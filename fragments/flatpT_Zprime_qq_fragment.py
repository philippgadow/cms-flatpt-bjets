import FWCore.ParameterSet.Config as cms

# OPTIONAL VARIANT -- not the primary deliverable.
#
# Flat-pT Z' with the ATLAS-like flavour mix (bb/cc/ss/uu/dd/gg) instead of
# 100% bb.  Useful for light-jet mistag studies, where b, c and light jets with
# the same flat pT spectrum are wanted in one sample.
#
# The tau channel of the original ATLAS jobOptions is dropped: this project is
# about jet flavour tagging, not hadronic taus.  Branching fractions are
# renormalised over the remaining quark/gluon channels.
#
# The primary deliverable is flatpT_Zprime_bb_fragment.py (100% Z' -> bb).
#
# As for the bb fragment: the hook modifies the trial cross section, so this
# sample has NO physical cross-section normalisation.

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *

generator = cms.EDFilter("Pythia8GeneratorFilter",
    maxEventsToPrint = cms.untracked.int32(0),
    pythiaPylistVerbosity = cms.untracked.int32(0),
    filterEfficiency = cms.untracked.double(1.0),
    pythiaHepMCVerbosity = cms.untracked.bool(False),
    comEnergy = cms.double(13600.),
    PythiaParameters = cms.PSet(
        pythia8CommonSettingsBlock,
        pythia8CP5SettingsBlock,
        processParameters = cms.vstring(
            'NewGaugeBoson:ffbar2gmZZprime = on',
            'Zprime:gmZmode = 3',
            '32:m0 = 4000.',
            '32:onMode = off',
            # Flavour mix, renormalised to unity over q qbar and gg:
            #   bb 0.24, cc 0.19, ss 0.19, uu 0.095, dd 0.095, gg 0.19
            '32:oneChannel = on 0.24  100 -5 5',
            '32:addChannel = 1 0.19  100 -4 4',
            '32:addChannel = 1 0.19  100 -3 3',
            '32:addChannel = 1 0.095 100 -2 2',
            '32:addChannel = 1 0.095 100 -1 1',
            '32:addChannel = 1 0.19  100 21 21',
            'PhaseSpace:mHatMin = 25.',
        ),
        parameterSets = cms.vstring(
            'pythia8CommonSettings',
            'pythia8CP5Settings',
            'processParameters',
        )
    ),
    UserCustomization = cms.VPSet(
        cms.PSet(
            pluginName = cms.string('ZprimeFlatpTHook'),
            # Same calibration as the bb fragment: the hook acts on sqrt(sHat),
            # which is independent of the decay flavour.
            p0 = cms.double(-8.95719),
            p1 = cms.double(1.62584e-03),
            MaxSHat = cms.double(13600.),
            DoDecayWeightBelow = cms.double(0.),
            DecayWeightP0 = cms.double(-0.000527117),
            DecayWeightP1 = cms.double(2.64665e-06),
            DecayWeightNorm = cms.double(0.008),
        )
    )
)

ProductionFilterSequence = cms.Sequence(generator)
