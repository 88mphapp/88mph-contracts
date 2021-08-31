#!/usr/bin/env bash

set -eux

# set cwd to dir containing this script
cd "$(dirname "$0")"

TEST_MODE="assertion"
# enable this to run sanity checks
# TEST_MODE="optimization"

# echidna in combination with hardhat sometimes uses previously compiled versions i.e. doesn't pick up changes.
# we're investigating this.
# clear artifacts manually in the meantime.
rm -r crytic-export || true
rm -r artifacts || true
rm -r cache || true

echidna-test-2.0 . --contract EchidnaDepositWithdrawTest --config trailofbits-echidna-config.yaml --test-mode ${TEST_MODE}
