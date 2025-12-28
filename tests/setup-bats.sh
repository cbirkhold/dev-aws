#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/lib"

echo "Installing bats helper libraries..."

if [[ ! -d bats-support ]]; then
  git clone --depth 1 https://github.com/bats-core/bats-support.git
fi

if [[ ! -d bats-assert ]]; then
  git clone --depth 1 https://github.com/bats-core/bats-assert.git
fi

echo "DONE"
