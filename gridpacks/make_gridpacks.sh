#!/bin/bash
#
# Build MadGraph gridpacks for the BulkGraviton -> HH grid.
#
# Usage:
#   ./make_gridpacks.sh --smoke                 # ONE point, to validate the setup
#   ./make_gridpacks.sh --point MX1200_MH125    # one named point
#   ./make_gridpacks.sh --all [--submit]        # the whole grid (ASK FIRST)
#
# Options:
#   --cards DIR    generated card directory (default gridpacks/cards_generated)
#   --eosdir DIR   where finished tarballs go (default $GRIDPACK_EOS)
#   --submit       use genproductions' condor submission instead of running locally
#   --dense        operate on the dense grid rather than the pilot
#
# genproductions is cloned on demand into gridpacks/genproductions.
#
# Environment (read from the release, NOT assumed):
#   gridpack_generation.sh picks scram_arch/CMSSW from /etc/redhat-release.
#   On EL9 that is el9_amd64_gcc11 + CMSSW_13_2_9 with MG5_aMC v2.9.18.
#   This differs from our GEN-SIM release (el9_amd64_gcc12 / CMSSW_14_0_19) and
#   that is fine: the gridpack is a self-contained tarball executed via
#   run_generic_tarball_cvmfs.sh, which is exactly how CMSSW runs it.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

CARDS_DIR="$SCRIPT_DIR/cards_generated"
EOSDIR="${GRIDPACK_EOS:-$EOS_OUTDIR/gridpacks}"
MODE=""
POINT=""
SUBMIT=false
DENSE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --smoke)  MODE="smoke" ;;
        --point)  MODE="point"; POINT="$2"; shift ;;
        --all)    MODE="all" ;;
        --cards)  CARDS_DIR="$2"; shift ;;
        --eosdir) EOSDIR="$2"; shift ;;
        --submit) SUBMIT=true ;;
        --dense)  DENSE="--dense" ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
    shift
done

[ -z "$MODE" ] && { echo "ERROR: need --smoke, --point NAME or --all"; exit 1; }

require_el9 || exit 1

GENPROD="$SCRIPT_DIR/genproductions"
if [ ! -d "$GENPROD" ]; then
    echo "──── cloning genproductions ────"
    git clone --filter=blob:none --sparse https://github.com/cms-sw/genproductions "$GENPROD"
    pushd "$GENPROD" > /dev/null
    git sparse-checkout set bin/MadGraph5_aMCatNLO
    popd > /dev/null
fi
GRIDGEN="$GENPROD/bin/MadGraph5_aMCatNLO"

# Generate the cards if they are not there yet.
if [ ! -d "$CARDS_DIR" ]; then
    echo "──── generating cards ────"
    python3 "$SCRIPT_DIR/gen_cards.py" --outdir "$CARDS_DIR" $DENSE
fi

# Which points to build.
case "$MODE" in
    smoke)
        # A point in the AK4-merged regime that is cheap and physically
        # representative of the sample's purpose.
        POINTS=("BulkGraviton_hh_GF_HH_narrow_MX1200_MH125")
        ;;
    point)
        POINTS=("$POINT")
        [[ "$POINT" != BulkGraviton* ]] && POINTS=("BulkGraviton_hh_GF_HH_narrow_${POINT}")
        ;;
    all)
        mapfile -t POINTS < <(ls "$CARDS_DIR")
        echo "════════════════════════════════════════════════════════════════"
        echo "  FULL GRID: ${#POINTS[@]} gridpacks"
        echo "  Each takes O(30-90 min) of CPU. Do not run this unattended"
        echo "  without --submit."
        echo "════════════════════════════════════════════════════════════════"
        ;;
esac

mkdir -p "$EOSDIR"
echo "  cards  : $CARDS_DIR"
echo "  output : $EOSDIR"
echo "  points : ${#POINTS[@]}"

WORKDIR="$SCRIPT_DIR/work"
mkdir -p "$WORKDIR"

for NAME in "${POINTS[@]}"; do
    CARDDIR="$CARDS_DIR/$NAME"
    if [ ! -d "$CARDDIR" ]; then
        echo "ERROR: no cards for $NAME in $CARDS_DIR"; exit 1
    fi

    if [ -n "$(ls "$EOSDIR"/${NAME}_*tarball.tar.xz 2>/dev/null)" ]; then
        echo "  ✓ $NAME already on EOS, skipping"
        continue
    fi

    echo ""
    echo "──── building $NAME ────"

    if [ "$SUBMIT" = true ]; then
        pushd "$GRIDGEN" > /dev/null
        # genproductions' own condor wrapper: <name> <carddir> <queue>
        ./submit_condor_gridpack_generation.sh "$NAME" "$CARDDIR" || {
            echo "ERROR: condor submission failed for $NAME"; popd > /dev/null; exit 1; }
        popd > /dev/null
        echo "  submitted to condor"
    else
        pushd "$GRIDGEN" > /dev/null
        # gridpack_generation.sh <name> <carddir> <queue> ; ALL = full workflow.
        # scram_arch/CMSSW are left to its OS-based defaults on purpose.
        ( ./gridpack_generation.sh "$NAME" "$CARDDIR" local ALL ) 2>&1 \
            | tee "$WORKDIR/${NAME}.log" | tail -20
        popd > /dev/null

        TARBALL=$(ls "$GRIDGEN"/${NAME}_*tarball.tar.xz 2>/dev/null | head -1)
        if [ -z "$TARBALL" ]; then
            echo "ERROR: no tarball produced for $NAME (see $WORKDIR/${NAME}.log)"
            exit 1
        fi
        echo "  staging $TARBALL -> $EOSDIR/"
        cp "$TARBALL" "$EOSDIR/" || xrdcp -f "$TARBALL" "root://eosuser.cern.ch/$EOSDIR/"
        echo "  ✓ $(basename "$TARBALL") ($(du -h "$TARBALL" | cut -f1))"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  done. gridpacks in $EOSDIR"
echo "  smoke-test one with:  ./gridpacks/test_gridpack.sh <tarball>"
echo "════════════════════════════════════════════════════════════════"
