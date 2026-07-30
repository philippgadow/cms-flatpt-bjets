#!/bin/bash
#
# Smoke test: 10 events, GEN-SIM only.
# Run this after any change to the hook or the fragment.
#
# Usage: ./test_local.sh [nevents]

set -e

NEVENTS=${1:-10}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

require_el9 || exit 1

TESTDIR="$SCRIPT_DIR/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TESTDIR"
cd "$TESTDIR"

echo "════════════════════════════════════════════════════════════════"
echo "  Local test: flat-pT Z' -> bb, GEN-SIM, $NEVENTS events"
echo "  workdir: $TESTDIR"
echo "════════════════════════════════════════════════════════════════"

"$SCRIPT_DIR/steps/step0_gensim.sh" "$NEVENTS" 12345 "$TESTDIR/${SAMPLE}_GEN-SIM.root"

echo ""
echo "──── generator-level check ────"
python3 "$REPO_DIR/validation/dump_genparticles.py" "$TESTDIR/${SAMPLE}_GEN-SIM.root" \
    2>&1 | grep -viE "^Warning|libGL|TClass|Info in"

echo ""
echo "✓ test complete: $TESTDIR/${SAMPLE}_GEN-SIM.root"
