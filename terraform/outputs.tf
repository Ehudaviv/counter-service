# 1. The Application URL
output "application_url" {
  value       = "http://${data.aws_lb.counter.dns_name}"
  description = "The public URL of the Counter Service"
}

# 2. The Grafana URL
output "grafana_url" {
  value       = "http://${data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].hostname}"
  description = "The public URL for Grafana Dashboards"
}

# 3. The ArgoCD URL
output "argocd_url" {
  value       = "https://${data.kubernetes_service_v1.argocd.status[0].load_balancer[0].ingress[0].hostname}"
  description = "The UI for GitOps deployments"
}

# 4. The CloudWatch Log Group
output "cloudwatch_log_group" {
  value       = "/aws/containerinsights/${var.cluster_name}/application"
  description = "The AWS CloudWatch Log Group for pod logs"
}