#include "ZprimeFlatpT.h"

#include <cmath>

ZprimeFlatpTHook::ZprimeFlatpTHook(const edm::ParameterSet& iConfig)
    : p0_(iConfig.getParameter<double>("p0")),
      p1_(iConfig.getParameter<double>("p1")),
      maxSHat_(iConfig.getParameter<double>("MaxSHat")),
      doDecayWeightBelow_(iConfig.getParameter<double>("DoDecayWeightBelow")),
      decayP0_(iConfig.getParameter<double>("DecayWeightP0")),
      decayP1_(iConfig.getParameter<double>("DecayWeightP1")),
      decayNorm_(iConfig.getParameter<double>("DecayWeightNorm")) {}

double ZprimeFlatpTHook::multiplySigmaBy(const Pythia8::SigmaProcess* sigmaProcessPtr,
                                        const Pythia8::PhaseSpace* phaseSpacePtr,
                                        bool /* inEvent */) {
  // Only 2 -> 1 resonance production is reweighted; kill anything else.
  if (sigmaProcessPtr->nFinal() != 1)
    return 0.;

  const int idRes = sigmaProcessPtr->resonanceB();
  const double mRes = particleDataPtr->m0(idRes);
  const double wRes = particleDataPtr->mWidth(idRes);
  const double m2Res = mRes * mRes;
  const double GamMRat = wRes / mRes;

  const double sHat = phaseSpacePtr->sHat();
  const double rH = std::sqrt(sHat);

  // Undo the Breit-Wigner: Pythia's trial sigma carries 1/((sHat-m^2)^2 +
  // (sHat*Gamma/m)^2), so multiplying by the denominator flattens the peak.
  const long double weightBW = Pythia8::pow2(sHat - m2Res) + Pythia8::pow2(sHat * GamMRat);

  // Invert the residual exponentially falling spectrum.
  long double weightpT = std::exp(p0_ + p1_ * rH);
  if (rH >= maxSHat_)
    weightpT = 0.;

  // Optional low-mass decay weight (disabled when DoDecayWeightBelow <= 0).
  double weightDecay = 1.;
  if (rH < doDecayWeightBelow_)
    weightDecay = decayNorm_ / (decayP0_ + decayP1_ * rH);

  return weightBW * weightpT * weightDecay;
}
