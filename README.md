# Counter Service — Enterprise-Grade Kubernetes Deployment

A highly resilient, fully observable counter microservice deployed on AWS EKS. This project demonstrates advanced DevOps principles, utilizing GitOps, dynamic Just-In-Time (JIT) node provisioning, event-driven autoscaling, and secure external secrets management.

---

## Architecture & Technology Stack

```text
User Request
  └── AWS Application Load Balancer (ALB / Ingress)
        ├── Nginx Frontend (Static HTML + Reverse Proxy)
        └── Python Backend (Port 8080)
              └── AWS RDS PostgreSQL (Persistent State)

| Component | Technology Choice | Highlight |
| :--- | :--- | :--- |
| **Cluster Management** | AWS EKS (v1.34) | Managed control plane with Graviton (ARM64) support. |
| **Node Autoscaling** | **Karpenter** | JIT node provisioning, replacing standard Cluster Autoscaler for faster, constraint-based scaling. |
| **Pod Autoscaling** | **KEDA** | Event-driven scaling based on custom Prometheus HTTP Request metrics (RPS), bypassing standard CPU-based HPA. |
| **GitOps Delivery** | Argo CD + Helm | Declarative, self-healing continuous deployment directly from Git source. |
| **Secrets Management** | **External Secrets Operator** | Securely syncs RDS credentials from AWS Secrets Manager into native Kubernetes Secrets. |
| **Infrastructure** | Terraform | Modular IaC defining VPC, EKS, NodeGroups, IAM OIDC, and Karpenter profiles. |
| **CI Pipeline** | GitHub Actions | Builds and pushes multi-architecture (AMD64/ARM64) images to ECR. |
| **Observability** | Prometheus, Grafana, OpenTelemetry | Full metric scraping, CloudWatch log aggregation, and X-Ray distributed tracing. |

## Repository Structure

```text
.
├── backend/                 # Python backend service, Dockerfile, and requirements
├── evidence/                # Screenshots of metrics, traces, scaling, and pipelines
├── frontend/                # Nginx configuration, static UI assets, and Dockerfile
├── helm/
│   └── counter-service/     # Unified Helm chart (App, KEDA scaled objects, ESO stores)
├── manifests/               # Declarative cluster definitions
│   ├── argocd-app.yaml      # Argo CD Application configuration for GitOps sync
│   └── karpenter-pool.yaml  # Karpenter provisioning rules (EC2NodeClass & NodePool)
├── scripts/
│   └── bootstrap.sh         # Pre-flight environment setup and IAM spot-role injection
└── terraform/               # Modular AWS Infrastructure as Code
    ├── controllers.tf       # Helm releases for ALB, Karpenter, ESO, and Prometheus
    ├── eks.tf               # Cluster control plane and IRSA OIDC configurations
    ├── network.tf           # VPC, subnets, and node discovery tagging
    └── nodegroup.tf         # Baseline managed node group for system controllers

## Deployment Workflow

### 1. Infrastructure as Code (Terraform)
Infrastructure is deployed via GitHub Actions using OpenID Connect (OIDC) for passwordless authentication to AWS. The Terraform configuration handles:
* **VPC & Networking:** Private/Public subnets tagged for ALB and Karpenter discovery.
* **EKS Cluster:** Provisioned with OIDC integration for IAM Roles for Service Accounts (IRSA).
* **Controllers:** AWS Load Balancer Controller, Karpenter, External Secrets Operator, and Kube-Prometheus-Stack.

### 2. Continuous Integration (CI)
On code changes to the `main` branch, the `.github/workflows/docker-build.yaml` pipeline triggers automatically:
1.  Builds multi-architecture Docker images (`linux/amd64`, `linux/arm64`).
2.  Pushes images to Amazon ECR.
3.  Updates the Helm `values.yaml` file with the new image tags and commits the change.

### 3. Continuous Deployment (GitOps)
Argo CD constantly monitors the repository. Once the CI pipeline commits the new image tags to the Helm chart, Argo CD automatically synchronizes the cluster state, performing a rolling update of the pods without manual intervention.

## Advanced DevOps Capabilities

### Secrets Management (ESO)
To adhere to strict security compliance, **no secrets are stored in Git**. 
Instead, the Terraform layer generates the RDS database password and stores it in AWS Secrets Manager. The **External Secrets Operator (ESO)** running in the cluster authenticates via IRSA, fetches the secret dynamically, and injects it into a Kubernetes Secret consumed by the backend deployment.

### Event-Driven Autoscaling (KEDA)
Standard Horizontal Pod Autoscalers (HPA) scale purely on CPU/Memory utilization, which often lags behind sudden traffic spikes. This architecture leverages **KEDA (Kubernetes Event-driven Autoscaling)**. KEDA queries Prometheus for the live `http_requests_total` metric. If the Requests Per Second (RPS) threshold is breached, KEDA dynamically overrides the deployment replicas, scaling the backend from 2 to 10 pods.

### Just-In-Time Node Provisioning (Karpenter)
Standard Kubernetes NodeGroups are static and slow to scale. This project utilizes **Karpenter**. When KEDA requests additional pods during a load event, the default nodes may become congested. Karpenter detects `Unschedulable` pods, evaluates the resource requests, and provisions a right-sized EC2 spot instance in seconds to absorb the load.

### Zero-Downtime Resilience
* **Topology Spread Constraints:** Pods are distributed across multiple Availability Zones to survive datacenter degradation.
* **Probes:** Strict Liveness and Readiness probes ensure traffic is only routed to healthy application states.
* **Graceful Termination:** Configured `terminationGracePeriodSeconds` allows in-flight requests to complete before pods are rotated.

## Observability

Full-stack observability is integrated by default, capturing the "Three Pillars" of system health:

* **Metrics:** A complete `kube-prometheus-stack` scrapes application endpoints via a defined `ServiceMonitor`. Custom dashboards in Grafana track RPS, memory footprint, and custom business metrics.
* **Traces:** The Python backend is instrumented with OpenTelemetry. Traces are exported to the AWS CloudWatch agent and visualized in **AWS X-Ray**, mapping the exact latency between the Python application and the RDS PostgreSQL database.
* **Logs:** FluentBit aggregates all container stdout/stderr streams and ships them to centralized CloudWatch Log Groups for persistent querying via Logs Insights.

## Evidence Directory

The `evidence/` directory contains visual proof of the operational capabilities, infrastructure state, and observability integrations of the Counter Service cluster.

* **`01-ci-build-success.png`**: Demonstrates the GitHub Actions CI pipeline successfully building and pushing multi-architecture Docker images to Amazon ECR.
* **`02-cd-gitops-sync.png`**: Shows ArgoCD actively managing the cluster state, maintaining a healthy and synced GitOps deployment pipeline.
* **`03-app-network-resources.png`**: Validates the core Kubernetes network topology, showing the running pods, ClusterIP services, AWS ALB Ingress, and the initial KEDA state.
* **`04-resilience-extras.png`**: Highlights the production-readiness of the pod specifications, including strict resource requests/limits, liveness/readiness probes, and topology spread constraints.
* **`05-persistence-proof.png`**: Proves state persistence by showing the database retaining the counter value even after the backend pods are manually deleted and recreated.
* **`06-KEDA-Scaling-Up.png`**: Demonstrates the event-driven autoscaler (KEDA) intercepting custom Prometheus metrics to successfully scale the backend deployment in response to simulated load.
* **`07-karpenter-scaling.png`**: Captures Karpenter dynamically provisioning a new EC2 node (JIT provisioning) in response to unschedulable pods caused by a resource bottleneck.
* **`08-eso-secrets.png`**: Validates the External Secrets Operator securely fetching the RDS database credentials from AWS Secrets Manager and injecting them as native Kubernetes secrets.
* **`09-xray-service-map.png`**: Displays the AWS X-Ray service map, proving OpenTelemetry auto-instrumentation is actively capturing distributed traces between the Python backend and the PostgreSQL database.
* **`10-grafana-metrics.png`**: Shows the Grafana dashboard querying Prometheus, confirming the successful scraping and visualization of cluster compute metrics.
* **`11-cloudwatch-logs.png`**: Demonstrates centralized log aggregation via CloudWatch Logs Insights, proving pod logs are persistently stored and actively searchable.