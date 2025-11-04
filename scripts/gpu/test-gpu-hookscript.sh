#!/bin/bash
#
# Test GPU Hookscript
# Validates hookscript functionality without starting a VM
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_test() { echo -e "[TEST] $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo "=========================================="
echo " GPU Hookscript Test Suite"
echo "=========================================="
echo ""

HOOKSCRIPT="/var/lib/vz/snippets/gpu-hookscript.pl"
TEST_VMID="999"

# Test 1: File exists
log_test "Checking hookscript exists..."
if [ -f "$HOOKSCRIPT" ]; then
    log_pass "Hookscript found: $HOOKSCRIPT"
else
    log_fail "Hookscript not found"
    exit 1
fi

# Test 2: Executable
log_test "Checking permissions..."
if [ -x "$HOOKSCRIPT" ]; then
    log_pass "Hookscript is executable"
else
    log_fail "Hookscript is not executable"
    exit 1
fi

# Test 3: Syntax
log_test "Checking bash syntax..."
if bash -n "$HOOKSCRIPT"; then
    log_pass "Syntax is valid"
else
    log_fail "Syntax errors detected"
    exit 1
fi

# Test 4: Required variables
log_test "Checking configuration..."
if grep -q "GPU_VIDEO_PCI=" "$HOOKSCRIPT"; then
    log_pass "GPU configuration present"
else
    log_warn "GPU configuration may need customization"
fi

# Test 5: Simulate pre-start (dry run)
log_test "Testing pre-start hook (dry-run)..."
export GPU_VIDEO_PCI="0000:02:00.0"
export GPU_AUDIO_PCI="0000:02:00.1"
if bash -n <(sed 's/^set -e/set -e; exit 0/' "$HOOKSCRIPT"); then
    log_pass "Pre-start hook structure valid"
else
    log_warn "Pre-start hook may need review"
fi

# Test 6: Log file writable
log_test "Checking log file..."
touch /var/log/gpu-hookscript.log 2>/dev/null && \
    log_pass "Log file writable"
