#!/bin/bash
#
# Status / merge helper for CRAB tasks (companion to condor/status.sh).
#
# Usage:
#   ./status.sh                     # list submitted tasks
#   ./status.sh <TASK>              # crab status of one task
#   ./status.sh <TASK> --merge      # merge that task's NanoAOD files (CERNBox)
#   ./status.sh <TASK> <crab args>  # anything else is passed to `crab status`
#
# <TASK> is the work/ subdirectory name, e.g. zprime_20260910_142530.
# For resubmission of failed jobs:  crab resubmit -d crab/work/<TASK>/crab_*

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

TASK="$1"
shift || true
MODE="${1:-}"

if [ -z "$TASK" ]; then
    echo "CRAB tasks in $SCRIPT_DIR/work:"
    for d in "$SCRIPT_DIR"/work/*/; do
        [ -d "$d" ] || continue
        t=$(basename "$d")
        proj=$(ls -d "$d"crab_*/ 2>/dev/null | head -1)
        printf "  %-30s  %s\n" "$t" "${proj:+project: $(basename "$proj")}"
    done
    echo ""
    echo "details:  ./status.sh <TASK>"
    exit 0
fi

TASKDIR="$SCRIPT_DIR/work/$TASK"
[ -d "$TASKDIR" ] || { echo "no such task: $TASK"; exit 1; }
CFG="$TASKDIR/crab_cfg.py"
# trailing slash: match only the project DIRECTORY, not crab_cfg.py
PROJDIR=$(ls -d "$TASKDIR"/crab_*/ 2>/dev/null | head -1)
PROJDIR="${PROJDIR%/}"

# Values recorded at submission time.
cfg_val() { sed -n "s/^config\.$1 = '\(.*\)'$/\1/p" "$CFG"; }
OUTLFN=$(cfg_val 'Data.outLFNDirBase')
PRIMARY=$(cfg_val 'Data.outputPrimaryDataset')
DSTAG=$(cfg_val 'Data.outputDatasetTag')
SITE=$(cfg_val 'Site.storageSite')

if [ "$MODE" = "--merge" ]; then
    if [ "$SITE" != "T3_CH_CERNBOX" ]; then
        echo "ERROR: --merge only knows the CERNBox path mapping (site is $SITE)."
        echo "       Fetch the files with xrdcp / rucio and merge manually."
        exit 1
    fi
    U="${OUTLFN#/store/user/}"; U="${U%%/*}"
    EOSDIR="/eos/user/${U:0:1}/${U}${OUTLFN#/store/user/$U}/$PRIMARY/$DSTAG"
    mapfile -t NANO < <(find "$EOSDIR" -name "${CAMPAIGN_NANO}_*.root" ! -name "*merged*" 2>/dev/null | sort)
    [ "${#NANO[@]}" -eq 0 ] && { echo "nothing to merge under $EOSDIR"; exit 1; }
    setup_release "$CMSSW_MINI"
    MERGED="$EOSDIR/${CAMPAIGN_NANO}_${PRIMARY}_merged.root"
    echo "──── merging ${#NANO[@]} NanoAOD files from $EOSDIR ────"
    # haddnano.py preserves NanoAOD structure; fall back to plain hadd.
    if command -v haddnano.py > /dev/null 2>&1; then
        haddnano.py "$MERGED" "${NANO[@]}"
    else
        hadd -f "$MERGED" "${NANO[@]}"
    fi
    echo "  -> $MERGED  ($(ls -lh "$MERGED" | awk '{print $5}'))"
    echo ""
    echo "  validate:  python3 validation/validate_nanoaod.py $MERGED"
    exit 0
fi

[ -n "$PROJDIR" ] || { echo "no crab project dir in $TASKDIR (submission failed?)"; exit 1; }

# The CRAB client refuses to run without a CMSSW environment, and lxplus ships
# a bare `crab` shim in the default PATH that fails the same way -- so always
# set up the env rather than trusting `command -v crab`.
setup_release "$CMSSW_GS" > /dev/null 2>&1
source /cvmfs/cms.cern.ch/common/crab-setup.sh > /dev/null 2>&1
crab status -d "$PROJDIR" "$@"
