#!/bin/bash

# Motivation
#
# When bringing up an EC2 Instance in a CloudFormation stack one might want to
# first introduce install scripts and tools in the UserData section. If those
# reside in a private Git repo we may need to first install a deploy key while
# this script, containing no sensitive information, can reside in a public repo.
#
# Overview
#
# This script retrieves a Base64 encoded SSH private key (deployment key) from
# the Secrets Manager and installs it for the given host. The encoding prevents
# whitespace issues with the secret.
#
# Side Effects
#
# - Installs curl git unzip jq (but apt-get update is up to the caller)
# - Installs AWS CLI v2
# - Creates/overwrites /root/.ssh/deploy-key
# - Amends /root/.ssh/config
#
# Notes
#
# It is recommended to reference a specific version of this file.
#
# usage:
#
# apt-get update
#
# SCRIPT="aws-cloudformation-install-deploy-key-from-secrets-manager.sh"
# curl -fsSL "https://raw.githubusercontent.com/owner/repo/commit/scripts/"\
#   "${SCRIPT}" -o "${SCRIPT}"
#
# SECRET_REGION=us-west-1 SECRET_ID=my-secret-id SECRET_KEY=DEPLOY_KEY_BASE64 \
#   ./aws-cloudformation-install-deploy-key-from-secrets-manager.sh host.com

set -euo pipefail

if [ $# -ne 1 ]; then
     echo "usage: ${0##*/} <host>"
     exit 1
fi

# Required environment variables (avoids exposure in process list)
: "${SECRET_REGION:?error: environment variable NOT set!}"
: "${SECRET_ID:?error: environment variable NOT set!}"
: "${SECRET_KEY:?error: environment variable NOT set!}"

# Positional arguments
readonly HOST="$1"

# Configurable paths (for testing)
readonly _SSH_DIR="${_SSH_DIR:-/root/.ssh}"

retry() {
  local n=0
  until [[ $n -ge 5 ]]; do
    "$@" && return 0
    n=$((n+1))
    sleep $((2**n))
  done
  return 1
}

# Install minimal dependencies
apt-get install -y --no-install-recommends curl git unzip jq

# Install AWS CLI
if command -v aws &> /dev/null && aws --version 2>&1 | grep -q "aws-cli/2\."; then
    echo "AWS CLI v2 already installed: $(aws --version)"
else
    retry curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -oq /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    echo "AWS CLI v2 installed: $(aws --version)"
fi

# Fetch deploy key
mkdir -p "${_SSH_DIR}"
chmod 700 "${_SSH_DIR}"

retry aws secretsmanager get-secret-value \
  --secret-id "${SECRET_ID}" \
  --query SecretString --output text \
  --region "${SECRET_REGION}" \
  | jq -r ".\"${SECRET_KEY}\"" \
  | base64 -d \
  | install -m 600 /dev/stdin "${_SSH_DIR}/deploy-key"

cat >> "${_SSH_DIR}/config" << EOF
Host ${HOST}
  IdentityFile ${_SSH_DIR}/deploy-key
  StrictHostKeyChecking accept-new
EOF
