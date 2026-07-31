#!/bin/bash
#
# Stand-alone smoke test of ONE gridpack: unpack it and generate a few LHE
# events, exactly the way CMSSW does (run_generic_tarball_cvmfs.sh).
#
# Run this before generating the rest of the grid -- a broken gridpack fails
# identically for every job that uses it.
#
# Usage: ./test_gridpack.sh <tarball.tar.xz> [nevents]

set -e
set -o pipefail

TARBALL=${1:?usage: test_gridpack.sh <tarball.tar.xz> [nevents]}
NEVENTS=${2:-10}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

[ -f "$TARBALL" ] || { echo "ERROR: no such tarball: $TARBALL"; exit 1; }
TARBALL="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")"

setup_release "$CMSSW_GS"

TESTDIR="$SCRIPT_DIR/test_$(basename "${TARBALL%%_*}")_$(date +%H%M%S)"
mkdir -p "$TESTDIR"
cd "$TESTDIR"

echo "════════════════════════════════════════════════════════════════"
echo "  gridpack smoke test"
echo "    tarball : $TARBALL"
echo "    events  : $NEVENTS"
echo "    workdir : $TESTDIR"
echo "════════════════════════════════════════════════════════════════"

# This is the very script BaseHadronizer::generateLHE forks, with the same
# argument order: <tarball> <nevents> <seed> <ncpu>.
SCRIPT=$(python3 -c "
import os
base = os.environ['CMSSW_RELEASE_BASE']
local = os.environ['CMSSW_BASE']
rel = 'src/GeneratorInterface/LHEInterface/data/run_generic_tarball_cvmfs.sh'
for b in (local, base):
    p = os.path.join(b, rel)
    if os.path.exists(p):
        print(p); break
")
[ -z "$SCRIPT" ] && { echo "ERROR: run_generic_tarball_cvmfs.sh not found"; exit 1; }
echo "  using: $SCRIPT"

echo ""
echo "──── running gridpack ────"
"$SCRIPT" "$TARBALL" "$NEVENTS" 12345 1 2>&1 | tail -25

echo ""
if [ ! -f cmsgrid_final.lhe ]; then
    echo "✗ FAILED: cmsgrid_final.lhe not produced"
    exit 1
fi

NLHE=$(grep -c "<event>" cmsgrid_final.lhe || true)
echo "──── result ────"
echo "  cmsgrid_final.lhe: $(du -h cmsgrid_final.lhe | cut -f1), $NLHE events"

if [ "$NLHE" -lt 1 ]; then
    echo "✗ FAILED: no <event> blocks in the LHE file"
    exit 1
fi

# Check the resonance masses actually match the requested point.
echo ""
echo "  masses seen in the LHE (pdgId 39 = X, 25 = H):"
python3 - cmsgrid_final.lhe <<'PYEOF'
import re, sys
masses = {}
inev = False
for line in open(sys.argv[1]):
    if line.startswith("<event>"):
        inev = True; continue
    if line.startswith("</event>"):
        inev = False; continue
    if inev:
        parts = line.split()
        if len(parts) >= 13:
            try:
                pid, m = abs(int(parts[0])), float(parts[10])
            except ValueError:
                continue
            if pid in (39, 25):
                masses.setdefault(pid, []).append(m)
for pid, ms in sorted(masses.items()):
    label = {39: "X (graviton)", 25: "H"}[pid]
    print("    %-14s n=%3d  mean=%8.2f  min=%8.2f  max=%8.2f"
          % (label, len(ms), sum(ms)/len(ms), min(ms), max(ms)))
PYEOF

echo ""
echo "✓ gridpack OK: $TESTDIR/cmsgrid_final.lhe"
