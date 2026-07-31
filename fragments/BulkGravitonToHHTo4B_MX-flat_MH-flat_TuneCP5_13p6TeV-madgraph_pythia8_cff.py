import os
import sys

import FWCore.ParameterSet.Config as cms

# Option B -- BulkGraviton -> HH -> bb bb, "multigridpack" (mX, mH) scan.
#
# Physics purpose: MERGED double-b jets.  Both b hadrons from one H land inside
# a single AK4 (or AK8) jet, which is the topology that single-b samples like
# the Z' and QCD-bb cannot provide.  The opening angle is tunable:
#
#     dR(bb) ~ 2*mH/pT(H) ~ 4*mH/mX
#
# so scanning (mX, mH) scans dR(bb) from deeply merged to resolved.
#
# Mechanism (verified against CMSSW_14_0_19, see gridpacks/README.md):
#   * RandomizedParameters is read by gen::BaseHadronizer. For EACH LUMINOSITY
#     BLOCK it picks one PSet (weighted by ConfigWeight) and forks
#     run_generic_tarball_cvmfs.sh on that PSet's GridpackPath to make the LHE.
#   * The chosen point is recorded in GenLumiInfoHeader (setConfigDescription),
#     NOT per event -- so the grid point is constant within a lumi block and
#     validation must map lumi -> (mX, mH).
#   * numberEventsInLuminosityBlock therefore sets the events per grid point.
#   * MUST use Pythia8GeneratorFilter: ConcurrentGeneratorFilter calls
#     randomizeIndex but never generateLHE, so gridpacks silently would not run.
#
# Ancestry: this is the 13.6 TeV, H->bb analogue of the central Run 2 samples
#   /BulkGravitonToHHTo4Q_MX-600to6000_MH-15to250_part{1,2,3}_TuneCP5_13TeV
#    -madgraph_pythia8/RunIIAutumn18MiniAOD-multigridpack_.../MINIAODSIM
#
# Normalisation: the grid is a scan of discrete points, not a physical mass
# spectrum. ConfigWeight sets only the relative sampling. No physical cross
# section -- object-performance sample, like the rest of this repo.

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *

# The grid definition is shared with the card/gridpack generation so the
# fragment can never point at a mass point that was never produced.
_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO, "gridpacks"))
import grid as gridmod  # noqa: E402

# Base directory holding the gridpack tarballs. Override with the
# FLATPT_GRIDPACK_DIR environment variable (condor jobs set it from env.sh).
GRIDPACK_DIR = os.environ.get(
    "FLATPT_GRIDPACK_DIR",
    "/eos/user/p/pgadow/cms-flatpt-bjets/gridpacks")

# Tarball naming as produced by genproductions on EL9:
#   <name>_<scram_arch>_<cmssw_version>_tarball.tar.xz
GRIDPACK_ARCH = os.environ.get("FLATPT_GRIDPACK_ARCH", "el9_amd64_gcc11")
GRIDPACK_RELEASE = os.environ.get("FLATPT_GRIDPACK_RELEASE", "CMSSW_13_2_9")

generator = cms.EDFilter("Pythia8GeneratorFilter",
    maxEventsToPrint = cms.untracked.int32(0),
    pythiaPylistVerbosity = cms.untracked.int32(0),
    filterEfficiency = cms.untracked.double(1.0),
    pythiaHepMCVerbosity = cms.untracked.bool(False),
    comEnergy = cms.double(13600.),
    RandomizedParameters = cms.VPSet(),
)

# Default decay: H -> b bbar only. The goal is boosted H(bb); the flavour-mix
# variant for mistag/charm studies lives in the *_4Q_* fragment.
_DECAY_HBB = [
    '25:onMode = off',
    '25:onIfMatch = 5 -5',
    'ResonanceDecayFilter:filter = on',
]

for _mx, _mh in gridmod.grid():
    _name = gridmod.point_name(_mx, _mh)
    _tarball = os.path.join(
        GRIDPACK_DIR,
        "%s_%s_%s_tarball.tar.xz" % (_name, GRIDPACK_ARCH, GRIDPACK_RELEASE))
    generator.RandomizedParameters.append(
        cms.PSet(
            # Uniform sampling across grid points.
            ConfigWeight = cms.double(1.0),
            GridpackPath = cms.string(_tarball),
            ConfigDescription = cms.string(_name),
            PythiaParameters = cms.PSet(
                pythia8CommonSettingsBlock,
                pythia8CP5SettingsBlock,
                pythia8PSweightsSettingsBlock,
                processParameters = cms.vstring(*_DECAY_HBB),
                parameterSets = cms.vstring(
                    'pythia8CommonSettings',
                    'pythia8CP5Settings',
                    'pythia8PSweightsSettings',
                    'processParameters',
                )
            )
        )
    )

ProductionFilterSequence = cms.Sequence(generator)
