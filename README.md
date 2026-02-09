# Israfel

Cloud billing kill switches. Automatically disable billing when monthly spending exceeds a configured threshold, preventing runaway costs.

## Supported Clouds

| Cloud | Status | Mechanism |
|-------|--------|-----------|
| [GCP](gcp/) | Available | Cloud Function disables billing via Cloud Billing API |

## How It Works

Each cloud provider has its own directory with:
- **Terraform modules** to provision all required infrastructure (alerts, functions, IAM, etc.)
- **Function code** that receives billing notifications and disables billing when the threshold is breached

The kill switch is a last-resort safety net. Once triggered, all billable services in the project/account are stopped.

## Quick Start

### GCP

```bash
cd gcp/terraform

cat > terraform.tfvars <<EOF
project_id            = "your-project-id"
project_number        = "123456789012"
billing_account       = "XXXXXX-XXXXXX-XXXXXX"
monthly_budget_amount = 50
EOF

terraform init && terraform apply
```

See [gcp/README.md](gcp/README.md) for full setup instructions.

## Important Caveats

- Budget notifications can be delayed by several hours — set thresholds conservatively below your true maximum acceptable spend.
- Disabling billing stops **all** billable services, including the kill switch infrastructure itself. This is by design.
- This is a safety net, not a precision tool. It will not catch micro-second billing spikes in real time.
