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

### Zero-Downtime Resilience & Security
* **Topology Spread Constraints:** Pods are distributed across multiple Availability Zones to survive datacenter degradation.
* **Pod Disruption Budgets (PDBs):** Enforce a `minAvailable: 1` rule, guaranteeing that Kubernetes will never drain a node if it would cause complete downtime during voluntary maintenance (e.g., Karpenter spot instance rotation).
* **Probes:** Strict Liveness and Readiness probes ensure traffic is only routed to healthy application states.
* **Graceful Termination:** Configured `terminationGracePeriodSeconds` allows in-flight requests to complete before pods are rotated.
* **Read-Only Root Filesystems:** Containers are enforced with `readOnlyRootFilesystem: true`, mounting ephemeral `emptyDir` volumes only where necessary (`/tmp`). This protects against malicious script execution and unauthorized filesystem mutations if a container is compromised.

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
`./scripts/bootstrap.sh`

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

## Accessing the Services

Once the cluster is provisioned and Argo CD has synchronized the applications, you can extract the relevant URLs and access points using the commands below.

### 1. Counter Application (Frontend & API)
The application is exposed via an AWS Application Load Balancer. Run the following command in your terminal to extract the public hostname:
```bash
    kubectl get ingress counter-ingress -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
### 2. Grafana (Metrics & Dashboards)
Grafana is exposed via an AWS Load Balancer configured by the kube-prometheus-stack. Extract the URL using:
```bash
    kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
* **URL:** http://'your-grafana-loadbalancer-url'
* **Username:** admin
* **Password:** admin *(Configured via Terraform)*

### 3. Argo CD (GitOps Dashboard)
Argo CD is exposed publicly via an AWS Load Balancer. Extract the public hostname using:
```bash
    kubectl get svc argo-cd-argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
Next, extract the auto-generated admin password:
```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
* **URL:** https://'your-argocd-loadbalancer-url'
* **Username:** admin

### 4. AWS CloudWatch (Logs)
All standard output and error logs from the containers are aggregated via the CloudWatch Observability Add-on (FluentBit).

1. Log in to the **AWS Management Console**.
2. Navigate to **CloudWatch** -> **Logs** -> **Log groups**.
3. Select the log group: `/aws/containerinsights/ehud-counter-service/application`
4. Use **Logs Insights** to query and filter specific pod logs.

### 5. AWS X-Ray (Distributed Traces)
OpenTelemetry automatically instruments the Python backend to track requests to the PostgreSQL database.

1. Log in to the **AWS Management Console**.
2. Navigate to **CloudWatch** -> **X-Ray traces** -> **Service map**.
3. View the visual node graph mapping the request paths and latency between the application and the RDS instance.

## Choices and Trade-offs

### High Availability

| Mechanism | Implementation & Trade-off |
| :--- | :--- |
| **Multi-AZ Compute** | Karpenter is configured to provision nodes across `eu-west-2a` and `eu-west-2b`. **Trade-off:** Increases cross-AZ data transfer costs but ensures the cluster survives a single datacenter failure. |
| **Pod Distribution** | Deployments utilize `topologySpreadConstraints` to force pods onto different physical nodes and AZs. **Trade-off:** May leave small resource gaps on nodes, slightly reducing bin-packing efficiency in favor of resilience. |
| **Database Redundancy** | The RDS PostgreSQL instance is provisioned outside the cluster. **Trade-off:** Currently configured as Single-AZ to optimize cloud costs for this demonstration. In a true production tier, enabling `multi_az = true` in Terraform would add a standby replica to prevent the database from being a single point of failure (SPoF). |

### Auto-scaling

This architecture intentionally replaces native Kubernetes scaling tools with advanced, event-driven alternatives to optimize reaction time and cost.

| Approach | Choice vs. Native | Trade-off & Justification |
| :--- | :--- | :--- |
| **Node Scaling** | **Karpenter** (Chosen) vs. Cluster Autoscaler | **Justification:** Cluster Autoscaler relies on rigid, pre-defined Auto Scaling Groups (ASGs). Karpenter directly provisions raw EC2 compute Just-In-Time based on pod requirements. **Trade-off:** Requires more complex initial IAM and networking setup (SQS queues, Spot instance roles) but dramatically reduces scaling latency from minutes to seconds. |
| **Pod Scaling** | **KEDA** (Chosen) vs. HPA | **Justification:** Native HPA scales reactively based on CPU/Memory exhaustion. KEDA proactively scales based on HTTP request traffic (RPS) directly from Prometheus. **Trade-off:** Adds operational overhead (managing KEDA controllers and ServiceMonitors) but ensures pods scale up *before* CPU bottlenecks degrade the user experience. |

### Persistence & State

**Chosen approach: AWS RDS PostgreSQL**

The counter application requires absolute state consistency. A relational database was chosen to handle atomic increments (`UPDATE ... RETURNING value`) to prevent race conditions when multiple backend replicas handle requests simultaneously.

| Alternative | Pros | Cons (Why it was rejected) |
| :--- | :--- | :--- |
| **In-Cluster StatefulSet (PVC)** | Cheaper, contained entirely within Kubernetes. | Requires complex volume management, backup strategies, and node-affinity rules. If the cluster fails, data recovery is difficult. |
| **Redis / In-Memory** | Exceptionally fast read/write speeds. | Ephemeral by default. Requires complex AOF/RDB configuration for durability and another controller to operate within the cluster. |
| **AWS RDS (Chosen)** | Fully managed, decoupled from compute, automated backups, out-of-the-box encryption at rest. | Network latency is marginally higher than in-cluster storage, and carries a base hourly cloud cost regardless of usage. |