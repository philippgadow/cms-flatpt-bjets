#ifndef GeneratorInterface_Pythia8Interface_ZprimeFlatpTHook_h
#define GeneratorInterface_Pythia8Interface_ZprimeFlatpTHook_h

// Pythia8 UserHook producing a flat sqrt(sHat) spectrum for a 2 -> 1 resonance
// (ffbar -> Z') by reweighting the trial cross section.
//
// Ported to CMSSW from the ATLAS implementation
// (Pythia8_i/ZprimeFlatpT.cxx, used for flat-pT Z'->qqbar samples).
//
// The weight has three factors:
//   * weightBW    -- removes the Breit-Wigner shape of the resonance, so the
//                    generated sqrt(sHat) is no longer peaked at m(Z').
//   * weightpT    -- exp(p0 + p1*sqrt(sHat)) inverts the residual falling
//                    (parton-luminosity driven) spectrum.  p0/p1 MUST be
//                    re-derived per collision energy / PDF (see calibration/).
//   * weightDecay -- optional extra weight below a mass threshold, off by
//                    default (DoDecayWeightBelow = 0).
//
// Because the trial cross section is modified, the resulting sample carries NO
// physical cross-section normalisation.  It is an object-performance sample.

#include "FWCore/ParameterSet/interface/ParameterSet.h"
#include "FWCore/PluginManager/interface/PluginFactory.h"
#include "Pythia8/Pythia.h"
#include "Pythia8/PhaseSpace.h"
#include "GeneratorInterface/Pythia8Interface/interface/CustomHook.h"

class ZprimeFlatpTHook : public Pythia8::UserHooks {
public:
  explicit ZprimeFlatpTHook(const edm::ParameterSet& iConfig);
  ~ZprimeFlatpTHook() override {}

  bool canModifySigma() override { return true; }

  double multiplySigmaBy(const Pythia8::SigmaProcess* sigmaProcessPtr,
                         const Pythia8::PhaseSpace* phaseSpacePtr,
                         bool inEvent) override;

private:
  // exp(p0 + p1*sqrt(sHat)) spectrum-flattening parameters
  const double p0_;
  const double p1_;
  // sqrt(sHat) [GeV] above which the weight is set to zero
  const double maxSHat_;
  // apply the low-mass decay weight below this sqrt(sHat) [GeV]; 0 disables it
  const double doDecayWeightBelow_;
  // parameters of the optional low-mass decay weight
  const double decayP0_;
  const double decayP1_;
  const double decayNorm_;
};

REGISTER_USERHOOK(ZprimeFlatpTHook);
#endif
