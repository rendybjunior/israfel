# GCP Billing Kill Switch

Automatically disables billing on a GCP project when monthly spending reaches a configured budget threshold.

## Architecture

```
GCP Budget Alert (thresholds at 50%, 90%, 100%)
       │
       ▼
Pub/Sub Topic: "billing-alerts"
       │
       ▼
Cloud Function Gen 2 (Python 3.12): "billing-kill-switch"
       │  costAmount >= budgetAmount?
       ▼
Cloud Billing API → unlink billing account → all billable services stopped
```

## Components

| Resource | Purpose |
|----------|---------|
| `google_billing_budget` | Monitors monthly spending; publishes to Pub/Sub at 50%, 90%, 100% thresholds |
| `google_pubsub_topic` | Receives budget alert notifications |
| `google_cloudfunctions2_function` | Parses alerts and disables billing when threshold is breached |
| `google_service_account` | Dedicated SA with minimal permissions for the function |
| IAM bindings | `roles/billing.projectManager` (project), `roles/billing.viewer` (billing account) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) (keep up to date via `gcloud components update`)
- Authenticated via `gcloud auth application-default login`
- The authenticated user must have:
  - `roles/owner` or `roles/editor` on the GCP project
  - `roles/billing.admin` on the billing account

## Setup

### 1. Configure variables

Copy the example and fill in your values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Use these commands to find the values:

```bash
gcloud config get-value project                                                      # project_id
gcloud projects describe PROJECT_ID --format='value(projectNumber)'                  # project_number
gcloud billing accounts list                                                         # billing_account
gcloud billing accounts describe BILLING_ACCOUNT_ID --format='value(currencyCode)'   # monthly_budget_currency
```

Edit `terraform/terraform.tfvars`:

```hcl
project_id              = "your-project-id"
project_number          = "123456789012"
billing_account         = "XXXXXX-XXXXXX-XXXXXX"
monthly_budget_amount   = 50
monthly_budget_currency = "IDR"  # Must match your billing account's currency
```

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID (string) |
| `project_number` | GCP project number (numeric) |
| `billing_account` | Billing account ID (format: `XXXXXX-XXXXXX-XXXXXX`) |
| `monthly_budget_amount` | Spending cap in the billing account's currency |
| `monthly_budget_currency` | **Must match your billing account's currency** (e.g. `USD`, `IDR`, `EUR`) |
| `region` | GCP region (optional, default: `us-central1`) |

### 2. Deploy

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Verify

Check that all resources were created:

```bash
terraform output
```

## Testing

### Simulate an over-budget notification

```bash
gcloud pubsub topics publish billing-alerts --message='{
  "budgetDisplayName": "Test Budget",
  "costAmount": 100.50,
  "budgetAmount": 100.00,
  "budgetAmountType": "SPECIFIED_AMOUNT",
  "currencyCode": "IDR",
  "costIntervalStart": "2024-01-01T08:00:00Z",
  "alertThresholdExceeded": 1.0
}'
```

### Simulate an under-budget notification (should NOT trigger)

```bash
gcloud pubsub topics publish billing-alerts --message='{
  "budgetDisplayName": "Test Budget",
  "costAmount": 40.00,
  "budgetAmount": 100.00,
  "budgetAmountType": "SPECIFIED_AMOUNT",
  "currencyCode": "IDR",
  "costIntervalStart": "2024-01-01T08:00:00Z",
  "alertThresholdExceeded": 0.5
}'
```

### Check function logs

```bash
gcloud functions logs read billing-kill-switch --region=us-central1 --gen2 --limit=20
```

### Check billing status

```bash
gcloud billing projects describe PROJECT_ID
```

### Re-enable billing after a test

```bash
./scripts/recover-billing.sh
```

This script:

1. Disables the kill switch (scales the Cloud Run service to 0) so budget alerts don't re-trigger it
2. Re-links the billing account to the project
3. Asks if you want to re-enable the kill switch

Without step 1, re-enabling billing would immediately trigger the kill switch again because budget alerts keep firing until the next billing cycle.

## How the Function Works

1. Receives a CloudEvent from Pub/Sub containing a budget notification
2. Decodes the base64-encoded message and parses the JSON payload
3. Compares `costAmount` against `budgetAmount`
4. If cost < budget: logs and exits (no action)
5. If cost >= budget: checks if billing is already disabled (idempotent), then calls the Cloud Billing API to unlink the billing account from the project

### Safety properties

- **Idempotent** — checks billing status before attempting to disable; safe to receive duplicate messages
- **Fail-open towards disabling** — if the billing status check fails, assumes billing is enabled and proceeds (safer direction for cost control)
- **No retry** — uses `RETRY_POLICY_DO_NOT_RETRY` to avoid infinite loops; the budget system naturally re-sends on subsequent threshold checks

## Important Caveats

1. **Notifications are delayed.** GCP budget alerts can lag by several hours. Set your budget conservatively below your true maximum acceptable spend.
2. **All services stop.** Disabling billing halts every billable service in the project, including this kill switch. This is intentional.
3. **IAM propagation delay.** After deployment, IAM bindings can take up to 7 minutes to propagate. Wait before testing.

## Cleanup

```bash
cd terraform
terraform destroy
```
