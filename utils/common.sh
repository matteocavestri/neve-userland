#!/bin/sh
# Common functions for POSIX compliance testing

# Colors for output (POSIX compliant)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Print a test result
print_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$result" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf "${GREEN}✓${NC} %s\n" "$test_name"
    elif [ "$result" = "FAIL" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}✗${NC} %s\n" "$test_name"
        if [ -n "$message" ]; then
            printf "  ${RED}Error:${NC} %s\n" "$message"
        fi
    elif [ "$result" = "SKIP" ]; then
        printf "${YELLOW}⊘${NC} %s (skipped)\n" "$test_name"
    fi
}

# Test if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Test if output matches expected
test_output() {
    local cmd="$1"
    local expected="$2"
    local test_name="$3"
    
    output=$(eval "$cmd" 2>&1)
    if [ "$output" = "$expected" ]; then
        print_result "$test_name" "PASS"
        return 0
    else
        print_result "$test_name" "FAIL" "Expected '$expected', got '$output'"
        return 1
    fi
}

# Test if exit code matches expected
test_exit_code() {
    local cmd="$1"
    local expected_code="$2"
    local test_name="$3"
    
    eval "$cmd" >/dev/null 2>&1
    actual_code=$?
    
    if [ "$actual_code" -eq "$expected_code" ]; then
        print_result "$test_name" "PASS"
        return 0
    else
        print_result "$test_name" "FAIL" "Expected exit code $expected_code, got $actual_code"
        return 1
    fi
}

# Test if command outputs to stderr
test_stderr() {
    local cmd="$1"
    local expected_pattern="$2"
    local test_name="$3"
    
    stderr=$(eval "$cmd" 2>&1 >/dev/null)
    
    case "$stderr" in
        *"$expected_pattern"*)
            print_result "$test_name" "PASS"
            return 0
            ;;
        *)
            print_result "$test_name" "FAIL" "Expected stderr to contain '$expected_pattern'"
            return 1
            ;;
    esac
}

# Create temporary file
make_temp_file() {
    mktemp /tmp/posix_test.XXXXXX
}

# Cleanup temporary file
cleanup_temp() {
    rm -f "$1" 2>/dev/null
}

# Print test summary
print_summary() {
    local utility_name="$1"
    
    printf "\n"
    printf "========================================\n"
    printf "Summary for %s\n" "$utility_name"
    printf "========================================\n"
    printf "Total tests:  %d\n" "$TESTS_TOTAL"
    printf "${GREEN}Passed:${NC}       %d\n" "$TESTS_PASSED"
    
    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf "${RED}Failed:${NC}       %d\n" "$TESTS_FAILED"
        return 1
    else
        printf "${GREEN}All tests passed!${NC}\n"
        return 0
    fi
}

# Set the binary directory and convert to absolute path if needed
BIN_DIR="${BIN_DIR:-zig-out/bin}"

# Convert BIN_DIR to absolute path if it's relative
case "$BIN_DIR" in
    /*)
        # Already absolute
        ;;
    *)
        # Make it absolute by prepending current directory
        # Find the project root (where build.zig is)
        if [ -f "build.zig" ]; then
            BIN_DIR="$(pwd)/$BIN_DIR"
        elif [ -f "../build.zig" ]; then
            BIN_DIR="$(cd .. && pwd)/$BIN_DIR"
        elif [ -f "../../build.zig" ]; then
            BIN_DIR="$(cd ../.. && pwd)/$BIN_DIR"
        fi
        ;;
esac

export BIN_DIR
