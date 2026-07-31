import os
import sys

import FWCore.ParameterSet.Config as cms

# OPTIONAL VARIANT of the graviton multigridpack sample -- not the primary
# deliverable (that is the H->bb one, ..._4B_...).
#
# Same (mX, mH) grid and mechanism, but with the central Run 2 "4Q" flavour
# mix instead of H -> bb only:
#
#     H -> bb : cc : ss : uu : dd  =  1/3 : 1/3 : 1/9 : 1/9 : 1/9
#
# i.e. one third b, one third charm, one third light -- which makes it the
# merged-jet analogue of the inclusive QCD sample: it provides double-b,
# double-c and double-light jets with the SAME kinematics, so a double-b
# tagger's mistag rate can be measured against a matched topology.
#
# Branching fractions reproduce the reference fragment from hqucms/event-producer
# behind /BulkGravitonToHHTo4Q_MX-600to6000_MH-15to250_.../MINIAODSIM.
#
# See the 4B fragment for the full mechanism documentation (per-lumi gridpack
# execution, GenLumiInfoHeader, Pythia8GeneratorFilter requirement).

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *

_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO, "gridpacks"))
import grid as gridmod  # noqa: E402

GRIDPACK_DIR = os.environ.get(
    "FLATPT_GRIDPACK_DIR",
    "/eos/user/p/pgadow/cms-flatpt-bjets/gridpacks")
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

# Flavour mix as in the central 4Q sample.
_DECAY_4Q = [
    '25:onMode = off',
    '25:oneChannel = 1 0.33333 100 5 -5',   # H -> b bbar
    '25:addChannel = 1 0.33333 100 4 -4',   # H -> c cbar
    '25:addChannel = 1 0.11111 100 3 -3',   # H -> s sbar
    '25:addChannel = 1 0.11111 100 2 -2',   # H -> u ubar
    '25:addChannel = 1 0.11111 100 1 -1',   # H -> d dbar
    'ResonanceDecayFilter:filter = on',
]

for _mx, _mh in gridmod.grid():
    _name = gridmod.point_name(_mx, _mh)
    _tarball = os.path.join(
        GRIDPACK_DIR,
        "%s_%s_%s_tarball.tar.xz" % (_name, GRIDPACK_ARCH, GRIDPACK_RELEASE))
    generator.RandomizedParameters.append(
        cms.PSet(
            ConfigWeight = cms.double(1.0),
            GridpackPath = cms.string(_tarball),
            ConfigDescription = cms.string(_name),
            PythiaParameters = cms.PSet(
                pythia8CommonSettingsBlock,
                pythia8CP5SettingsBlock,
                pythia8PSweightsSettingsBlock,
                processParameters = cms.vstring(*_DECAY_4Q),
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
