#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

create_mock_apt_get() {
  printf '#!/bin/bash\nexit 0\n' > "$1/apt-get"
  chmod +x "$1/apt-get"
}

create_mock_aws() {
  # We want literal $1 written to the mock script
  # shellcheck disable=SC2016
  printf '#!/bin/bash\nif [[ "$1" == "--version" ]]; then echo "aws-cli/2.0.0"; exit 0; fi\necho '\''{"DEPLOY_KEY_BASE64": "dGVzdC1wcml2YXRlLWtleS1jb250ZW50"}'\''\n' > "$1/aws"
  chmod +x "$1/aws"
}

setup() {
  load 'lib/bats-support/load'
  load 'lib/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../scripts/aws-cloudformation-install-deploy-key-from-secrets-manager.sh"
}

teardown() {
  # Clean up temp directories from integration test
  rm -rf "${FIXTURE_DIR:-}" "${MOCK_DIR:-}"
}

@test "script requires exactly one argument" {
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "usage:"
}

@test "script fails without SECRET_REGION" {
  unset SECRET_REGION
  export SECRET_ID="test-id"
  export SECRET_KEY="DEPLOY_KEY_BASE64"

  run bash "$SCRIPT" host.com
  assert_failure
  assert_output --partial "SECRET_REGION"
}

@test "script fails without SECRET_ID" {
  export SECRET_REGION="us-west-1"
  unset SECRET_ID
  export SECRET_KEY="DEPLOY_KEY_BASE64"

  run bash "$SCRIPT" host.com
  assert_failure
  assert_output --partial "SECRET_ID"
}

@test "script fails without SECRET_KEY" {
  export SECRET_REGION="us-west-1"
  export SECRET_ID="my-secret-id"
  unset SECRET_KEY

  run bash "$SCRIPT" host.com
  assert_failure
  assert_output --partial "SECRET_KEY"
}

@test "retry function retries on failure" {
  # Extract and test the retry function in a subshell
  run bash -c '
    eval "$(sed -n "/^retry()/,/^}/p" "'"$SCRIPT"'")"

    FAIL_COUNT=0
    fail_twice() {
      FAIL_COUNT=$((FAIL_COUNT + 1))
      [[ $FAIL_COUNT -ge 3 ]]
    }

    retry fail_twice
  '
  assert_success
}

@test "full script installs deploy key and configures ssh" {
  # Script uses install /dev/stdin (Linux-only) and x86_64 AWS CLI
  if [[ "$(uname)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    skip "This test requires Linux x86_64"
  fi

  # Create fixture and mock directories (cleaned up by teardown)
  FIXTURE_DIR="$(mktemp -d)"
  MOCK_DIR="$(mktemp -d)"

  # Create mock commands
  create_mock_apt_get "$MOCK_DIR"
  create_mock_aws "$MOCK_DIR"

  # Set up environment
  export PATH="$MOCK_DIR:$PATH"
  export _SSH_DIR="$FIXTURE_DIR/.ssh"
  export SECRET_REGION="us-west-1"
  export SECRET_ID="my-secret-id"
  export SECRET_KEY="DEPLOY_KEY_BASE64"

  # Run script
  run bash "$SCRIPT" host.com
  assert_success

  # Verify deploy key was created with correct content
  assert [ -f "$_SSH_DIR/deploy-key" ]
  run cat "$_SSH_DIR/deploy-key"
  assert_output "test-private-key-content"

  # Verify deploy key has correct permissions (600)
  run stat -c '%a' "$_SSH_DIR/deploy-key"
  assert_output "600"

  # Verify SSH config was created with correct content
  assert [ -f "$_SSH_DIR/config" ]
  run cat "$_SSH_DIR/config"
  assert_output --partial "Host host.com"
  assert_output --partial "IdentityFile $_SSH_DIR/deploy-key"
  assert_output --partial "StrictHostKeyChecking accept-new"
}
