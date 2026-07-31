import FWCore.ParameterSet.Config as cms

# Option A2 -- flat-pT inclusive QCD (all flavours).
#
# The private 13.6 TeV analogue of the central QCD_Pt-15to7000 flat sample.
# Unlike A1 (matrix-element b bbar only), this keeps every hard QCD process, so
# the sample contains light-quark and gluon jets, charm, AND b jets from gluon
# splitting -- the topology that dominates the b-tag mistag rate and that a
# ME-only bb sample does not provide.
#
# Primary use case: mistag rates vs pT for all jet flavours, with uniform
# statistics up to multi-TeV.
#
# Same weighting caveat as A1: bias2Selection oversamples high pT-hat and
# compensates with a weight that reaches genWeight.  Unweighted spectrum is
# ~flat; fill any physical distribution with genWeight.  No absolute
# normalisation.
#
# Mechanism note: the central UL "Flat2018" samples instead used the CMSSW
# reweightGenEmp hook (an empirical per-tune pT-hat reweighting).  That hook
# does exist in this release (Pythia8Hadronizer handles a reweightGenEmp PSet),
# but it is tune-specific and opaque; bias2Selection is Pythia-native, tunable
# via a single exponent and documented, so it is used here.  See
# fragments/README.md for the comparison.

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
            # All hard QCD 2 -> 2 processes (light, gluon, charm, beauty).
            'HardQCD:all = on',
            'PhaseSpace:pTHatMin = 15',
            'PhaseSpace:pTHatMax = 7000',
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
