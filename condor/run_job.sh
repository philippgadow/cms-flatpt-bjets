#!/bin/bash
#
# HTCondor payload: run the full chain for one job and copy MiniAOD + NanoAOD
# to EOS.
#
# Usage (by condor):  run_job.sh <jobid> <nevents> <seedbase> <repodir> <eosdir> [--no-pileup]
#
# Runs inside the el9 container (see submit.sh: +SingularityImage).

set -e

JOBID=${1:?need jobid}
NEVENTS=${2:?need nevents}
SEEDBASE=${3:?need seedbase}
REPODIR=${4:?need repodir}
EOSDIR=${5:?need eosdir}
PILEUP_FLAG="${6:-}"

# Per-job seed: distinct for every job, reproducible from the job id.
SEED=$(( SEEDBASE + JOBID ))

echo "════════════════════════════════════════════════════════════════"
echo "  condor job $JOBID   nevents=$NEVENTS   seed=$SEED"
echo "  host: $(hostname)   $(date)"
echo "  cwd : $PWD"
echo "════════════════════════════════════════════════════════════════"

# Work on the local scratch disk the batch system gave us.
WORKDIR="$PWD/work_${JOBID}"
mkdir -p "$WORKDIR"

# Releases are shared read-only from the repo area; the chain only writes to
# WORKDIR, except for the fragment/scram-build in the GEN-SIM release.
export RELEASE_DIR="$REPODIR/releases"
export NTHREADS="${NTHREADS:-4}"

# The release area on AFS is shared read-only between all jobs of a batch.
# Refuse to build into it from a job: concurrent jobs would race on the same
# files.  setup.sh must have installed and built the fragment before submission
# (submit.sh checks the hook; this covers the fragment).
export ALLOW_FRAGMENT_BUILD=0

"$REPODIR/production/run_fullchain.sh" \
    --nevents "$NEVENTS" \
    --seed "$SEED" \
    --outdir "$WORKDIR" \
    $PILEUP_FLAG

# ─── stage out ──────────────────────────────────────────────────────────────
source "$REPODIR/production/env.sh"

echo ""
echo "──── stage out to $EOSDIR ────"
mkdir -p "$EOSDIR"

stage() {
    local SRC="$1" DST="$2"
    if [ ! -f "$SRC" ]; then
        echo "  WARNING: $SRC not produced, skipping"
        return 0
    fi
    echo "  $SRC -> $DST"
    # EOS is fuse-mounted on lxplus/condor; fall back to xrdcp if not.
    if cp "$SRC" "$DST" 2>/dev/null; then
        echo "    ok ($(ls -lh "$DST" | awk '{print $5}'))"
    else
        xrdcp -f "$SRC" "root://eosuser.cern.ch/${DST}" || {
            echo "    ERROR: stage out failed"; return 1; }
        echo "    ok (xrdcp)"
    fi
}

stage "$WORKDIR/${CAMPAIGN_MINI}_${SAMPLE}.root" "$EOSDIR/${CAMPAIGN_MINI}_${SAMPLE}_${JOBID}.root"
stage "$WORKDIR/${CAMPAIGN_NANO}_${SAMPLE}.root" "$EOSDIR/${CAMPAIGN_NANO}_${SAMPLE}_${JOBID}.root"

# Intermediates are large and not staged out; drop them explicitly.
rm -rf "$WORKDIR"

echo ""
echo "✓ job $JOBID done at $(date)"
