#!/bin/bash
#
# Local full chain: GEN-SIM -> DIGI/HLT -> RECO -> MiniAODv6 -> NanoAODv15
#
# Usage:
#   ./run_fullchain.sh [--no-pileup] [--nevents N] [--seed S] [--skip-to K]
#
# Options:
#   --no-pileup   skip premixed pileup (much faster; no proxy needed)
#   --nevents N   events to process (default 100)
#   --seed S      random seed (default 12345)
#   --skip-to K   resume at step K (0-4) reusing existing intermediate files
#   --outdir DIR  working directory (default production/fullchain_<timestamp>)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

NEVENTS=100
SEED=12345
SKIP_TO=0
PILEUP_FLAG=""
OUTDIR=""

SAMPLE_ARG="${SAMPLE_TYPE:-zprime}"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-pileup) PILEUP_FLAG="--no-pileup" ;;
        --nevents)   NEVENTS="$2"; shift ;;
        --seed)      SEED="$2"; shift ;;
        --skip-to)   SKIP_TO="$2"; shift ;;
        --outdir)    OUTDIR="$2"; shift ;;
        --sample)    SAMPLE_ARG="$2"; shift ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Sets SAMPLE + FRAGMENT (+ EVENTS_PER_LUMI for the graviton grid).
select_sample "$SAMPLE_ARG" || exit 1

require_el9 || exit 1

[ -z "$OUTDIR" ] && OUTDIR="$SCRIPT_DIR/fullchain_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

F_GS="$OUTDIR/${CAMPAIGN_GS}_${SAMPLE}.root"
F_DR="$OUTDIR/${CAMPAIGN_DR}_${SAMPLE}.root"
F_RECO="$OUTDIR/${CAMPAIGN_RECO}_${SAMPLE}.root"
F_MINI="$OUTDIR/${CAMPAIGN_MINI}_${SAMPLE}.root"
F_NANO="$OUTDIR/${CAMPAIGN_NANO}_${SAMPLE}.root"

echo "════════════════════════════════════════════════════════════════"
echo "  Full chain: $SAMPLE_TYPE ($SAMPLE)"
echo "    fragment: $(basename "$FRAGMENT")"
echo "    events  : $NEVENTS"
echo "    seed    : $SEED"
echo "    pileup  : $([ -n "$PILEUP_FLAG" ] && echo no || echo yes)"
echo "    skip-to : step $SKIP_TO"
echo "    workdir : $OUTDIR"
echo "════════════════════════════════════════════════════════════════"

cd "$OUTDIR"

START=$(date +%s)

[ "$SKIP_TO" -le 0 ] && "$SCRIPT_DIR/steps/step0_gensim.sh"  "$NEVENTS" "$SEED" "$F_GS"
[ "$SKIP_TO" -le 1 ] && "$SCRIPT_DIR/steps/step1_digihlt.sh" "$F_GS"   "$NEVENTS" "$SEED" "$F_DR" $PILEUP_FLAG
[ "$SKIP_TO" -le 2 ] && "$SCRIPT_DIR/steps/step2_reco.sh"    "$F_DR"   "$NEVENTS" "$F_RECO"
[ "$SKIP_TO" -le 3 ] && "$SCRIPT_DIR/steps/step3_miniaod.sh" "$F_RECO" "$NEVENTS" "$F_MINI"
[ "$SKIP_TO" -le 4 ] && "$SCRIPT_DIR/steps/step4_nanoaod.sh" "$F_MINI" "$NEVENTS" "$F_NANO"

ELAPSED=$(( $(date +%s) - START ))

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Chain complete in ${ELAPSED}s ($(( ELAPSED / 60 )) min)"
echo "════════════════════════════════════════════════════════════════"
ls -lh "$OUTDIR"/*.root 2>/dev/null | awk '{printf "  %-70s %s\n", $9, $5}'
echo ""
echo "  Validate:  python3 validation/validate_nanoaod.py $F_NANO"
