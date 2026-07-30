#!/bin/bash
#
# Step 1: DIGI + DATAMIX(premix) + L1 + DIGI2RAW + HLT  (CMSSW_14_0_21)
#
# Usage: ./step1_digihlt.sh <infile> <nevents> <seed> <outfile> [--no-pileup]
#
# With pileup this reads the premix library over AAA and needs a VOMS proxy.

set -e

INFILE=${1:?usage: step1_digihlt.sh <infile> <nevents> <seed> <outfile> [--no-pileup]}
NEVENTS=${2:?need nevents}
SEED=${3:?need seed}
OUTFILE=${4:?need outfile}
USE_PILEUP=true
[ "$5" = "--no-pileup" ] && USE_PILEUP=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

echo "━━━ STEP 1: DIGI + L1 + HLT:$HLT_MENU ($CMSSW_DR) ━━━"
echo "  pileup : $USE_PILEUP"

setup_release "$CMSSW_DR"

SEED_CMD="process.RandomNumberGeneratorService.generator.initialSeed=${SEED}"

if [ "$USE_PILEUP" = true ]; then
    check_proxy || exit 1
    echo "  premix : $PREMIX_DATASET"
    cmsDriver.py \
        --python_filename "${CAMPAIGN_DR}_step1_cfg.py" \
        --eventcontent PREMIXRAW \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --datatier GEN-SIM-RAW \
        --filein "file:${INFILE}" \
        --fileout "file:${OUTFILE}" \
        --pileup_input "dbs:${PREMIX_DATASET}" \
        --conditions "$GT_DR" \
        --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:${HLT_MENU} \
        --procModifiers premix_stage2 \
        --geometry DB:Extended \
        --datamix PreMix \
        --era "$ERA" \
        --mc \
        --nThreads "$NTHREADS" \
        --customise_commands "$SEED_CMD" \
        -n "$NEVENTS"
else
    echo "  ⚠  running WITHOUT pileup (validation mode)"
    cmsDriver.py \
        --python_filename "${CAMPAIGN_DR}_step1_cfg.py" \
        --eventcontent RAWSIM \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --datatier GEN-SIM-RAW \
        --filein "file:${INFILE}" \
        --fileout "file:${OUTFILE}" \
        --conditions "$GT_DR" \
        --step DIGI,L1,DIGI2RAW,HLT:${HLT_MENU} \
        --geometry DB:Extended \
        --era "$ERA" \
        --mc \
        --nThreads "$NTHREADS" \
        --customise_commands "$SEED_CMD" \
        -n "$NEVENTS"
fi

echo "  ✓ DIGI-HLT: $(ls -lh "$OUTFILE" | awk '{print $5}')"
