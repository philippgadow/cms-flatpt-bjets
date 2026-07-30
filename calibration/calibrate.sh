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
python3 - "$OUTDIR" "$FITMIN" "$FITMAX" <<'PYEOF'
import json, math, sys
outdir, fitmin, fitmax = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
a = json.load(open(f"{outdir}/passA_fit.json"))
b = json.load(open(f"{outdir}/passB_fit.json"))

# Judge flatness by how much the spectrum actually varies, NOT by the
# significance of the slope: with O(50k) events the statistical precision is so
# good that any residual is many sigma, so a sigma-based criterion would never
# converge even when the spectrum is flat for all practical purposes.
def spread(c1, lo, hi):
    return math.exp(abs(c1) * (hi - lo))

# The physics target is a flat spectrum up to ~7 TeV.
TARGET_HI = min(7000.0, fitmax)
spread_a = spread(a["c1"], fitmin, TARGET_HI)
spread_b = spread(b["c1"], fitmin, TARGET_HI)
# p1 corrections are additive: the new one stacks on what Pass B already used.
p1_next = a["p1_recommended"] + b["p1_recommended"]
n = 1000
acc = sum(math.exp(p1_next * (fitmin + (fitmax - fitmin) * (i + 0.5) / n))
          for i in range(n)) / n
p0_next = -math.log(acc)

print()
print("=" * 64)
print("  CALIBRATION SUMMARY")
print("=" * 64)
print(f"  Pass A  c1 = {a['c1']:+.4g} +- {a['c1_err']:.3g} /GeV"
      f"   spectrum varies x{spread_a:.3g} up to {TARGET_HI:.0f} GeV")
print(f"  Pass B  c1 = {b['c1']:+.4g} +- {b['c1_err']:.3g} /GeV"
      f"   spectrum varies x{spread_b:.3g} up to {TARGET_HI:.0f} GeV")
print(f"  in-range fraction: pass A {100.*a['n_in_range']/a['n_events']:.1f}%"
      f" -> pass B {100.*b['n_in_range']/b['n_events']:.1f}%")
print()
# A factor <2 across 200 GeV..7 TeV is flat enough for a performance sample:
# per-bin b-tagging statistics then vary by less than the bin-to-bin
# fluctuation of a realistic sample size.
if spread_b < 2.0:
    print(f"  => CONVERGED: flat to within a factor {spread_b:.2f} up to"
          f" {TARGET_HI:.0f} GeV.")
    print("     Values currently in the fragment are good.")
else:
    print(f"  => NOT YET FLAT (varies x{spread_b:.3g}). Iterate: put these into")
    print("     fragments/flatpT_Zprime_bb_fragment.py and rerun with REUSE_PASSA=1:")
    print()
    print(f"         p0 = cms.double({p0_next:.6g}),")
    print(f"         p1 = cms.double({p1_next:.6g}),")
print("=" * 64)
PYEOF
