#!/usr/bin/env bash
#
# Recover billing after the kill switch has triggered.
#
# This script:
#   1. Disables the kill switch function (scales Cloud Run to 0)
#   2. Re-enables billing on the project
#   3. Optionally re-enables the kill switch when you're ready
#
# Without step 1, re-enabling billing would immediately trigger the
# kill switch again because the budget alerts keep firing until the
# next billing cycle.
#
# Usage:
#   ./scripts/recover-billing.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these or pass as environment variables
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||')}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-billing-kill-switch}"

# If billing is already disabled, the billing account won't be in the project info.
# Fall back to terraform state or manual input.
if [ -z "$BILLING_ACCOUNT" ]; then
  if [ -f "$(dirname "$0")/../terraform/terraform.tfvars" ]; then
    BILLING_ACCOUNT=$(grep billing_account "$(dirname "$0")/../terraform/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/')
  fi
fi

if [ -z "$PROJECT_ID" ] || [ -z "$BILLING_ACCOUNT" ]; then
  echo "ERROR: Could not determine PROJECT_ID or BILLING_ACCOUNT."
  echo "Set them as environment variables:"
  echo "  PROJECT_ID=your-project BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0"
  exit 1
fi

echo "Project:         $PROJECT_ID"
echo "Billing account: $BILLING_ACCOUNT"
echo "Region:          $REGION"
echo "Function:        $FUNCTION_NAME"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Disable the kill switch
# ---------------------------------------------------------------------------
echo ">>> Step 1: Disabling kill switch (scaling Cloud Run service to 0)..."
gcloud run services update "$FUNCTION_NAME" \
  --max-instances=0 \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --quiet

echo "    Kill switch disabled. Budget alerts will no longer trigger billing removal."
echo ""

# ---------------------------------------------------------------------------
# Step 2: Re-enable billing
# ---------------------------------------------------------------------------
echo ">>> Step 2: Re-enabling billing..."
gcloud billing projects link "$PROJECT_ID" \
  --billing-account="$BILLING_ACCOUNT"

echo "    Billing re-enabled."
echo ""

# ---------------------------------------------------------------------------
# Step 3: Optionally re-enable the kill switch
# ---------------------------------------------------------------------------
echo ">>> Step 3: Re-enable the kill switch?"
echo ""
echo "    The kill switch is currently DISABLED. Budget alerts will not"
echo "    trigger billing removal until you re-enable it."
echo ""
echo "    You may want to wait until the next billing cycle, or after"
echo "    you've adjusted your budget threshold."
echo ""
read -rp "    Re-enable the kill switch now? [y/N] " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo ""
  echo "    Re-enabling kill switch..."
  gcloud run services update "$FUNCTION_NAME" \
    --max-instances=1 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --quiet
  echo "    Kill switch re-enabled."
else
  echo ""
  echo "    Kill switch remains disabled. Re-enable it later with:"
  echo "    gcloud run services update $FUNCTION_NAME --max-instances=1 --region=$REGION --project=$PROJECT_ID"
fi

echo ""
echo "Done."
