variable "project_id" {
  description = "The GCP project ID where resources are created and billing will be disabled if budget is exceeded."
  type        = string
}

variable "project_number" {
  description = "The GCP project number (numeric). Find via: gcloud projects describe PROJECT_ID --format='value(projectNumber)'"
  type        = string
}

variable "region" {
  description = "The GCP region for the Cloud Function and related resources."
  type        = string
  default     = "us-central1"
}

variable "billing_account" {
  description = "The billing account ID (format: XXXXXX-XXXXXX-XXXXXX). Find via: gcloud billing accounts list"
  type        = string
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount. When spending reaches this amount, billing is disabled."
  type        = number
}

variable "monthly_budget_currency" {
  description = "The 3-letter ISO 4217 currency code for the budget. Must match the billing account's currency. Find via: gcloud billing accounts describe BILLING_ACCOUNT_ID --format='value(currencyCode)'"
  type        = string
}
