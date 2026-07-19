# ---------------------------------------------------------------------------
# Dedicated security group for Karpenter-provisioned nodes (poc-eks).
# The EC2NodeClass discovers it via the karpenter.sh/discovery tag. It is
# attached alongside the EKS cluster security group (also discovery-tagged in
# karpenter.tf), which provides node <-> control-plane connectivity.
# ---------------------------------------------------------------------------
resource "aws_security_group" "karpenter_node" {
  name_prefix = "${var.cluster_name}-karpenter-node-"
  vpc_id      = var.vpc_id
  description = "Karpenter-managed node security group for ${var.cluster_name}"

  tags = {
    "Name"                   = "${var.cluster_name}-karpenter-node"
    "karpenter.sh/discovery" = var.cluster_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Node <-> node (pod networking, DNS, kube-proxy)
resource "aws_vpc_security_group_ingress_rule" "karpenter_node_self" {
  security_group_id            = aws_security_group.karpenter_node.id
  referenced_security_group_id = aws_security_group.karpenter_node.id
  ip_protocol                  = "-1"
  description                  = "node to node"
}

# EKS control plane / cluster SG -> node (kubelet 10250, webhooks, etc.)
resource "aws_vpc_security_group_ingress_rule" "karpenter_node_from_cluster" {
  security_group_id            = aws_security_group.karpenter_node.id
  referenced_security_group_id = aws_eks_cluster.poc.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "-1"
  description                  = "cluster control plane to node"
}

# Node -> anywhere (image pulls, AWS APIs, internet via NAT)
resource "aws_vpc_security_group_egress_rule" "karpenter_node_egress" {
  security_group_id = aws_security_group.karpenter_node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "all egress"
}

output "karpenter_node_security_group_id" {
  description = "Dedicated SG for Karpenter nodes (selected by the EC2NodeClass discovery tag)"
  value       = aws_security_group.karpenter_node.id
}
