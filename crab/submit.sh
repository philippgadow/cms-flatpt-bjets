#!/bin/bash
#
# Submit the flat-pT b-jet production to the grid via CRAB.
#
# There is no input dataset at GEN, so this uses CRAB's PrivateMC mode with a
# scriptExe (crab_job.sh) that runs the full multi-release chain on the worker
# node.  The CRAB sandbox is packed from the GEN-SIM release area, so the
# ZprimeFlatpT hook and the fragment must already be built there
# (production/setup.sh) -- the same pre-flight checks as condor/submit.sh.
#
# Usage:
#   ./submit.sh --njobs N --nevents M [options]
#
# Options:
#   --njobs N       number of jobs (required)
#   --nevents M     events per job (required).  CRAB caps the job runtime at
#                   ~46 h (2750 min), so keep premix jobs at O(500) events.
#   --sample T      zprime | qcd-bb | qcd-incl | grav-hbb   (default zprime).
#                   grav-hbb jobs fetch the FULL gridpack set over xrootd at
#                   job start (worker nodes cannot mount /eos/user), so every
#                   grid point must have a tarball in $GRIDPACK_EOS.
#   --seedbase S    seed offset, seed = S + CRAB_Id (1-based; default 100000).
#                   CHANGE THIS when adding statistics to an existing sample.
#   --no-pileup     run without premixed pileup (fast validation)
#   --site SITE     storage site (default T3_CH_CERNBOX = /eos/user)
#   --outlfn LFN    output LFN base (default /store/user/$USER/cms-flatpt-bjets/crab)
#   --gridpack-url U  xrootd location of the gridpacks for grav-hbb
#                   (default root://eosuser.cern.ch/$GRIDPACK_EOS)
#   --runtime MIN   maxJobRuntimeMin (default 2750, the CRAB maximum)
#   --publish       publish MiniAOD + NanoAOD as private datasets in DBS
#                   phys03 (/<primary>/<user>-<tag>-<hash>/USER, one dataset
#                   per output, kept apart by the output module label).
#   --tag T         extra token in the outputDatasetTag.  Defaults to
#                   NoXsecPerformanceOnly when --publish is given: these
#                   samples have NO physical normalisation, and the tag is
#                   what warns anyone who finds them in DAS.
#   --dry-run       write the CRAB config and tarball, do not submit
#
# Examples:
#   ./submit.sh --njobs 1 --nevents 20 --no-pileup     # smoke test
#   ./submit.sh --njobs 200 --nevents 500              # 100k events
#   ./submit.sh --njobs 2000 --nevents 500 --site T2_DE_DESY \
#               --publish            # 1M, published

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

NJOBS=""
NEVENTS=""
SEEDBASE=100000
PILEUP="yes"
SAMPLE_ARG="zprime"
SITE="T3_CH_CERNBOX"
OUTLFN="/store/user/$USER/cms-flatpt-bjets/crab"
RUNTIME=2750
GRIDPACK_URL=""
PUBLISH=False
USERTAG=""
DRYRUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --njobs)    NJOBS="$2"; shift ;;
        --nevents)  NEVENTS="$2"; shift ;;
        --sample)   SAMPLE_ARG="$2"; shift ;;
        --seedbase) SEEDBASE="$2"; shift ;;
        --no-pileup) PILEUP="no" ;;
        --site)     SITE="$2"; shift ;;
        --outlfn)   OUTLFN="$2"; shift ;;
        --runtime)  RUNTIME="$2"; shift ;;
        --gridpack-url) GRIDPACK_URL="$2"; shift ;;
        --publish)  PUBLISH=True ;;
        --tag)      USERTAG="$2"; shift ;;
        --dry-run)  DRYRUN=true ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
    shift
done

[ -z "$NJOBS" ]   && { echo "ERROR: --njobs is required";   exit 1; }
[ -z "$NEVENTS" ] && { echo "ERROR: --nevents is required"; exit 1; }

# Published datasets carry the no-normalisation warning in their name unless
# the user chose a tag themselves.
if [ "$PUBLISH" = "True" ] && [ -z "$USERTAG" ]; then
    USERTAG="NoXsecPerformanceOnly"
fi

select_sample "$SAMPLE_ARG" || exit 1

# ─── pre-flight checks ──────────────────────────────────────────────────────
# The graviton sample needs every grid point's gridpack: a missing point only
# fails once it is randomly drawn (same check as condor/submit.sh).  The jobs
# fetch the tarballs over xrootd, so also resolve the URL now.
GRIDPACK_SCRIPTARG=""
if [ "$SAMPLE_TYPE" = "grav-hbb" ]; then
    NPACK=$(ls "$GRIDPACK_EOS"/BulkGraviton_*tarball.tar.xz 2>/dev/null | wc -l)
    NPOINTS=$(python3 -c "import sys; sys.path.insert(0,'$REPO_DIR/gridpacks'); import grid; print(len(grid.grid()))")
    if [ "$NPACK" -eq 0 ]; then
        echo "ERROR: no gridpacks in $GRIDPACK_EOS."
        echo "       Run:  ./gridpacks/make_gridpacks.sh --all"
        exit 1
    fi
    if [ "$NPACK" -lt "$NPOINTS" ]; then
        echo "ERROR: only $NPACK of $NPOINTS gridpacks present in $GRIDPACK_EOS."
        echo "       Every grid point in the fragment must exist or jobs will"
        echo "       fail whenever a missing point is drawn."
        exit 1
    fi
    if [ -z "$GRIDPACK_URL" ]; then
        case "$GRIDPACK_EOS" in
            /eos/*) GRIDPACK_URL="root://eosuser.cern.ch/$GRIDPACK_EOS" ;;
            *) echo "ERROR: GRIDPACK_EOS=$GRIDPACK_EOS is not under /eos/;"
               echo "       pass --gridpack-url with an xrootd location instead."
               exit 1 ;;
        esac
    fi
    PACK_SIZE=$(du -sh "$GRIDPACK_EOS" 2>/dev/null | awk '{print $1}')
    echo "  gridpacks: $NPACK/$NPOINTS present in $GRIDPACK_EOS (${PACK_SIZE:-?})"
    echo "             each job downloads the full set from $GRIDPACK_URL"
    GRIDPACK_SCRIPTARG=", 'gridpacks=$GRIDPACK_URL'"
fi

# CRAB always needs a proxy, pileup or not (skip for --dry-run: no submission).
if [ "$DRYRUN" = false ]; then
    check_proxy || { echo "ERROR: CRAB needs a valid VOMS proxy."; exit 1; }
fi

# The sandbox is packed from the GEN-SIM release, so the hook must be built...
if [ "$SAMPLE_TYPE" = "zprime" ]; then
    if ! grep -q "ZprimeFlatpTHook" "$RELEASE_DIR/$CMSSW_GS/lib/$ARCH/.edmplugincache" 2>/dev/null; then
        echo "ERROR: ZprimeFlatpTHook not built in $RELEASE_DIR/$CMSSW_GS."
        echo "       Run:  source production/setup.sh"
        exit 1
    fi
fi

# ...and the fragment installed and importable (jobs only rebuild as fallback).
FRAG_SRC="$FRAGMENT"
FRAG_INST="$RELEASE_DIR/$CMSSW_GS/src/Configuration/GenProduction/python/${SAMPLE}.py"
if ! cmp -s "$FRAG_SRC" "$FRAG_INST"; then
    echo "ERROR: the fragment in $RELEASE_DIR/$CMSSW_GS is missing or out of date."
    echo "       Run:  source production/setup.sh gs"
    exit 1
fi
( setup_release "$CMSSW_GS"
  python3 -c "import Configuration.GenProduction.${SAMPLE}" > /dev/null 2>&1 ) || {
    echo "ERROR: Configuration.GenProduction.${SAMPLE} is not importable in $CMSSW_GS."
    echo "       Run:  source production/setup.sh gs"
    exit 1; }
echo "  fragment installed and importable in $CMSSW_GS"

# ─── task definition ────────────────────────────────────────────────────────
TAG="$(date +%Y%m%d_%H%M%S)"
WORKDIR="$SCRIPT_DIR/work/${SAMPLE_TYPE}_${TAG}"
REQUEST="flatpt_${SAMPLE_TYPE//-/_}_${TAG}"
TOTAL=$(( NJOBS * NEVENTS ))
MINI_FILE="${CAMPAIGN_MINI}_${SAMPLE}.root"
NANO_FILE="${CAMPAIGN_NANO}_${SAMPLE}.root"

# Dataset tag: campaign base (+ user token) + timestamp.  The tag names BOTH
# published datasets (mini and nano), so use the campaign without a datatier
# suffix.  DBS only allows [a-zA-Z0-9_-] here.
if [ -n "$USERTAG" ] && ! [[ "$USERTAG" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "ERROR: --tag may only contain letters, digits, _ and -"
    exit 1
fi
DSTAG="${CAMPAIGN_GS%GS}${USERTAG:+_$USERTAG}_${TAG}"

mkdir -p "$WORKDIR"

# Repo scripts for the worker node (crab_job.sh untars this next to PSet.py).
tar czf "$WORKDIR/flatpt_repo.tar.gz" -C "$REPO_DIR" \
    --exclude='fullchain_*' --exclude='test_*' --exclude='output*' \
    --exclude='*.root' --exclude='*.log' --exclude='__pycache__' \
    production fragments gridpacks

echo "════════════════════════════════════════════════════════════════"
echo "  cms-flatpt-bjets CRAB submission"
echo "    request     : $REQUEST"
echo "    sample      : $SAMPLE_TYPE ($SAMPLE)"
echo "    jobs        : $NJOBS"
echo "    events/job  : $NEVENTS"
echo "    total events: $TOTAL"
echo "    seeds       : $(( SEEDBASE + 1 )) .. $(( SEEDBASE + NJOBS ))"
echo "    pileup      : $PILEUP"
echo "    storage     : $SITE  $OUTLFN"
if [ "$PUBLISH" = "True" ]; then
    echo "    publication : DBS phys03, /$SAMPLE/<user>-$DSTAG-<hash>/USER (mini + nano)"
else
    echo "    publication : no"
fi
echo "    workdir     : $WORKDIR"
echo "════════════════════════════════════════════════════════════════"

cat > "$WORKDIR/crab_cfg.py" <<EOF
# Generated by crab/submit.sh on $(date) -- do not edit, resubmit instead.
from CRABClient.UserUtilities import config
config = config()

config.General.requestName = '$REQUEST'
config.General.workArea = '$WORKDIR'
config.General.transferOutputs = True
config.General.transferLogs = True

# PrivateMC: no input dataset; crab_job.sh runs the full chain in place of cmsRun.
config.JobType.pluginName = 'PrivateMC'
config.JobType.psetName = '$SCRIPT_DIR/PSet.py'
config.JobType.scriptExe = '$SCRIPT_DIR/crab_job.sh'
config.JobType.scriptArgs = ['nevents=$NEVENTS',
                             'seedbase=$SEEDBASE',
                             'sample=$SAMPLE_TYPE',
                             'pileup=$PILEUP',
                             'nthreads=$NTHREADS'$GRIDPACK_SCRIPTARG]
config.JobType.inputFiles = ['$WORKDIR/flatpt_repo.tar.gz',
                             '$SCRIPT_DIR/merge_fjr.py']
config.JobType.disableAutomaticOutputCollection = True
config.JobType.outputFiles = ['$MINI_FILE', '$NANO_FILE']
config.JobType.numCores = $NTHREADS
config.JobType.maxMemoryMB = $(( NTHREADS * 2000 ))
config.JobType.maxJobRuntimeMin = $RUNTIME
config.JobType.allowUndistributedCMSSW = True

config.Data.splitting = 'EventBased'
config.Data.unitsPerJob = $NEVENTS
config.Data.totalUnits = $TOTAL
config.Data.outputPrimaryDataset = '$SAMPLE'
config.Data.outputDatasetTag = '$DSTAG'
config.Data.outLFNDirBase = '$OUTLFN'
config.Data.publication = $PUBLISH

config.Site.storageSite = '$SITE'
EOF

if [ "$DRYRUN" = true ]; then
    echo ""
    echo "DRY RUN, config written to $WORKDIR/crab_cfg.py"
    echo "would submit with:"
    echo "  source /cvmfs/cms.cern.ch/common/crab-setup.sh"
    echo "  crab submit -c $WORKDIR/crab_cfg.py"
    exit 0
fi

# CRAB packs the sandbox from CMSSW_BASE, so submit from the GEN-SIM release
# (cmsenv first, then the CRAB client, per the recommended order).
setup_release "$CMSSW_GS"
source /cvmfs/cms.cern.ch/common/crab-setup.sh
crab submit -c "$WORKDIR/crab_cfg.py"

echo ""
echo "  submitted. monitor with:"
echo "    ./crab/status.sh ${SAMPLE_TYPE}_${TAG}"
echo "    crab status -d $WORKDIR/crab_$REQUEST"
if [ "$SITE" = "T3_CH_CERNBOX" ]; then
    U="${OUTLFN#/store/user/}"; U="${U%%/*}"
    echo "  output will appear under:"
    echo "    /eos/user/${U:0:1}/${U}${OUTLFN#/store/user/$U}/$SAMPLE/$DSTAG/"
fi
if [ "$PUBLISH" = "True" ]; then
    echo "  published datasets (once transfers finish; check crab status --long):"
    echo "    https://cmsweb.cern.ch/das/request?instance=prod/phys03&input=dataset=/$SAMPLE/*$DSTAG*/USER"
fi
