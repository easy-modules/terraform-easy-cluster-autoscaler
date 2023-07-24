#==============================================================================
# EXTERNAL SECRET IAM ROLES
#==============================================================================
data "aws_iam_policy_document" "kubernetes_cluster_autoscaler" {
  count = var.enabled ? 1 : 0

  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes"
    ]
    resources = [
      "*",
    ]
    effect = "Allow"
  }

}

resource "aws_iam_policy" "kubernetes_cluster_autoscaler" {
  depends_on  = [var.mod_dependency]
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler"
  path        = "/"
  description = "Policy for cluster autoscaler service"

  policy = data.aws_iam_policy_document.kubernetes_cluster_autoscaler[0].json
}

# Role
data "aws_iam_policy_document" "kubernetes_cluster_autoscaler_assume" {
  count = var.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_identity_oidc_issuer_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_identity_oidc_issuer, "https://", "")}:sub"

      values = [
        "system:serviceaccount:${var.namespace}:${var.service_account_name}",
      ]
    }

    effect = "Allow"
  }
}

#==============================================================================
# HELM CHART
#==============================================================================
resource "kubernetes_namespace" "cluster_autoscaler" {
  depends_on = [var.mod_dependency]
  count      = (var.enabled && var.create_namespace && var.namespace != "kube-system") ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "aws_iam_role" "kubernetes_cluster_autoscaler" {
  count              = var.enabled ? 1 : 0
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.kubernetes_cluster_autoscaler_assume[0].json
}

resource "aws_iam_role_policy_attachment" "kubernetes_cluster_autoscaler" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.kubernetes_cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.kubernetes_cluster_autoscaler[0].arn
}

resource "helm_release" "cluster_autoscaler" {
  depends_on = [var.mod_dependency, kubernetes_namespace.cluster_autoscaler]
  count      = var.enabled ? 1 : 0
  name       = var.helm_chart_name
  chart      = var.helm_chart_release_name
  repository = var.helm_chart_repo
  version    = var.helm_chart_version
  namespace  = var.namespace

  set {
    name  = "fullnameOverride"
    value = var.fullname_override
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = var.service_account_name
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.kubernetes_cluster_autoscaler[0].arn
  }

  values = [
    yamlencode(var.settings)
  ]
}
