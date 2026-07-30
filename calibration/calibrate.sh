#!/bin/bash
#
# Two-pass flatness calibration of the ZprimeFlatpTHook.
#
#   Pass A: p0 = p1 = 0  (BW removal only) -> measure the residual slope c1
#           of ln(dN/dsqrt(sHat)), which comes from the falling parton luminosity.
#   Fit   : p1 = -c1, p0 chosen so <weight> ~ 1 over the range.
#   Pass B: regenerate with those parameters and confirm c1 ~ 0.
#
# The recommended parameters are printed at the end; put them into
# fragments/flatpT_Zprime_bb_fragment.py (they are NOT written automatically,
# so that the fragment stays under review control).
#
# Usage:
#   ./calibrate.sh [nevents] [fitmin] [fitmax]
# Defaults: 50000 events, fit over 200 .. 13600 GeV.

set -e
# The fit is piped through grep to suppress ROOT noise; without pipefail a
# crashing fit would be masked by grep's exit status.
set -o pipefail

NEVENTS=${1:-50000}
FITMIN=${2:-200}
FITMAX=${3:-13600}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="$SCRIPT_DIR/output"
mkdir -p "$OUTDIR"

source "$SCRIPT_DIR/../production/env.sh"

# fit <genfile> <tag> -- run the fit inside the CMSSW env (FWLite needs it).
fit_pass() {
    local GENFILE="$1" TAG="$2"
    # setup_release leaves us in the caller's cwd but with the env applied.
    setup_release "$CMSSW_GS"
    python3 "$SCRIPT_DIR/fit_flatness.py" "$GENFILE" \
        --min "$FITMIN" --max "$FITMAX" \
        --plot "$OUTDIR/${TAG}_shat.pdf" --json "$OUTDIR/${TAG}_fit.json" \
        2>&1 | grep -viE "^Warning|libGL|TClass|Info in"
}

echo "════════════════════════════════════════════════════════════════"
echo "  ZprimeFlatpT flatness calibration"
echo "    events per pass : $NEVENTS"
echo "    fit range       : $FITMIN .. $FITMAX GeV"
echo "    output          : $OUTDIR"
echo "════════════════════════════════════════════════════════════════"

# ─── Pass A: BW removal only ────────────────────────────────────────────────
# Reuse an existing Pass A file if REUSE_PASSA=1 (it is expensive to regenerate).
echo ""
if [ "${REUSE_PASSA:-0}" = "1" ] && [ -f "$OUTDIR/passA_GEN.root" ]; then
    echo "──── Pass A: reusing existing $OUTDIR/passA_GEN.root ────"
else
    echo "──── Pass A: p0 = 0, p1 = 0 (BW removal only) ────"
    "$SCRIPT_DIR/run_genonly.sh" "$NEVENTS" 100001 0.0 0.0 "$OUTDIR/passA_GEN.root"
fi

echo ""
echo "──── Fitting Pass A ────"
fit_pass "$OUTDIR/passA_GEN.root" passA

P0=$(python3 -c "import json;print(json.load(open('$OUTDIR/passA_fit.json'))['p0_recommended'])")
P1=$(python3 -c "import json;print(json.load(open('$OUTDIR/passA_fit.json'))['p1_recommended'])")

# ─── Pass B: closure ────────────────────────────────────────────────────────
echo ""
echo "──── Pass B: p0 = $P0, p1 = $P1 ────"
"$SCRIPT_DIR/run_genonly.sh" "$NEVENTS" 200002 "$P0" "$P1" "$OUTDIR/passB_GEN.root"

echo ""
echo "──── Fitting Pass B (closure test) ────"
fit_pass "$OUTDIR/passB_GEN.root" passB

# ─── Summary ────────────────────────────────────────────────────────────────
python3 - "$OUTDIR" <<'PYEOF'
import json, sys
outdir = sys.argv[1]
a = json.load(open(f"{outdir}/passA_fit.json"))
b = json.load(open(f"{outdir}/passB_fit.json"))
sig = abs(b["c1"]) / b["c1_err"] if b["c1_err"] else float("nan")
print()
print("=" * 64)
print("  CALIBRATION SUMMARY")
print("=" * 64)
print(f"  Pass A slope c1 = {a['c1']:+.4g} +- {a['c1_err']:.3g} /GeV")
print(f"  Pass B slope c1 = {b['c1']:+.4g} +- {b['c1_err']:.3g} /GeV  ({sig:.1f} sigma from flat)")
print()
print("  Use in the fragment:")
print(f"      p0 = cms.double({a['p0_recommended']:.6g}),")
print(f"      p1 = cms.double({a['p1_recommended']:.6g}),")
print()
if sig < 3:
    print("  => Pass B is flat within 3 sigma. Calibration converged.")
else:
    print("  => Pass B still sloped (>3 sigma). Iterate: rerun calibrate.sh")
    print("     after putting the Pass B recommendation into the fragment,")
    print("     or increase the statistics.")
print("=" * 64)
PYEOF
