#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


# Locate the project root independently of the current terminal directory.
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# Define the Terraform directory and generated Ansible variables file.
TERRAFORM_DIR = PROJECT_ROOT / "terraform"
OUTPUT_FILE = PROJECT_ROOT / "ansible" / "generated-vars.json"


# Terraform outputs required by our Ansible deployment.
REQUIRED_OUTPUTS = [
    "aws_region",
    "db_name",
    "rds_secret_arn",
    "app_alb_dns_name",
    "ansible_ssm_bucket_name",
]


def get_terraform_outputs():
    """Retrieve Terraform outputs in JSON format."""

    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=TERRAFORM_DIR,
            capture_output=True,
            text=True,
            check=True,
        )

    except FileNotFoundError:
        raise RuntimeError(
            "Terraform CLI was not found. Install Terraform and add it to PATH."
        )

    except subprocess.CalledProcessError as error:
        details = error.stderr.strip() or str(error)
        raise RuntimeError(
            "Could not retrieve Terraform outputs. "
            "Check that Terraform has been initialized and applied. "
            f"\nDetails: {details}"
        )

    try:
        return json.loads(result.stdout)

    except json.JSONDecodeError:
        raise RuntimeError("Terraform returned invalid JSON output.")


def generate_ansible_variables(outputs):
    """Extract and validate values required by Ansible."""

    missing_outputs = [
        name for name in REQUIRED_OUTPUTS if name not in outputs
    ]

    if missing_outputs:
        raise RuntimeError(
            f"Missing Terraform outputs: {', '.join(missing_outputs)}"
        )

    values = {
        name: outputs[name].get("value")
        for name in REQUIRED_OUTPUTS
    }

    empty_outputs = [
        name
        for name, value in values.items()
        if not isinstance(value, str) or not value.strip()
    ]

    if empty_outputs:
        raise RuntimeError(
            "The following Terraform outputs are empty or null: "
            f"{', '.join(empty_outputs)}"
        )

    # Map Terraform outputs to the variables used by Ansible.
    ansible_variables = {
        # Application configuration.
        "aws_region": values["aws_region"],
        "db_name": values["db_name"],
        "db_secret_arn": values["rds_secret_arn"],
        "app_load_balancer_dns_name": values["app_alb_dns_name"],

        # AWS Systems Manager connection configuration.
        "ansible_aws_ssm_region": values["aws_region"],
        "ansible_aws_ssm_bucket_name": values["ansible_ssm_bucket_name"],
    }

    return ansible_variables


def main():
    print("Retrieving Terraform outputs...")

    outputs = get_terraform_outputs()

    print("Validating required Terraform values...")

    ansible_variables = generate_ansible_variables(outputs)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    with OUTPUT_FILE.open("w", encoding="utf-8") as file:
        json.dump(ansible_variables, file, indent=2)
        file.write("\n")

    print("Ansible variables file generated successfully.")
    print(f"Location: {OUTPUT_FILE.relative_to(PROJECT_ROOT)}")
    print("Required variables: all present.")


if __name__ == "__main__":
    try:
        main()

    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
