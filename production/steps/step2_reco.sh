#!/bin/bash
#
# Step 2: RAW2DIGI + L1Reco + RECO + RECOSIM -> AODSIM  (CMSSW_14_0_21)
#
# Usage: ./step2_reco.sh <infile> <nevents> <outfile>

set -e

INFILE=${1:?usage: step2_reco.sh <infile> <nevents> <outfile>}
NEVENTS=${2:?need nevents}
OUTFILE=${3:?need outfile}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

echo "━━━ STEP 2: RECO -> AOD ($CMSSW_DR) ━━━"

setup_release "$CMSSW_DR"

cmsDriver.py \
    --python_filename "${CAMPAIGN_RECO}_cfg.py" \
    --eventcontent AODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier AODSIM \
    --filein "file:${INFILE}" \
    --fileout "file:${OUTFILE}" \
    --conditions "$GT_DR" \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM \
    --geometry DB:Extended \
    --era "$ERA" \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS"

echo "  ✓ AOD: $(ls -lh "$OUTFILE" | awk '{print $5}')"
