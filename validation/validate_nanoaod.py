#!/usr/bin/env python3
"""
NanoAOD-level validation of the flat-pT b-jet sample.

Checks:
  1. pT spectrum of b-flavoured GenJets and reco Jets (hadronFlavour == 5)
     -- should be ~flat up to ~3 TeV per jet.
  2. Fraction of events with >= 2 b jets, and dR(bb) vs pT
     (at multi-TeV sqrt(sHat) the bb system is back-to-back, dR -> pi).
  3. sqrt(sHat) / Z' mass flatness -- closure of the Stage 4 calibration.
  4. Sanity: event count, generator weights present, no empty key branches.

Uses RDataFrame. Produces PDF plots and a text summary.

Usage:
  python3 validate_nanoaod.py <nano.root> [more.root ...] [--outdir DIR]
"""

import argparse
import math
import os
import sys

import ROOT

ROOT.gROOT.SetBatch(True)


# Branches we require to exist and be non-empty.
REQUIRED = ["Jet_pt", "Jet_eta", "Jet_hadronFlavour",
            "GenJet_pt", "GenJet_eta", "GenJet_hadronFlavour",
            "GenPart_pdgId", "GenPart_mass", "genWeight"]

# Declared once; used by the dR(bb) column.
CPP_HELPERS = """
#ifndef FLATPT_HELPERS
#define FLATPT_HELPERS
#include <cmath>
// dR between the two highest-pT b-flavoured jets; -1 if fewer than two.
double dRbb(const ROOT::VecOps::RVec<float>& pt,
            const ROOT::VecOps::RVec<float>& eta,
            const ROOT::VecOps::RVec<float>& phi,
            const ROOT::VecOps::RVec<unsigned char>& flav) {
  int i1 = -1, i2 = -1;
  for (size_t i = 0; i < pt.size(); ++i) {
    if (flav[i] != 5) continue;
    if (i1 < 0 || pt[i] > pt[i1]) { i2 = i1; i1 = i; }
    else if (i2 < 0 || pt[i] > pt[i2]) { i2 = i; }
  }
  if (i1 < 0 || i2 < 0) return -1.;
  double deta = eta[i1] - eta[i2];
  double dphi = std::abs(phi[i1] - phi[i2]);
  if (dphi > M_PI) dphi = 2 * M_PI - dphi;
  return std::sqrt(deta * deta + dphi * dphi);
}
// Mass of the last Z' (pdgId 32) in the record; -1 if absent.
float zprimeMass(const ROOT::VecOps::RVec<int>& pdgId,
                 const ROOT::VecOps::RVec<float>& mass) {
  float m = -1.f;
  for (size_t i = 0; i < pdgId.size(); ++i)
    if (std::abs(pdgId[i]) == 32) m = mass[i];
  return m;
}
#endif
"""


def flatness(hist, lo, hi):
    """RMS/mean of bin contents in [lo,hi] -- 0 means perfectly flat."""
    vals = [hist.GetBinContent(b) for b in range(1, hist.GetNbinsX() + 1)
            if lo <= hist.GetBinCenter(b) <= hi and hist.GetBinContent(b) > 0]
    if len(vals) < 2:
        return float("nan"), float("nan"), 0
    mean = sum(vals) / len(vals)
    rms = math.sqrt(sum((v - mean) ** 2 for v in vals) / len(vals))
    return mean, rms / mean if mean else float("nan"), len(vals)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--jetptmax", type=float, default=3500.0)
    args = ap.parse_args()

    outdir = args.outdir or os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
    os.makedirs(outdir, exist_ok=True)

    ROOT.gInterpreter.Declare(CPP_HELPERS)

    lines = []

    def say(msg=""):
        print(msg)
        lines.append(msg)

    say("=" * 66)
    say("  NanoAOD validation: flat-pT Z' -> bb")
    say("=" * 66)
    for f in args.files:
        say("  input: %s" % f)

    # ─── branch presence ────────────────────────────────────────────────────
    tf = ROOT.TFile.Open(args.files[0])
    tree = tf.Get("Events")
    if not tree:
        sys.exit("ERROR: no Events tree in %s" % args.files[0])
    present = {b.GetName() for b in tree.GetListOfBranches()}
    missing = [b for b in REQUIRED if b not in present]
    say()
    say("──── branch check ────")
    if missing:
        say("  MISSING: %s" % ", ".join(missing))
    else:
        say("  all %d required branches present" % len(REQUIRED))
    say("  total branches in Events: %d" % len(present))
    tf.Close()
    if missing:
        sys.exit("ERROR: required branches missing; aborting.")

    df = ROOT.RDataFrame("Events", args.files)
    n_total = df.Count().GetValue()
    say()
    say("──── event count ────")
    say("  events: %d" % n_total)
    if n_total == 0:
        sys.exit("ERROR: zero events.")

    # ─── define columns ─────────────────────────────────────────────────────
    d = (df
         .Define("bGenJet_pt",  "GenJet_pt[GenJet_hadronFlavour == 5]")
         .Define("bJet_pt",     "Jet_pt[Jet_hadronFlavour == 5]")
         .Define("nBGenJet",    "bGenJet_pt.size()")
         .Define("nBJet",       "bJet_pt.size()")
         .Define("dRbb_gen",    "dRbb(GenJet_pt, GenJet_eta, GenJet_phi, GenJet_hadronFlavour)")
         .Define("dRbb_reco",   "dRbb(Jet_pt, Jet_eta, Jet_phi, Jet_hadronFlavour)")
         .Define("mZp",         "zprimeMass(GenPart_pdgId, GenPart_mass)")
         .Define("leadBGenPt",  "bGenJet_pt.size() > 0 ? bGenJet_pt[0] : -1.f")
         )

    NB = 35
    h_gen = d.Histo1D(("h_gen", "b-flavour GenJets;GenJet p_{T} [GeV];jets / bin",
                       NB, 0, args.jetptmax), "bGenJet_pt")
    h_reco = d.Histo1D(("h_reco", "b-flavour reco Jets;Jet p_{T} [GeV];jets / bin",
                        NB, 0, args.jetptmax), "bJet_pt")
    h_mzp = d.Histo1D(("h_mzp", "Z' mass;m(Z') [GeV];events / bin",
                       40, 0, 13600), "mZp")
    h_drg = d.Histo1D(("h_drg", "#DeltaR(bb) GenJets;#DeltaR(b,b);events",
                       50, 0, 5), "dRbb_gen")
    h_nb_gen = d.Histo1D(("h_nb_gen", "n b GenJets;N_{b GenJet};events",
                          8, -0.5, 7.5), "nBGenJet")
    h_nb_reco = d.Histo1D(("h_nb_reco", "n b Jets;N_{b Jet};events",
                           8, -0.5, 7.5), "nBJet")
    p_dr = d.Filter("dRbb_gen > 0").Profile1D(
        ("p_dr", "#DeltaR(bb) vs lead b-jet p_{T};lead b GenJet p_{T} [GeV];#LT#DeltaR(bb)#GT",
         20, 0, args.jetptmax), "leadBGenPt", "dRbb_gen")

    n_ge2_gen = d.Filter("nBGenJet >= 2").Count()
    n_ge2_reco = d.Filter("nBJet >= 2").Count()
    gw_min = d.Min("genWeight")
    gw_max = d.Max("genWeight")

    # ─── flatness ───────────────────────────────────────────────────────────
    say()
    say("──── b-jet pT flatness (target: flat to ~3 TeV) ────")
    for label, hist in (("GenJet", h_gen), ("recoJet", h_reco)):
        mean, rel, nbins = flatness(hist.GetValue(), 100, 3000)
        say("  %-8s 100-3000 GeV: <N/bin> = %8.1f   RMS/mean = %s  (%d bins)"
            % (label, mean,
               "%.2f" % rel if rel == rel else "n/a", nbins))
        say("           entries = %d, mean pT = %.0f GeV"
            % (hist.GetEntries(), hist.GetMean()))

    say()
    say("──── sqrt(sHat) / m(Z') flatness (Stage 4 closure) ────")
    mean, rel, nbins = flatness(h_mzp.GetValue(), 200, 7000)
    say("  200-7000 GeV: <N/bin> = %8.1f   RMS/mean = %s  (%d bins)"
        % (mean, "%.2f" % rel if rel == rel else "n/a", nbins))
    say("  m(Z') mean = %.0f GeV" % h_mzp.GetValue().GetMean())

    say()
    say("──── b-jet multiplicity ────")
    say("  events with >=2 b GenJets : %d / %d  (%.1f%%)"
        % (n_ge2_gen.GetValue(), n_total, 100.0 * n_ge2_gen.GetValue() / n_total))
    say("  events with >=2 b recoJets: %d / %d  (%.1f%%)"
        % (n_ge2_reco.GetValue(), n_total, 100.0 * n_ge2_reco.GetValue() / n_total))
    say("  <N b GenJet>  = %.2f" % h_nb_gen.GetValue().GetMean())
    say("  <N b recoJet> = %.2f" % h_nb_reco.GetValue().GetMean())

    say()
    say("──── dR(bb) (expect ~pi = 3.14, back-to-back) ────")
    say("  <dR(bb)> GenJet = %.2f  (entries %d)"
        % (h_drg.GetValue().GetMean(), h_drg.GetValue().GetEntries()))

    say()
    say("──── generator weights ────")
    say("  genWeight range: %.4g .. %.4g" % (gw_min.GetValue(), gw_max.GetValue()))
    say("  NOTE: the UserHook modifies the trial cross section, so neither the")
    say("        cross section nor genWeight carries a physical normalisation.")

    # ─── plots ──────────────────────────────────────────────────────────────
    def save(hist, name, logy=False, opt="hist e"):
        c = ROOT.TCanvas("c_" + name, name, 800, 600)
        if logy:
            c.SetLogy()
        obj = hist.GetValue() if hasattr(hist, "GetValue") else hist
        obj.SetLineWidth(2)
        obj.SetMinimum(0)
        obj.Draw(opt)
        path = os.path.join(outdir, "%s.pdf" % name)
        c.SaveAs(path)
        return path

    plots = [
        save(h_gen, "bGenJet_pt"),
        save(h_reco, "bRecoJet_pt"),
        save(h_mzp, "zprime_mass"),
        save(h_drg, "dRbb_genjet"),
        save(p_dr, "dRbb_vs_pt", opt="e"),
        save(h_nb_gen, "n_bGenJet"),
    ]
    say()
    say("──── plots ────")
    for p in plots:
        say("  %s" % p)

    summary = os.path.join(outdir, "validation_summary.txt")
    with open(summary, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print()
    print("summary written: %s" % summary)


if __name__ == "__main__":
    main()
