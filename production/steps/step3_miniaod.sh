#!/bin/bash
#
# Step 3: PAT -> MiniAODv6  (CMSSW_15_0_2)
#
# Usage: ./step3_miniaod.sh <infile> <nevents> <outfile>

set -e

INFILE=${1:?usage: step3_miniaod.sh <infile> <nevents> <outfile>}
NEVENTS=${2:?need nevents}
OUTFILE=${3:?need outfile}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

echo "━━━ STEP 3: MiniAODv6 ($CMSSW_MINI) ━━━"

setup_release "$CMSSW_MINI"

cmsDriver.py \
    --python_filename "${CAMPAIGN_MINI}_cfg.py" \
    --eventcontent MINIAODSIM \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --datatier MINIAODSIM \
    --filein "file:${INFILE}" \
    --fileout "file:${OUTFILE}" \
    --conditions "$GT_MINI" \
    --step PAT \
    --geometry DB:Extended \
    --era "$ERA" \
    --mc \
    --nThreads "$NTHREADS" \
    -n "$NEVENTS"

echo "  ✓ MiniAOD: $(ls -lh "$OUTFILE" | awk '{print $5}')"
