#!/bin/bash
#
# Run a GEN-only job with configurable ZprimeFlatpTHook parameters.
# Used by both passes of the flatness calibration (see calibrate.sh).
#
# Usage:
#   ./run_genonly.sh <nevents> <seed> <p0> <p1> <outfile>
#
# GEN without SIM is fast (~O(100) evt/s), so 1e4-1e5 events are cheap.

set -e

NEVENTS=${1:?need nevents}
SEED=${2:?need seed}
P0=${3:?need p0}
P1=${4:?need p1}
OUTFILE=${5:?need output file}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

setup_release "$CMSSW_GS"

# Install a fragment variant with the requested hook parameters.
FRAG_NAME="flatpT_Zprime_bb_calib"
FRAG_DST="$CMSSW_BASE/src/Configuration/GenProduction/python/${FRAG_NAME}.py"
mkdir -p "$(dirname "$FRAG_DST")"
sed -e "s/^\( *p0 = cms.double(\).*/\1${P0}),/" \
    -e "s/^\( *p1 = cms.double(\).*/\1${P1}),/" \
    "$SCRIPT_DIR/../fragments/flatpT_Zprime_bb_fragment.py" > "$FRAG_DST"

echo "  hook parameters in use:"
grep -E "^ *(p0|p1|MaxSHat) = cms.double" "$FRAG_DST" | sed 's/^/    /'

pushd "$CMSSW_BASE/src" > /dev/null
scram b -j 8 > /dev/null 2>&1
popd > /dev/null

OUTDIR="$(cd "$(dirname "$OUTFILE")" && pwd)"
OUTBASE="$(basename "$OUTFILE")"

cmsDriver.py "Configuration/GenProduction/python/${FRAG_NAME}.py" \
    --python_filename "${OUTDIR}/${OUTBASE%.root}_cfg.py" \
    --eventcontent RAWSIM \
    --datatier GEN \
    --fileout "file:${OUTDIR}/${OUTBASE}" \
    --conditions "$GT_GS" \
    --beamspot DBrealistic \
    --step GEN \
    --geometry DB:Extended \
    --era "$ERA" \
    --nThreads "$NTHREADS" \
    --customise_commands "process.RandomNumberGeneratorService.generator.initialSeed=${SEED}\nprocess.RAWSIMoutput.outputCommands = cms.untracked.vstring('drop *', 'keep recoGenParticles_genParticles_*_*', 'keep GenEventInfoProduct_*_*_*')" \
    --mc \
    -n "$NEVENTS"

echo "  -> ${OUTDIR}/${OUTBASE}"
