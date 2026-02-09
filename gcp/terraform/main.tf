terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Enable required APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "cloudbilling" {
  project            = var.project_id
  service            = "cloudbilling.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  project            = var.project_id
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "billingbudgets" {
  project            = var.project_id
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Pub/Sub topic for budget alerts
# ---------------------------------------------------------------------------

resource "google_pubsub_topic" "billing_alerts" {
  name    = "billing-alerts"
  project = var.project_id

  depends_on = [google_project_service.pubsub]
}

# ---------------------------------------------------------------------------
# Service account for the Cloud Function
# ---------------------------------------------------------------------------

resource "google_service_account" "billing_kill_switch" {
  account_id   = "billing-kill-switch"
  display_name = "Billing Kill Switch Cloud Function"
  project      = var.project_id
}

# ---------------------------------------------------------------------------
# IAM bindings
# ---------------------------------------------------------------------------

# Allow the function to unlink the billing account from the project.
resource "google_project_iam_member" "billing_project_manager" {
  project = var.project_id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${google_service_account.billing_kill_switch.email}"
}

# Allow the function to check current billing status.
resource "google_billing_account_iam_member" "billing_viewer" {
  billing_account_id = var.billing_account
  role               = "roles/billing.viewer"
  member             = "serviceAccount:${google_service_account.billing_kill_switch.email}"
}

# Allow the GCP budget system to publish notifications to the topic.
resource "google_pubsub_topic_iam_member" "budget_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.billing_alerts.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:billing-budgets@system.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Cloud Function source (GCS bucket + zip archive)
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-billing-kill-switch-source"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.cloudbuild]
}

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/../function"
  output_path = "${path.module}/../function.zip"
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# ---------------------------------------------------------------------------
# Cloud Function Gen 2
# ---------------------------------------------------------------------------

resource "google_cloudfunctions2_function" "billing_kill_switch" {
  name        = "billing-kill-switch"
  location    = var.region
  project     = var.project_id
  description = "Disables billing on the project when monthly spending exceeds the configured budget."

  build_config {
    runtime     = "python312"
    entry_point = "stop_billing"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 120
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    service_account_email = google_service_account.billing_kill_switch.email

    environment_variables = {
      GCP_PROJECT = var.project_id
    }

    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.billing_alerts.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.run,
    google_project_service.cloudbuild,
    google_project_service.eventarc,
    google_project_service.pubsub,
  ]
}

# ---------------------------------------------------------------------------
# Billing budget with Pub/Sub notification
# ---------------------------------------------------------------------------

resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account
  display_name    = "${var.project_id} monthly billing kill switch"

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.monthly_budget_currency
      units         = tostring(var.monthly_budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic                   = google_pubsub_topic.billing_alerts.id
    schema_version                 = "1.0"
    disable_default_iam_recipients = false
  }

  depends_on = [
    google_project_service.billingbudgets,
    google_pubsub_topic_iam_member.budget_publisher,
  ]
}
