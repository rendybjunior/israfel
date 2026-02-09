"""GCP Billing Kill Switch Cloud Function.

Triggered by Pub/Sub budget notifications. When the reported cost
equals or exceeds the budget amount, this function disables billing
on the project by unlinking its billing account.

WARNING: Disabling billing will stop ALL billable GCP services in
the project. This is intentionally destructive as a cost-control
measure of last resort.
"""

import base64
import json
import os

import functions_framework
from cloudevents.http.event import CloudEvent
from google.cloud import billing_v1


PROJECT_ID = os.environ.get("GCP_PROJECT")
PROJECT_NAME = f"projects/{PROJECT_ID}"

billing_client = billing_v1.CloudBillingClient()


@functions_framework.cloud_event
def stop_billing(cloud_event: CloudEvent) -> None:
    """Entry point. Receives a CloudEvent from a Pub/Sub budget alert.

    Decodes the message, compares costAmount to budgetAmount, and
    disables billing if cost >= budget.
    """
    if not PROJECT_ID:
        print("ERROR: GCP_PROJECT environment variable is not set. Aborting.")
        return

    try:
        pubsub_data = base64.b64decode(
            cloud_event.data["message"]["data"]
        ).decode("utf-8")
        notification = json.loads(pubsub_data)
    except (KeyError, json.JSONDecodeError) as e:
        print(f"ERROR: Failed to decode budget notification: {e}")
        return

    cost_amount = notification.get("costAmount", 0)
    budget_amount = notification.get("budgetAmount", 0)
    budget_display_name = notification.get("budgetDisplayName", "Unknown")
    currency_code = notification.get("currencyCode", "USD")

    print(
        f"Budget notification received: '{budget_display_name}' - "
        f"Cost: {cost_amount} {currency_code}, "
        f"Budget: {budget_amount} {currency_code}"
    )

    if cost_amount < budget_amount:
        print(
            f"No action needed. Current cost ({cost_amount}) is below "
            f"budget ({budget_amount})."
        )
        return

    print(
        f"ALERT: Cost ({cost_amount}) has reached or exceeded budget "
        f"({budget_amount}). Proceeding to disable billing."
    )

    if not _is_billing_enabled(PROJECT_NAME):
        print(f"Billing is already disabled on {PROJECT_NAME}. No action taken.")
        return

    _disable_billing(PROJECT_NAME)


def _is_billing_enabled(project_name: str) -> bool:
    """Check whether billing is currently enabled for the project.

    Defaults to True on error (fail-open towards disabling billing,
    which is the safer direction for cost control).
    """
    try:
        response = billing_client.get_project_billing_info(name=project_name)
        return response.billing_enabled
    except Exception as e:
        print(
            f"WARNING: Could not determine billing status for "
            f"{project_name}: {e}. Assuming billing is enabled."
        )
        return True


def _disable_billing(project_name: str) -> None:
    """Disable billing by setting billingAccountName to empty.

    This unlinks the billing account from the project, causing GCP
    to stop all billable services.
    """
    try:
        project_billing_info = billing_v1.ProjectBillingInfo(
            billing_account_name=""
        )
        response = billing_client.update_project_billing_info(
            name=project_name,
            project_billing_info=project_billing_info,
        )
        print(
            f"SUCCESS: Billing disabled on {project_name}. "
            f"Response: billing_enabled={response.billing_enabled}"
        )
    except Exception as e:
        print(f"ERROR: Failed to disable billing on {project_name}: {e}")
