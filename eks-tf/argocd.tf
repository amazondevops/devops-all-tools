# resource "kubernetes_namespace" "argocd" {
#   metadata {
#     name = "argocd"
#   }
#   depends_on = [aws_eks_node_group.argo]
# }

# resource "helm_release" "argocd" {
#   name       = "argocd"
#   namespace  = kubernetes_namespace.argocd.metadata[0].name
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   version    = "7.7.0"

#   depends_on = [
#     aws_eks_node_group.argo,
#     aws_eks_addon.coredns,
#   ]
# }

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  depends_on = [aws_eks_node_group.argo]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.0"

  values = [yamlencode({
    server = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internal"
          "service.beta.kubernetes.io/aws-load-balancer-subnets"  = join(",", var.private_subnet_ids)
        }
      }
    }
  })]

  depends_on = [
    aws_eks_node_group.argo,
    aws_eks_addon.coredns,
    helm_release.lbc,
  ]
}