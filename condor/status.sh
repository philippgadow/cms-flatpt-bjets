#!/bin/bash
#
# Status / merge helper for a submitted batch.
#
# Usage:
#   ./status.sh                 # list all batches
#   ./status.sh <TAG>           # status of one batch
#   ./status.sh <TAG> --merge   # merge that batch's NanoAOD files
#   ./status.sh <TAG> --failed  # print the tails of failed job logs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

TAG="$1"
MODE="$2"

if [ -z "$TAG" ]; then
    echo "batches in $SCRIPT_DIR/logs:"
    for d in "$SCRIPT_DIR"/logs/*/; do
        [ -d "$d" ] || continue
        t=$(basename "$d")
        n_out=$(ls "$d"/job_*.out 2>/dev/null | wc -l)
        n_eos=$(ls "$EOS_OUTDIR/$t"/*NanoAODv15*.root 2>/dev/null | wc -l)
        printf "  %-20s  logs: %4d   NanoAOD on EOS: %4d\n" "$t" "$n_out" "$n_eos"
    done
    echo ""
    echo "current queue:"
    condor_q 2>/dev/null | tail -5 || echo "  (condor_q unavailable)"
    exit 0
fi

LOGDIR="$SCRIPT_DIR/logs/$TAG"
EOSDIR="$EOS_OUTDIR/$TAG"
[ -d "$LOGDIR" ] || { echo "no such batch: $TAG"; exit 1; }

N_OUT=$(ls "$LOGDIR"/job_*.out 2>/dev/null | wc -l)
N_DONE=$(grep -l "job .* done" "$LOGDIR"/job_*.out 2>/dev/null | wc -l)
N_NANO=$(ls "$EOSDIR"/*NanoAODv15*.root 2>/dev/null | wc -l)
N_MINI=$(ls "$EOSDIR"/*MiniAODv6*.root 2>/dev/null | wc -l)

echo "════════════════════════════════════════════════════════════════"
echo "  batch $TAG"
echo "════════════════════════════════════════════════════════════════"
echo "  job logs started   : $N_OUT"
echo "  jobs finished ok   : $N_DONE"
echo "  NanoAOD on EOS     : $N_NANO"
echo "  MiniAOD on EOS     : $N_MINI"
echo "  EOS dir            : $EOSDIR"

# Jobs whose log exists but which never reported completion.
FAILED=()
for f in "$LOGDIR"/job_*.out; do
    [ -f "$f" ] || continue
    if ! grep -q "done" "$f" 2>/dev/null; then
        FAILED+=("$f")
    fi
done
echo "  incomplete/failed  : ${#FAILED[@]}"

if [ "$MODE" = "--failed" ]; then
    for f in "${FAILED[@]}"; do
        echo ""
        echo "──── $f ────"
        tail -15 "$f"
        err="${f%.out}.err"
        [ -f "$err" ] && { echo "  -- stderr --"; tail -10 "$err"; }
    done
    exit 0
fi

if [ "$MODE" = "--merge" ]; then
    [ "$N_NANO" -eq 0 ] && { echo "nothing to merge"; exit 1; }
    setup_release "$CMSSW_MINI"
    MERGED="$EOSDIR/${CAMPAIGN_NANO}_${SAMPLE}_merged.root"
    echo ""
    echo "──── merging $N_NANO NanoAOD files ────"
    # haddnano.py preserves NanoAOD structure; fall back to plain hadd.
    if command -v haddnano.py > /dev/null 2>&1; then
        haddnano.py "$MERGED" "$EOSDIR"/*NanoAODv15*[0-9].root
    else
        hadd -f "$MERGED" "$EOSDIR"/*NanoAODv15*[0-9].root
    fi
    echo "  -> $MERGED  ($(ls -lh "$MERGED" | awk '{print $5}'))"
    echo ""
    echo "  validate:  python3 validation/validate_nanoaod.py $MERGED"
fi
