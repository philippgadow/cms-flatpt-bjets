#!/bin/bash
#
# Step 0: GEN + SIM  (CMSSW_14_0_19)
#
# Usage: ./step0_gensim.sh <nevents> <seed> <outfile>
#
# Unlike the reference ggH->Za chain there is no LHE step: the process is pure
# Pythia8 (ffbar -> Z'), so the fragment is the generator.

set -e

NEVENTS=${1:?usage: step0_gensim.sh <nevents> <seed> <outfile>}
SEED=${2:?need seed}
OUTFILE=${3:?need outfile}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

FRAGMENT="${FRAGMENT:-$REPO_DIR/fragments/flatpT_Zprime_bb_fragment.py}"

echo "━━━ STEP 0: GEN + SIM ($CMSSW_GS) ━━━"
echo "  events   : $NEVENTS"
echo "  seed     : $SEED"
echo "  fragment : $FRAGMENT"

setup_release "$CMSSW_GS"

# The UserHook must be present in this release (see userhook/README.md).
if ! grep -q "ZprimeFlatpTHook" "$CMSSW_BASE/lib/$SCRAM_ARCH/.edmplugincache" 2>/dev/null; then
    echo "ERROR: ZprimeFlatpTHook plugin not found in $CMSSW_BASE."
    echo "       Run production/setup.sh first to install and build the hook."
    exit 1
fi

FRAG_NAME="$SAMPLE"
FRAG_DST="$CMSSW_BASE/src/Configuration/GenProduction/python/${FRAG_NAME}.py"

# Batch jobs share one release area on AFS, so they must NOT all copy the
# fragment and run `scram b` into it concurrently -- that races on the same
# files.  Install + build only if the fragment is missing or has changed;
# production/setup.sh normally does this once, before submission.
# scram compiles GenProduction python in place under src/, so importability --
# not a copy under python/ -- is what says it is ready.
if cmp -s "$FRAGMENT" "$FRAG_DST" \
   && python3 -c "import Configuration.GenProduction.${FRAG_NAME}" > /dev/null 2>&1; then
    echo "  fragment already installed and built, reusing"
else
    if [ "${ALLOW_FRAGMENT_BUILD:-1}" != "1" ]; then
        echo "ERROR: fragment not installed in $CMSSW_BASE and building is"
        echo "       disabled (ALLOW_FRAGMENT_BUILD=0). Run production/setup.sh"
        echo "       and install the fragment before submitting jobs."
        exit 1
    fi
    echo "  installing + building fragment ..."
    mkdir -p "$(dirname "$FRAG_DST")"
    cp "$FRAGMENT" "$FRAG_DST"
    pushd "$CMSSW_BASE/src" > /dev/null
    scram b -j "$NTHREADS" > /dev/null 2>&1
    popd > /dev/null
fi

cmsDriver.py "Configuration/GenProduction/python/${FRAG_NAME}.py" \
    --python_filename "${CAMPAIGN_GS}_cfg.py" \
    --eventcontent RAWSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier GEN-SIM \
    --fileout "file:${OUTFILE}" \
    --conditions "$GT_GS" \
    --beamspot "$BEAMSPOT" \
    --step GEN,SIM \
    --geometry DB:Extended \
    --era "$ERA" \
    --nThreads "$NTHREADS" \
    --customise_commands "process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(100)\nprocess.RandomNumberGeneratorService.generator.initialSeed=${SEED}" \
    --mc \
    -n "$NEVENTS"

echo "  ✓ GEN-SIM: $(ls -lh "$OUTFILE" | awk '{print $5}')"
