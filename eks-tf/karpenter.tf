# ---------------------------------------------------------------------------
# Karpenter AWS prerequisites for the `poc-eks` cluster.
# Karpenter itself is installed via ArgoCD (helm chart) - this file only
# creates the AWS-side resources the chart needs to exist beforehand:
#
#   1. SQS interruption queue + EventBridge rules (spot interruption, rebalance,
#      instance state-change, health events) so Karpenter can drain nodes early.
#   2. Karpenter *controller* IAM role (IRSA) + scoped policy  -> assumed by the
#      karpenter controller pod via its ServiceAccount.
#   3. Karpenter *node* IAM role (+ EKS access entry so nodes can join the
#      cluster) -> referenced by the EC2NodeClass `role:` field.
#   4. karpenter.sh/discovery tags on the private subnets and cluster security
#      group so the EC2NodeClass can discover them by tag.
#
# The values that must be plugged into the helm value files are printed as
# outputs at the bottom.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

variable "karpenter_namespace" {
  description = "Namespace the Karpenter controller runs in"
  default     = "karpenter"
}

variable "karpenter_service_account" {
  description = "ServiceAccount name used by the Karpenter controller (must match helm serviceAccount.name)"
  default     = "karpenter"
}

locals {
  karpenter_queue_name    = "Karpenter-${var.cluster_name}"
  oidc_provider_condition = replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")
}

# ---------------------------------------------------------------------------
# 1. Interruption SQS queue + EventBridge rules
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "karpenter" {
  name                      = local.karpenter_queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    sid       = "SqsWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

locals {
  karpenter_event_rules = {
    health = {
      name          = "HealthEvent"
      event_pattern = jsonencode({ source = ["aws.health"], detail-type = ["AWS Health Event"] })
    }
    spot_interruption = {
      name          = "SpotInterruption"
      event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] })
    }
    rebalance = {
      name          = "RebalanceRecommendation"
      event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] })
    }
    instance_state_change = {
      name          = "InstanceStateChange"
      event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] })
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each      = local.karpenter_event_rules
  name_prefix   = "Karpenter-${each.value.name}-"
  event_pattern = each.value.event_pattern
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_event_rules
  rule     = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn      = aws_sqs_queue.karpenter.arn
}

# ---------------------------------------------------------------------------
# 2. Karpenter node IAM role (assumed by Karpenter-launched EC2 instances)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "karpenter_node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "KarpenterNodeRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume.json
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

# Let Karpenter-launched nodes register with the cluster (EKS access entry API).
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.poc.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# ---------------------------------------------------------------------------
# 3. Karpenter controller IAM role (IRSA) + scoped policy
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_condition}:sub"
      values   = ["system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_condition}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "KarpenterController-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

# Official Karpenter v1.x controller policy, scoped to this cluster / region / queue.
resource "aws_iam_policy" "karpenter_controller" {
  name = "KarpenterController-${var.cluster_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:subnet/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
        ]
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
            "ec2:CreateAction"                                         = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*"
        Action   = "ec2:CreateTags"
        Condition = {
          StringEquals         = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike           = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
          StringEqualsIfExists = { "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
        ]
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter.arn
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      },
      {
        Sid       = "AllowPassingInstanceRole"
        Effect    = "Allow"
        Resource  = aws_iam_role.karpenter_node.arn
        Action    = "iam:PassRole"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = "iam:CreateInstanceProfile"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"             = var.region
          }
          StringLike = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = "iam:TagInstanceProfile"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.region
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"  = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                       = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"              = var.region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.region
          }
          StringLike = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = "iam:GetInstanceProfile"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = aws_eks_cluster.poc.arn
        Action   = "eks:DescribeCluster"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# ---------------------------------------------------------------------------
# 4. Discovery tags so the EC2NodeClass can find subnets / security group
# ---------------------------------------------------------------------------
resource "aws_ec2_tag" "subnet_discovery" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.poc.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# ---------------------------------------------------------------------------
# Outputs -> plug these into the helm value files
# ---------------------------------------------------------------------------
output "karpenter_controller_role_arn" {
  description = "Set as serviceAccount.annotations.eks.amazonaws.com/role-arn"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_role_name" {
  description = "Set as the EC2NodeClass `role:` value"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue_name" {
  description = "Set as settings.interruptionQueue (string)"
  value       = aws_sqs_queue.karpenter.name
}

output "karpenter_discovery_tag" {
  description = "Tag key=value used by EC2NodeClass subnet/securityGroup selectorTerms"
  value       = "karpenter.sh/discovery=${var.cluster_name}"
}
