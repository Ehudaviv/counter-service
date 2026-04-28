# Counter Service - Enterprise-Grade Kubernetes Deployment

A highly resilient, fully observable counter microservice deployed on AWS EKS. This project demonstrates advanced DevOps principles, utilizing GitOps, dynamic Just-In-Time (JIT) node provisioning, event-driven autoscaling, and secure external secrets management.

---

## Architecture & Technology Stack

```text
User Request
  └── AWS Application Load Balancer (ALB / Ingress)
        ├── Nginx Frontend (Static HTML + Reverse Proxy)
        └── Python Backend (Port 8080)
              └── AWS RDS PostgreSQL (Persistent State)
```

| Component | Technology Choice | Highlight |
| :--- | :--- | :--- |
| **Cluster Management** | AWS EKS (v1.34) | Managed control plane with Graviton (ARM64) support. |
| **Node Autoscaling** | Karpenter | JIT node provisioning, replacing standard Cluster Autoscaler for faster, constraint-based scaling. |
| **Pod Autoscaling** | KEDA | Event-driven scaling based on custom Prometheus HTTP Request metrics (RPS), bypassing standard CPU-based HPA. |
| **GitOps Delivery** | Argo CD + Helm | Declarative, self-healing continuous deployment directly from Git source. |
| **Secrets Management** | External Secrets Operator | Securely syncs RDS credentials from AWS Secrets Manager into native Kubernetes Secrets. |
| **Infrastructure** | Terraform | Modular IaC defining VPC, EKS, NodeGroups, IAM OIDC, and Karpenter profiles. |
| **CI Pipeline** | GitHub Actions | Builds and pushes multi-architecture (AMD64/ARM64) images to ECR. |
| **Observability** | Prometheus, Grafana, OpenTelemetry | Full metric scraping, CloudWatch log aggregation, and X-Ray distributed tracing. |

## Repository Structure

```text
.
├── README.md                      # Project documentation
├── backend/                       # Python backend service, Dockerfile, and requirements
├── docker-compose.yaml            # Local development orchestration
├── evidence/                      # Screenshots of metrics, traces, scaling, and pipelines
├── frontend/                      # Nginx configuration, static UI assets, and Dockerfile
├── helm/
│   └── counter-service/           # Unified Helm chart (App, KEDA scaled objects, ESO stores)
├── legacy-counter-service/        # Original un-containerized script
├── manifests/                     # Declarative cluster definitions
│   ├── argocd-app.yaml            # Argo CD Application configuration for GitOps sync
│   └── karpenter-pool.yaml        # Karpenter provisioning rules (EC2NodeClass & NodePool)
├── scripts/
│   └── bootstrap.sh               # Pre-flight environment setup and IAM spot-role injection
└── terraform/                     # Modular AWS Infrastructure as Code
    ├── controllers.tf             # Helm releases for ALB, Karpenter, ESO, and Prometheus
    ├── data.tf                    # AWS data source lookups
    ├── eks.tf                     # Cluster control plane and IRSA OIDC configurations
    ├── karpenter.tf               # Karpenter IAM roles and SQS queues
    ├── network.tf                 # VPC, subnets, and node discovery tagging
    ├── nodegroup.tf               # Baseline managed node group for system controllers
    ├── providers.tf               # Terraform AWS and Kubernetes providers
    └── variables.tf               # Infrastructure variables configuration

```

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

## Provisioning the Cluster

This section outlines the exact steps taken to provision the original environment and serves as a reproducible guide for deploying this architecture into a new AWS account.

### Step 1: Pre-flight Configuration
Before provisioning the infrastructure, a new user must fork this repository and update the hardcoded AWS Account IDs to match their own environment.

1. **Fork the repository** to your own GitHub account.
2. **Update the Bootstrap Script:** Open `scripts/bootstrap.sh` and update the `VCS_ORG` variable to match your GitHub username or organization.
3. **Update GitHub Actions:** In both `.github/workflows/terraform-infra.yaml` and `.github/workflows/docker-build.yaml`, locate the `role-to-assume` ARN and replace `630943284793` with your target AWS Account ID.

### Step 2: Bootstrap AWS Foundations (One-Time Execution)
To maintain security best practices, this project relies on temporary OIDC credentials rather than static IAM access keys. A foundational bootstrap script must be run locally to prepare the AWS account.

Execute the following command using an AWS CLI profile with administrative privileges:
./scripts/bootstrap.sh

**What this script does:**
* Provisions an S3 Bucket (`ehud-counter-service-tfstate`) and a DynamoDB table for secure, locked Terraform remote state management.
* Registers GitHub as an OpenID Connect (OIDC) identity provider in the AWS account.
* Creates the `ehud-counter-service-terraform-ci` IAM role, granting the GitHub Actions pipeline permissions to execute Terraform.
* Creates the `ehud-counter-service-github-actions-role` IAM role, granting the pipeline permissions to push built Docker images to Amazon ECR.
* Manually provisions the EC2 Spot Instance Service-Linked Role required for Karpenter to function.

### Step 3: Infrastructure Provisioning via CI/CD
Once the foundational roles are established, the entire AWS infrastructure is deployed declaratively via GitHub Actions.

1. Navigate to the **Actions** tab in your GitHub repository.
2. Select the **Infrastructure Provisioning (Infra Layer)** workflow.
3. Click **Run workflow**, leaving the action set to `apply`.

**What this workflow does:**
* Authenticates to AWS securely via OIDC.
* Executes `terraform apply` to provision the VPC, Subnets, EKS Control Plane, managed NodeGroups, IAM roles for service accounts (IRSA), and RDS PostgreSQL database.
* Installs core cluster controllers via Helm (AWS Load Balancer Controller, Karpenter, External Secrets Operator, and Kube-Prometheus-Stack).
* Automatically applies the baseline Kubernetes manifests (`manifests/karpenter-pool.yaml` and `manifests/argocd-app.yaml`) to the new cluster.

### Step 4: Application Deployment (GitOps)
After the infrastructure pipeline completes, the cluster is fully operational. Argo CD is actively running inside the cluster and monitoring the repository for state changes. 

To deploy the application:
1. Navigate to the **Actions** tab and manually trigger the **Docker Build & Push** workflow (or simply push a new commit to the `main` branch).
2. The pipeline will build the multi-architecture images, push them to the newly created ECR repositories, and commit the updated image tags back to the Helm `values.yaml` file.
3. Argo CD will immediately detect the commit and synchronize the cluster state, deploying the backend, frontend, KEDA scaled objects, and External Secret stores without any manual intervention.

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