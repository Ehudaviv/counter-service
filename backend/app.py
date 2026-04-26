import logging
import os
import time
from flask import Flask, jsonify, Response, g, request
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
log = logging.getLogger(__name__)

# --- OpenTelemetry Setup (Optional based on environment) ---
try:
    from opentelemetry import trace
    from opentelemetry.instrumentation.flask import FlaskInstrumentor
    from opentelemetry.instrumentation.requests import RequestsInstrumentor
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    OTEL_AVAILABLE = True
except ImportError:
    OTEL_AVAILABLE = False
    log.warning("Tracing disabled: OpenTelemetry packages not found.")

OTEL_ENABLED = os.getenv("OTEL_ENABLED", "false").lower() in ("1", "true", "yes", "on") and OTEL_AVAILABLE

app = Flask(__name__)

# --- Database Configuration ---
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_engine(
    DATABASE_URL,
    pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "2")),
    pool_pre_ping=True, # Validates connection before checking out of pool
    pool_recycle=300,
)

# --- Prometheus Metrics ---
REQUEST_COUNT = Counter("http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"])
REQUEST_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "endpoint"])
COUNTER_VALUE = Gauge("counter_value", "Current state of the counter")

# --- Tracing Initialization ---
if OTEL_ENABLED:
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if endpoint:
        resource = Resource.create({"service.name": "counter-backend", "deployment.environment": "prod"})
        tracer_provider = TracerProvider(resource=resource)
        tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces")))
        trace.set_tracer_provider(tracer_provider)
        
        FlaskInstrumentor().instrument_app(app)
        RequestsInstrumentor().instrument()
        SQLAlchemyInstrumentor().instrument(engine=engine)
        log.info(f"Tracing fully enabled and exporting to {endpoint}")

# --- DB Initialization ---
def init_db():
    try:
        with engine.begin() as conn:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS request_counter_state (
                    id INTEGER PRIMARY KEY,
                    value BIGINT NOT NULL DEFAULT 0
                );
            """))
            conn.execute(text("""
                INSERT INTO request_counter_state (id, value) VALUES (1, 0)
                ON CONFLICT (id) DO NOTHING;
            """))
            log.info("Database initialized successfully.")
    except SQLAlchemyError as e:
        log.error(f"Database initialization failed: {e}")

# --- Middleware ---
@app.before_request
def before_request():
    g.start_time = time.time()

@app.after_request
def after_request(response):
    latency = time.time() - getattr(g, "start_time", time.time())
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    REQUEST_LATENCY.labels(request.method, request.path).observe(latency)
    return response

# --- Routes ---
@app.route("/api/counter", methods=["GET"])
def get_counter():
    try:
        with engine.begin() as conn:
            val = conn.execute(text("SELECT value FROM request_counter_state WHERE id = 1")).scalar_one()
        COUNTER_VALUE.set(val)
        return jsonify({"value": val})
    except SQLAlchemyError as e:
        return jsonify({"error": "database error"}), 500

@app.route("/api/counter", methods=["POST"])
def increment_counter():
    try:
        with engine.begin() as conn:
            val = conn.execute(text("UPDATE request_counter_state SET value = value + 1 WHERE id = 1 RETURNING value;")).scalar_one()
        COUNTER_VALUE.set(val)
        return jsonify({"value": val})
    except SQLAlchemyError as e:
        return jsonify({"error": "database error"}), 500

@app.route("/healthz", methods=["GET"])
def healthz():
    # Deep health check - verifies DB connectivity
    try:
        with engine.begin() as conn:
            conn.execute(text("SELECT 1"))
        return jsonify({"status": "ok"})
    except SQLAlchemyError:
        return jsonify({"status": "degraded"}), 500

@app.route("/metrics", methods=["GET"])
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)