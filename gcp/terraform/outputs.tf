output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic receiving budget alerts."
  value       = google_pubsub_topic.billing_alerts.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the Pub/Sub topic."
  value       = google_pubsub_topic.billing_alerts.id
}

output "cloud_function_name" {
  description = "The name of the billing kill switch Cloud Function."
  value       = google_cloudfunctions2_function.billing_kill_switch.name
}

output "cloud_function_uri" {
  description = "The URI of the deployed Cloud Function."
  value       = google_cloudfunctions2_function.billing_kill_switch.service_config[0].uri
}

output "service_account_email" {
  description = "The email of the service account used by the Cloud Function."
  value       = google_service_account.billing_kill_switch.email
}

output "budget_name" {
  description = "The resource name of the billing budget."
  value       = google_billing_budget.monthly_budget.name
}
