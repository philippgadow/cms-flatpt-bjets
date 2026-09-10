#!/bin/bash
#
# CRAB scriptExe payload: run the full chain for one job on a grid worker node
# and leave MiniAOD + NanoAOD in the job directory for CRAB stage-out.
#
# CRAB invokes this as:
#   crab_job.sh <jobid> nevents=N seedbase=S sample=T pileup=yes|no nthreads=K \
#               [gridpacks=root://host//path]
# where <jobid> is the 1-based CRAB job number (also in $CRAB_Id).  The
# gridpacks argument is only present for grav-hbb: the tarballs are fetched
# from that xrootd location, since grid worker nodes cannot mount /eos/user.
#
# Environment provided by the CRAB job wrapper:
#   - the GEN-SIM release (CMSSW_14_0_19) is set up from the sandbox, which was
#     packed from the repo's release area and therefore contains the built
#     ZprimeFlatpT hook and the installed fragment;
#   - cvmfs is mounted (the other releases are created here with scram p);
#   - X509_USER_PROXY points at a valid proxy (needed for premix over AAA);
#   - PSet.py and the inputFiles (flatpt_repo.tar.gz) are in the working dir.

set -e

JOBID="${CRAB_Id:-${1:?need job id}}"
shift || true

NEVENTS=""
SEEDBASE=100000
SAMPLE_TYPE_ARG="zprime"
PILEUP="yes"
NTHREADS_ARG=4
GRIDPACK_URL=""

for arg in "$@"; do
    case "$arg" in
        nevents=*)   NEVENTS="${arg#*=}" ;;
        seedbase=*)  SEEDBASE="${arg#*=}" ;;
        sample=*)    SAMPLE_TYPE_ARG="${arg#*=}" ;;
        pileup=*)    PILEUP="${arg#*=}" ;;
        nthreads=*)  NTHREADS_ARG="${arg#*=}" ;;
        gridpacks=*) GRIDPACK_URL="${arg#*=}" ;;
        *) ;;   # ignore anything else CRAB may append
    esac
done

[ -z "$NEVENTS" ] && { echo "ERROR: nevents=N missing from scriptArgs"; exit 1; }

# Per-job seed: distinct for every job, reproducible from the CRAB job number.
# A resubmitted job keeps its CRAB_Id and therefore its seed.
SEED=$(( SEEDBASE + JOBID ))

PILEUP_FLAG=""
[ "$PILEUP" = "no" ] && PILEUP_FLAG="--no-pileup"

JOBDIR="$PWD"

echo "════════════════════════════════════════════════════════════════"
echo "  crab job $JOBID   sample=$SAMPLE_TYPE_ARG   nevents=$NEVENTS   seed=$SEED"
echo "  host: $(hostname)   $(date)"
echo "  cwd : $JOBDIR"
echo "  pileup: $PILEUP   threads: $NTHREADS_ARG"
echo "════════════════════════════════════════════════════════════════"

# The GEN-SIM release comes from the CRAB sandbox; the wrapper has already
# scram-projected it and set CMSSW_BASE before calling this script.
GS_BASE="${CMSSW_BASE:-$(ls -d "$JOBDIR"/CMSSW_* 2>/dev/null | head -1)}"
[ -z "$GS_BASE" ] && { echo "ERROR: no CMSSW area found (CMSSW_BASE unset)"; exit 1; }
echo "  GEN-SIM release from sandbox: $GS_BASE"

# Unpack the repo scripts shipped as an input file.
mkdir -p "$JOBDIR/repo"
tar xzf "$JOBDIR/flatpt_repo.tar.gz" -C "$JOBDIR/repo"

# Local release area: the sandbox release is linked in, the other releases are
# created fresh from cvmfs by setup_release (a few minutes, mostly symlinks).
export RELEASE_DIR="$JOBDIR/releases"
mkdir -p "$RELEASE_DIR"
ln -sfn "$GS_BASE" "$RELEASE_DIR/$(basename "$GS_BASE")"

export NTHREADS="$NTHREADS_ARG"

# ─── gridpacks (grav-hbb only) ──────────────────────────────────────────────
# The fragment draws a random (mX, mH) point per luminosity block, so EVERY
# tarball must be locally available.  Grid worker nodes cannot mount /eos/user,
# so fetch the whole set over xrootd (the CRAB proxy authenticates to eosuser).
if [ "$SAMPLE_TYPE_ARG" = "grav-hbb" ]; then
    [ -z "$GRIDPACK_URL" ] && { echo "ERROR: sample=grav-hbb needs gridpacks=<xrootd url>"; exit 1; }
    XRD_HOST="${GRIDPACK_URL#root://}"; XRD_HOST="${XRD_HOST%%/*}"
    # normalize any number of leading slashes to exactly one
    XRD_PATH="${GRIDPACK_URL#root://$XRD_HOST}"
    XRD_PATH="/$(printf '%s' "$XRD_PATH" | sed 's|^/*||')"
    echo ""
    echo "──── fetching gridpacks from root://$XRD_HOST/$XRD_PATH ────"
    mkdir -p "$JOBDIR/gridpacks_local"
    mapfile -t PACKS < <(xrdfs "$XRD_HOST" ls "$XRD_PATH" | grep '_tarball\.tar\.xz$')
    [ "${#PACKS[@]}" -eq 0 ] && { echo "ERROR: no gridpack tarballs found at $GRIDPACK_URL"; exit 1; }
    for p in "${PACKS[@]}"; do
        xrdcp -s "root://$XRD_HOST/$p" "$JOBDIR/gridpacks_local/" \
            || { echo "ERROR: failed to fetch $p"; exit 1; }
    done
    echo "  fetched ${#PACKS[@]} tarballs ($(du -sh "$JOBDIR/gridpacks_local" | awk '{print $1}'))"
    # env.sh derives FLATPT_GRIDPACK_DIR from GRIDPACK_EOS for this sample.
    export GRIDPACK_EOS="$JOBDIR/gridpacks_local"
fi

# The release copy is job-local, so letting step0 (re)build the fragment is
# safe here -- it is only a fallback; normally the sandbox already has it.
export ALLOW_FRAGMENT_BUILD=1

# Unique (lumi, event) ranges per job: without these every job starts at
# lumi 1 / event 1, and the published datasets would carry duplicate event ids
# across files.  Strides leave plenty of headroom (lumis used per job =
# nevents / EVENTS_PER_LUMI, well below 10000).
export FLATPT_FIRSTLUMI=$(( (JOBID - 1) * 10000 + 1 ))
export FLATPT_FIRSTEVENT=$(( (JOBID - 1) * NEVENTS + 1 ))

# Real framework job reports from the Mini/Nano cmsRun steps -- CRAB publishes
# exactly what these reports declare (see merge below).
export FLATPT_FJR_MINI="$JOBDIR/fjr_mini.xml"
export FLATPT_FJR_NANO="$JOBDIR/fjr_nano.xml"

"$JOBDIR/repo/production/run_fullchain.sh" \
    --sample "$SAMPLE_TYPE_ARG" \
    --nevents "$NEVENTS" \
    --seed "$SEED" \
    --outdir "$JOBDIR/out" \
    $PILEUP_FLAG

# ─── collect outputs for CRAB stage-out ─────────────────────────────────────
# CRAB picks up JobType.outputFiles from the working directory and appends the
# job number to the filenames at the destination.
source "$JOBDIR/repo/production/env.sh"
select_sample "$SAMPLE_TYPE_ARG" || exit 1

for f in "${CAMPAIGN_MINI}_${SAMPLE}.root" "${CAMPAIGN_NANO}_${SAMPLE}.root"; do
    [ -f "$JOBDIR/out/$f" ] || { echo "ERROR: expected output $f not produced"; exit 1; }
    mv "$JOBDIR/out/$f" "$JOBDIR/$f"
    echo "  output: $f ($(ls -lh "$JOBDIR/$f" | awk '{print $5}'))"
done

# Intermediates (GEN-SIM/RAW/AOD) and fetched gridpacks are large and not
# staged out.
rm -rf "$JOBDIR/out" "$JOBDIR/gridpacks_local"

# ─── FrameworkJobReport.xml ─────────────────────────────────────────────────
# Every scriptExe job must hand CRAB a valid framework job report, and
# publication uses exactly the output <File> sections it contains.  Merge the
# real reports of the Mini and Nano cmsRun steps into one, as if a single
# cmsRun had written both outputs.
echo ""
echo "──── assembling FrameworkJobReport.xml (nano + mini) ────"
for fjr in "$FLATPT_FJR_NANO" "$FLATPT_FJR_MINI"; do
    [ -f "$fjr" ] || { echo "ERROR: $fjr missing -- cmsRun did not write its report"; exit 1; }
done
# --pfn-dir: the reports still point into out/, but the files were moved to
# JOBDIR above and CRAB stats the PFNs to add sizes and checksums.
python3 "$JOBDIR/merge_fjr.py" --pfn-dir "$JOBDIR" \
    "$FLATPT_FJR_NANO" "$FLATPT_FJR_MINI" \
    > "$JOBDIR/FrameworkJobReport.xml"

echo ""
echo "✓ crab job $JOBID done at $(date)"
