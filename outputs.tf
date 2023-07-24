output "helm_chart_name" {
  description = "helm chart name"
  value       = helm_release.cluster_autoscaler[*].name
}

output "helm_chart_namespace" {
  description = "helm chart namespace"
  value       = helm_release.cluster_autoscaler[*].namespace
}
