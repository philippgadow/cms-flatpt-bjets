#!/bin/bash
#
# GEN-only job for the QCD bias2SelectionPow scan (see tune_qcd_bias.py).
#
# Usage:
#   ./run_genonly_qcd.sh <fragment> <nevents> <seed> <bias2SelectionPow> <outfile>
#
# Unlike the Z' calibration runner, this keeps ak4GenJets as well as
# genParticles: the QCD flatness target is the leading JET pT, not sqrt(sHat).

set -e
set -o pipefail

FRAGMENT=${1:?need fragment}
NEVENTS=${2:?need nevents}
SEED=${3:?need seed}
POW=${4:?need bias2SelectionPow}
OUTFILE=${5:?need output file}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../production/env.sh"

setup_release "$CMSSW_GS"

FRAG_NAME="qcd_biasscan"
FRAG_DST="$CMSSW_BASE/src/Configuration/GenProduction/python/${FRAG_NAME}.py"
mkdir -p "$(dirname "$FRAG_DST")"

# Substitute the scanned exponent into a copy of the fragment.
sed -e "s/^\( *'PhaseSpace:bias2SelectionPow = \).*/\1${POW}',/" \
    "$FRAGMENT" > "$FRAG_DST"

echo "  bias2Selection settings in use:"
grep -E "bias2Selection|pTHatM" "$FRAG_DST" | sed 's/^/    /'

pushd "$CMSSW_BASE/src" > /dev/null
scram b -j 8 > /dev/null 2>&1
popd > /dev/null

OUTDIR="$(cd "$(dirname "$OUTFILE")" && pwd)"
OUTBASE="$(basename "$OUTFILE")"

# Keep genParticles, the generator info (weights!) and the AK4 GenJets.
KEEP="process.RAWSIMoutput.outputCommands = cms.untracked.vstring('drop *', 'keep recoGenParticles_genParticles_*_*', 'keep GenEventInfoProduct_*_*_*', 'keep recoGenJets_ak4GenJets_*_*')"

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
    --customise_commands "process.RandomNumberGeneratorService.generator.initialSeed=${SEED}\n${KEEP}" \
    --mc \
    -n "$NEVENTS"

echo "  -> ${OUTDIR}/${OUTBASE}"
