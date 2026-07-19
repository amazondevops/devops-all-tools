output "cluster_name" {
  value = aws_eks_cluster.poc.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.poc.endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.poc.name}"
}

output "argocd_admin_password_command" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}