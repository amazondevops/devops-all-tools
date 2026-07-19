data "tls_certificate" "oidc" {
  url = aws_eks_cluster.poc.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.poc.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}