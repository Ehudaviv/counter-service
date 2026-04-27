resource "aws_eks_node_group" "system_nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system-node-group"
  
  node_role_arn   = aws_iam_role.karpenter_node.arn 
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  instance_types = ["t4g.medium"]
  # Updated to Amazon Linux 2023 to support EKS 1.34
  ami_type       = "AL2023_ARM_64_STANDARD"

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_node_policies
  ]
}