import FWCore.ParameterSet.Config as cms

# Option A1 -- flat-pT QCD, bb-bar enriched (matrix-element b quarks).
#
# Complements the Z' sample: instead of isolated single-b jets from a 2 -> 1
# resonance, these are ME b's produced in a realistic QCD environment (initial-
# and final-state radiation, MPI, colour connection to the beam remnants).
#
# Flattening uses Pythia's own PhaseSpace:bias2Selection, which oversamples
# high pT-hat by (pTHat/pTRef)^pow and assigns the inverse as a compensating
# weight.  This ONLY works for 2 -> 2 processes (Pythia aborts otherwise),
# which is why the 2 -> 1 Z' needs the custom ZprimeFlatpT hook instead.
#
# >>> THESE EVENTS ARE WEIGHTED <<<
# The compensating weight reaches GenEventInfoProduct -> genWeight in NanoAOD.
# The UNWEIGHTED pT spectrum is approximately flat (that is the point: uniform
# statistics per pT bin); the WEIGHTED spectrum reproduces the physical, steeply
# falling QCD one.  Any physical distribution must be filled with genWeight.
# As with the other samples in this repo, there is no usable absolute
# normalisation -- this is an object-performance sample.
#
# bias2SelectionPow is tuned in calibration/tune_qcd_bias.py; see
# calibration/results_qcd/ for the scan behind the value below.

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *

generator = cms.EDFilter("Pythia8GeneratorFilter",
    maxEventsToPrint = cms.untracked.int32(0),
    pythiaPylistVerbosity = cms.untracked.int32(0),
    filterEfficiency = cms.untracked.double(1.0),
    pythiaHepMCVerbosity = cms.untracked.bool(False),
    comEnergy = cms.double(13600.),
    PythiaParameters = cms.PSet(
        pythia8CommonSettingsBlock,
        pythia8CP5SettingsBlock,
        pythia8PSweightsSettingsBlock,
        processParameters = cms.vstring(
            # Matrix-element b bbar production only.
            'HardQCD:gg2bbbar = on',
            'HardQCD:qqbar2bbbar = on',
            # pTHatMin must be > 0: a pTHat = 0 event would get infinite weight.
            'PhaseSpace:pTHatMin = 15',
            'PhaseSpace:pTHatMax = 4000',
            # Flat-in-pT sampling with compensating weights (2 -> 2 only).
            'PhaseSpace:bias2Selection = on',
            'PhaseSpace:bias2SelectionPow = 4.5',
            'PhaseSpace:bias2SelectionRef = 15.',
        ),
        parameterSets = cms.vstring(
            'pythia8CommonSettings',
            'pythia8CP5Settings',
            'pythia8PSweightsSettings',
            'processParameters',
        )
    )
)

ProductionFilterSequence = cms.Sequence(generator)
