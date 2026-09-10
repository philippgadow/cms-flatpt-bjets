#!/bin/bash
#
# Step 4: NANO -> standard NanoAODv15  (CMSSW_15_0_2)
#
# Usage: ./step4_nanoaod.sh <infile> <nevents> <outfile>
#
# Standard NANO only -- no BTV/custom customisation (that is out of scope here;
# the final format for this project is central NanoAODv15).

set -e

INFILE=${1:?usage: step4_nanoaod.sh <infile> <nevents> <outfile>}
NEVENTS=${2:?need nevents}
OUTFILE=${3:?need outfile}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

echo "━━━ STEP 4: NanoAODv15 ($CMSSW_MINI) ━━━"

setup_release "$CMSSW_MINI"

DRIVER_ARGS=(
    --python_filename "${CAMPAIGN_NANO}_cfg.py"
    --eventcontent NANOAODSIM
    --customise Configuration/DataProcessing/Utils.addMonitoring
    --datatier NANOAODSIM
    --filein "file:${INFILE}"
    --fileout "file:${OUTFILE}"
    --conditions "$GT_MINI"
    --step NANO
    --era "$ERA"
    --scenario pp
    --mc
    --nThreads "$NTHREADS"
    -n "$NEVENTS"
)

# CRAB publication needs the framework job report of the cmsRun that produced
# the output.  When FLATPT_FJR_NANO is set (by crab/crab_job.sh), generate the
# config only and run cmsRun ourselves with -j; the default path is unchanged.
if [ -n "${FLATPT_FJR_NANO:-}" ]; then
    cmsDriver.py "${DRIVER_ARGS[@]}" --no_exec
    cmsRun -e -j "$FLATPT_FJR_NANO" "${CAMPAIGN_NANO}_cfg.py"
else
    cmsDriver.py "${DRIVER_ARGS[@]}"
fi

echo "  ✓ NanoAOD: $(ls -lh "$OUTFILE" | awk '{print $5}')"
