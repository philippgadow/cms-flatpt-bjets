#!/bin/bash
#
# Set up all CMSSW releases for the cms-flatpt-bjets chain and build the
# ZprimeFlatpT UserHook into the GEN-SIM release.
#
# Usage:
#   source production/setup.sh          # all releases
#   source production/setup.sh gs       # only the GEN-SIM release (+ hook)
#
# Must run on el9 (lxplus9) or inside `cmssw-el9`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

require_el9 || return 1 2>/dev/null || exit 1

WHICH=${1:-all}

echo "════════════════════════════════════════════════════════════════"
echo "  cms-flatpt-bjets setup"
echo "    releases dir : $RELEASE_DIR"
echo "    EOS output   : $EOS_OUTDIR"
echo "════════════════════════════════════════════════════════════════"

# ─── GEN-SIM release: needs the patched Pythia8Interface ─────────────────────
setup_gs_release() {
    echo ""
    echo "──── $CMSSW_GS (GEN-SIM) + ZprimeFlatpT hook ────"
    setup_release "$CMSSW_GS"

    local PKG="$CMSSW_BASE/src/GeneratorInterface/Pythia8Interface"

    if [ ! -d "$PKG" ]; then
        echo "  checking out GeneratorInterface/Pythia8Interface ..."
        pushd "$CMSSW_BASE/src" > /dev/null
        git cms-init --upstream-only > /dev/null 2>&1 || true
        git cms-addpkg GeneratorInterface/Pythia8Interface || {
            echo "ERROR: git cms-addpkg failed"; popd > /dev/null; return 1; }
        popd > /dev/null
    fi

    echo "  installing hook sources ..."
    cp "$REPO_DIR/userhook/ZprimeFlatpT.h"  "$PKG/plugins/"
    cp "$REPO_DIR/userhook/ZprimeFlatpT.cc" "$PKG/plugins/"

    # The hook needs its OWN library stanza. The generic *Hook*.cc glob is used
    # by both the HepMC2 and HepMC3 plugin libraries, so a file matching it
    # would register the plugin twice -> 'MultiplePlugins' fatal exception.
    if ! grep -q "ZprimeFlatpT\*.cc" "$PKG/plugins/BuildFile.xml"; then
        echo "  patching plugins/BuildFile.xml ..."
        python3 - "$PKG/plugins/BuildFile.xml" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
stanza = ('\n<library file="ZprimeFlatpT*.cc" '
          'name="GeneratorInterfacePythia8ZprimeFlatpTHook">\n</library>\n')
open(path, "w").write(text.rstrip("\n") + "\n" + stanza)
PYEOF
    else
        echo "  BuildFile.xml already patched"
    fi

    mkdir -p "$CMSSW_BASE/src/Configuration/GenProduction/python"

    echo "  building (this takes a few minutes the first time) ..."
    pushd "$CMSSW_BASE/src" > /dev/null
    scram b -j 12 2>&1 | grep -iE "^gmake.*Error|error:" && {
        echo "ERROR: build failed"; popd > /dev/null; return 1; }
    popd > /dev/null

    local NREG
    NREG=$(grep -c "ZprimeFlatpTHook" "$CMSSW_BASE/lib/$SCRAM_ARCH/.edmplugincache" 2>/dev/null || echo 0)
    if [ "$NREG" -eq 1 ]; then
        echo "  ✓ ZprimeFlatpTHook registered exactly once"
    else
        echo "  ✗ plugin registered $NREG times (expected 1) -- check BuildFile.xml"
        return 1
    fi
}

setup_plain_release() {
    local REL="$1" LABEL="$2"
    echo ""
    echo "──── $REL ($LABEL) ────"
    setup_release "$REL"
    echo "  ✓ $REL ready"
}

case "$WHICH" in
    gs)  setup_gs_release ;;
    all)
        setup_gs_release || return 1 2>/dev/null || exit 1
        setup_plain_release "$CMSSW_DR"   "DIGI+HLT+RECO"
        setup_plain_release "$CMSSW_MINI" "MiniAOD+NanoAOD"
        ;;
    *) echo "usage: source setup.sh [all|gs]"; return 1 2>/dev/null || exit 1 ;;
esac

mkdir -p "$EOS_OUTDIR" 2>/dev/null || echo "  note: could not create $EOS_OUTDIR (check EOS access)"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Setup complete."
echo ""
echo "  Next:"
echo "    ./production/test_local.sh                 # 10 events, GEN-SIM"
echo "    ./production/run_fullchain.sh --no-pileup   # 100 events -> NanoAOD"
echo "    ./calibration/calibrate.sh                 # re-derive p0/p1"
echo "════════════════════════════════════════════════════════════════"
