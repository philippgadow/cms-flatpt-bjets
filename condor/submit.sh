#!/bin/bash
#
# Submit the flat-pT b-jet production to lxplus HTCondor.
#
# There is no input dataset at GEN, so this uses plain HTCondor rather than
# CRAB.  Each job generates its own events with a distinct seed and stages
# MiniAOD + NanoAOD out to EOS.
#
# Usage:
#   ./submit.sh --njobs N --nevents M [options]
#
# Options:
#   --njobs N       number of jobs (required)
#   --nevents M     events per job (required; O(500-1000) is a sensible size)
#   --seedbase S    seed offset, seed = S + ProcId (default 100000).
#                   CHANGE THIS when adding statistics to an existing sample.
#   --no-pileup     run without premixed pileup (fast validation)
#   --flavour F     JobFlavour (default testmatch = 3 days)
#   --dry-run       write the submit file and print the command, do not submit
#
# Timing: 20 events without pileup took ~7 min at 8 threads on an interactive
# node, i.e. ~20 s/event.  A batch node at 4 threads is slower and premix adds
# more, so budget generously: espresso (20 min) only fits a ~20-event smoke
# test, and 500-event production jobs need testmatch.
#
# Examples:
#   ./submit.sh --njobs 1 --nevents 20 --no-pileup --flavour microcentury  # smoke test
#   ./submit.sh --njobs 200 --nevents 500                                  # 100k events

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

NJOBS=""
NEVENTS=""
SEEDBASE=100000
PILEUPFLAG=""
FLAVOUR="testmatch"
DRYRUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --njobs)    NJOBS="$2"; shift ;;
        --nevents)  NEVENTS="$2"; shift ;;
        --seedbase) SEEDBASE="$2"; shift ;;
        --no-pileup) PILEUPFLAG="--no-pileup" ;;
        --flavour)  FLAVOUR="$2"; shift ;;
        --dry-run)  DRYRUN=true ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
    shift
done

[ -z "$NJOBS" ]   && { echo "ERROR: --njobs is required";   exit 1; }
[ -z "$NEVENTS" ] && { echo "ERROR: --nevents is required"; exit 1; }

# ─── pre-flight checks ──────────────────────────────────────────────────────
# Premix needs a proxy inside the job; check now rather than after queueing.
if [ -z "$PILEUPFLAG" ]; then
    check_proxy || { echo "ERROR: premix jobs need a proxy. Use --no-pileup to skip."; exit 1; }
fi

PROXY="${X509_USER_PROXY:-/tmp/x509up_u$(id -u)}"
if [ ! -f "$PROXY" ]; then
    echo "ERROR: proxy file $PROXY not found. Run voms-proxy-init."
    exit 1
fi

# The hook must be built, or every job fails identically.
if ! grep -q "ZprimeFlatpTHook" "$RELEASE_DIR/$CMSSW_GS/lib/$ARCH/.edmplugincache" 2>/dev/null; then
    echo "ERROR: ZprimeFlatpTHook not built in $RELEASE_DIR/$CMSSW_GS."
    echo "       Run:  source production/setup.sh"
    exit 1
fi

# Jobs are forbidden from building into the shared release area, so the
# fragment must already be installed there and be importable.  scram compiles
# GenProduction python in place under src/, so check the import rather than
# looking for a copy under python/.
FRAG_SRC="$REPO_DIR/fragments/flatpT_Zprime_bb_fragment.py"
FRAG_INST="$RELEASE_DIR/$CMSSW_GS/src/Configuration/GenProduction/python/${SAMPLE}.py"
if ! cmp -s "$FRAG_SRC" "$FRAG_INST"; then
    echo "ERROR: the fragment in $RELEASE_DIR/$CMSSW_GS is missing or out of date."
    echo "       Jobs may not build into the shared release area."
    echo "       Run:  source production/setup.sh gs"
    exit 1
fi
( setup_release "$CMSSW_GS"
  python3 -c "import Configuration.GenProduction.${SAMPLE}" > /dev/null 2>&1 ) || {
    echo "ERROR: Configuration.GenProduction.${SAMPLE} is not importable in $CMSSW_GS."
    echo "       Run:  source production/setup.sh gs"
    exit 1; }
echo "  fragment installed and importable in $CMSSW_GS"

TAG="$(date +%Y%m%d_%H%M%S)"
LOGDIR="$SCRIPT_DIR/logs/$TAG"
EOSDIR="$EOS_OUTDIR/$TAG"
mkdir -p "$LOGDIR"

TOTAL=$(( NJOBS * NEVENTS ))

echo "════════════════════════════════════════════════════════════════"
echo "  cms-flatpt-bjets condor submission"
echo "    jobs        : $NJOBS"
echo "    events/job  : $NEVENTS"
echo "    total events: $TOTAL"
echo "    seeds       : $(( SEEDBASE )) .. $(( SEEDBASE + NJOBS - 1 ))"
echo "    pileup      : $([ -n "$PILEUPFLAG" ] && echo no || echo yes)"
echo "    flavour     : $FLAVOUR"
echo "    logs        : $LOGDIR"
echo "    output      : $EOSDIR"
echo "════════════════════════════════════════════════════════════════"

mkdir -p "$EOSDIR"

# Disk: measured ~4 MB/event without pileup for the sum of all intermediates
# (GEN-SIM 1.3 + RAW 1.9 + AOD 0.5 + Mini 0.2 + Nano 0.13 MB/evt).  Premix
# roughly triples the RAW step, so budget 15 MB/event there, and keep a 5 GB
# floor for the release/scratch overhead.
# PILEUPFLAG is non-empty when --no-pileup was given.
if [ -n "$PILEUPFLAG" ]; then
    PER_EVENT_KB=4000     # measured, no pileup
else
    PER_EVENT_KB=15000    # premix inflates the RAW step
fi
DISK_KB=$(( NEVENTS * PER_EVENT_KB + 5000000 ))

CMD=(condor_submit "$SCRIPT_DIR/submit.sub"
     -append "REPODIR = $REPO_DIR"
     -append "EOSDIR = $EOSDIR"
     -append "LOGDIR = $LOGDIR"
     -append "NJOBS = $NJOBS"
     -append "NEVENTS = $NEVENTS"
     -append "SEEDBASE = $SEEDBASE"
     -append "PILEUPFLAG = $PILEUPFLAG"
     -append "PROXY = $PROXY"
     -append "FLAVOUR = $FLAVOUR"
     -append "NCPUS = $NTHREADS"
     -append "MEMORY = $(( NTHREADS * 2000 ))"
     -append "DISK = $DISK_KB")

if [ "$DRYRUN" = true ]; then
    echo ""
    echo "DRY RUN, would submit:"
    printf '  %q\n' "${CMD[@]}"
    exit 0
fi

"${CMD[@]}"

echo ""
echo "  submitted. monitor with:"
echo "    ./condor/status.sh $TAG"
echo "    condor_q"
