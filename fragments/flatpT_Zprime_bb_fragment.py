import FWCore.ParameterSet.Config as cms

# Flat-pT b-jet sample: ffbar -> Z'(4 TeV, gmZmode=3) -> b bbar, with the
# ZprimeFlatpTHook reweighting the trial cross section so that sqrt(sHat) --
# and hence the b-jet pT ~ sqrt(sHat)/2 -- is flat up to several TeV.
#
# NOTE ON NORMALISATION: the hook modifies the trial cross section, so the
# cross section reported by Pythia8 and any per-event weight carry NO physical
# meaning.  This is an object-performance (b-tagging) sample only and must not
# be used for any rate/normalisation measurement.
#
# The p0/p1 flattening parameters below are the result of the two-pass
# calibration in calibration/ for 13.6 TeV with the CP5 tune (NNPDF3.1 NNLO).
# Re-derive them if the beam energy, PDF or MaxSHat changes.

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
            # 2 -> 1 production of a Z' resonance
            'NewGaugeBoson:ffbar2gmZZprime = on',
            # gmZmode = 3: pure Z' (no gamma*/Z interference or admixture)
            'Zprime:gmZmode = 3',
            '32:m0 = 4000.',
            # 100% Z' -> b bbar
            '32:onMode = off',
            '32:oneChannel = on 1.0 100 -5 5',
            # Open up the full mass range; the hook shapes the spectrum.
            'PhaseSpace:mHatMin = 25.',
        ),
        parameterSets = cms.vstring(
            'pythia8CommonSettings',
            'pythia8CP5Settings',
            'processParameters',
        )
    ),
    # Flat-sqrt(sHat) reweighting hook (GeneratorInterface/Pythia8Interface).
    UserCustomization = cms.VPSet(
        cms.PSet(
            pluginName = cms.string('ZprimeFlatpTHook'),
            # weightpT = exp(p0 + p1*sqrt(sHat)); calibrated in calibration/
            p0 = cms.double(-15.5771),
            p1 = cms.double(1.35874e-03),
            # sqrt(sHat) [GeV] above which the weight is zero (13.6 TeV beam)
            MaxSHat = cms.double(13600.),
            # Optional low-mass decay weight, disabled by default
            DoDecayWeightBelow = cms.double(0.),
            DecayWeightP0 = cms.double(-0.000527117),
            DecayWeightP1 = cms.double(2.64665e-06),
            DecayWeightNorm = cms.double(0.008),
        )
    )
)

ProductionFilterSequence = cms.Sequence(generator)
