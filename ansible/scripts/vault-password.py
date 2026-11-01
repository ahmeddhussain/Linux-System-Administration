#!/usr/bin/env python3
"""Print the Ansible Vault password stored in SSM Parameter Store.

Used as vault_password_file in ansible.cfg. Runs on control01, authenticated
by its instance role (no stored credentials). The parameter is created by
terraform/persistent. Needs boto3, so run inside ~/ansible-venv.
"""
import os
import sys

import boto3
import botocore.exceptions

PARAMETER = os.environ.get("AHMED_VAULT_PARAMETER", "/ahmed-infra/ansible-vault-password")
REGION = os.environ.get("AWS_REGION", "us-east-1")


def main():
    try:
        ssm = boto3.client("ssm", region_name=REGION)
        value = ssm.get_parameter(Name=PARAMETER, WithDecryption=True)["Parameter"]["Value"]
    except (botocore.exceptions.BotoCoreError, botocore.exceptions.ClientError) as e:
        # Never print the value; only say what failed.
        sys.exit(f"vault-password.py: cannot read {PARAMETER} in {REGION}: {e}")
    print(value)


if __name__ == "__main__":
    main()
