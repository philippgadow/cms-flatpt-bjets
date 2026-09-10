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

DRIVER_ARGS=(
    --python_filename "${CAMPAIGN_MINI}_cfg.py"
    --eventcontent MINIAODSIM
    --customise Configuration/DataProcessing/Utils.addMonitoring
    --datatier MINIAODSIM
    --filein "file:${INFILE}"
    --fileout "file:${OUTFILE}"
    --conditions "$GT_MINI"
    --step PAT
    --geometry DB:Extended
    --era "$ERA"
    --mc
    --nThreads "$NTHREADS"
    -n "$NEVENTS"
)

# CRAB publication needs the framework job report of the cmsRun that produced
# the output.  When FLATPT_FJR_MINI is set (by crab/crab_job.sh), generate the
# config only and run cmsRun ourselves with -j; the default path is unchanged.
if [ -n "${FLATPT_FJR_MINI:-}" ]; then
    cmsDriver.py "${DRIVER_ARGS[@]}" --no_exec
    cmsRun -e -j "$FLATPT_FJR_MINI" "${CAMPAIGN_MINI}_cfg.py"
else
    cmsDriver.py "${DRIVER_ARGS[@]}"
fi

echo "  ✓ MiniAOD: $(ls -lh "$OUTFILE" | awk '{print $5}')"
