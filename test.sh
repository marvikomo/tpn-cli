#!/bin/sh


# --------------------
# Helpers
# --------------------

green() {
  if [ $# -gt 0 ]; then
    printf '\033[0;32m%s\033[0m\n' "$*"
  else
    while IFS= read -r line; do
      printf '\033[0;32m%s\033[0m\n' "$line"
    done
  fi
}

red() {
  if [ $# -gt 0 ]; then
    printf '\033[0;31m%s\033[0m\n' "$*"
  else
    while IFS= read -r line; do
      printf '\033[0;31m%s\033[0m\n' "$line"
    done
  fi
}

# Path to tpn.sh (adjust if needed)
TPN="sh ./tpn.sh"

# Parse --fail-fast argument
FAIL_FAST=0
for arg in "$@"; do
  if [ "$arg" = "--fail-fast" ]; then
    FAIL_FAST=1
  fi
done

fail=0

print_green() { green "$1"; }
print_red() { red "$1"; }

run_and_log() {
  echo "\n$*"
  eval "$*"
}

fail_exit() {
  if [ $FAIL_FAST -eq 1 ]; then
    print_red "Fail-fast enabled. Exiting on first failure."
    # Clean up .out files before exit
    rm -f countries.out countries_code.out status.out connect_missing.out disconnect.out connect_any.out disconnect_any.out help.out
    exit 1
  fi
}

echo "\nTesting: countries (default)"
run_and_log "$TPN countries | tee countries.out"
if [ $(wc -c < countries.out) -ge 10 ]; then
  print_green "PASS: countries"
else
  print_red "FAIL: countries (output too short)"
  fail=1
  fail_exit
fi

echo "\nTesting: countries code"
run_and_log "$TPN countries code | tee countries_code.out"
if [ $(wc -c < countries_code.out) -ge 10 ]; then
  print_green "PASS: countries code"
else
  print_red "FAIL: countries code (output too short)"
  fail=1
  fail_exit
fi

echo "\nTesting: status"
run_and_log "$TPN status | tee status.out"
if grep -q "TPN status:" status.out; then
  print_green "PASS: status"
else
  print_red "FAIL: status"
  fail=1
  fail_exit
fi

echo "\nTesting: connect to 'any' (real connection)"
run_and_log "$TPN connect -f any | tee connect_any.out"
if grep -qi "IP address changed" connect_any.out && ! grep -qi "error" connect_any.out; then
  print_green "PASS: connect any (real connection)"
  sleep 10
else
  print_red "FAIL: connect any (real connection)"
  fail=1
  fail_exit
fi

echo "\nTesting: disconnect after connect (real disconnect)"
run_and_log "$TPN disconnect | tee disconnect_any.out"
if grep -qi "IP changed back" disconnect_any.out && ! grep -qi "error" disconnect_any.out; then
  print_green "PASS: disconnect after connect (real disconnect)"
else
  print_red "FAIL: disconnect after connect (real disconnect)"
  fail=1
  fail_exit
fi

echo "\nTesting: help"
run_and_log "$TPN help > help.out 2>&1"
if grep -qi "usage" help.out; then
  print_green "PASS: help"
else
  print_red "FAIL: help"
  fail=1
  fail_exit
fi

if [ $fail -eq 0 ]; then
  print_green "All tests passed."
else
  print_red "Some tests failed."
fi

# Clean up .out files
rm -f countries.out countries_code.out status.out connect_missing.out disconnect.out connect_any.out disconnect_any.out help.out

exit $fail
