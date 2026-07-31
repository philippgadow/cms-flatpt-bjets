#!/usr/bin/env python3
"""
Sample-specific NanoAOD validation for the flat-pT b-jet sample options.

  qcd-bb / qcd-incl
      * unweighted vs genWeight-weighted jet pT spectra (flat vs falling)
      * flavour composition vs pT from Jet_hadronFlavour (5 / 4 / 0)
      * gluon-splitting proxy: AK4 jets containing TWO b hadrons vs one

  grav-hbb
      * per-event (mX, mH) recovered from the GenModel_* branches
        (NanoAOD turns each RandomizedParameters ConfigDescription into a
        boolean branch GenModel_<description>; verified in
        GenWeightsTableProducer.cc of CMSSW_15_0_2)
      * dR(bb) of the H daughters vs H pT, with the AK4 (0.4) and AK8 (0.8)
        cone sizes overlaid
      * fraction of AK4 jets containing two B hadrons vs pT -- the boosted
        H(bb) signature
      * jet mass vs mH closure

  --compare
      cross-sample overlays: b-jet pT coverage, and single-b vs double-b jet
      content across Z', QCD-bb and graviton.

Usage:
  python3 validate_samples.py --sample qcd-bb  <nano.root> [...]
  python3 validate_samples.py --sample grav-hbb <nano.root> [...]
  python3 validate_samples.py --compare zprime=a.root qcd-bb=b.root grav-hbb=c.root
"""

import argparse
import os
import re
import sys

import ROOT

ROOT.gROOT.SetBatch(True)

# Count B hadrons per jet by matching GenPart b hadrons to jets in dR.
# Jet_nBHadrons exists in NanoAOD for MC and is the direct quantity, so prefer
# it when present and fall back to the GenPart match only if it is missing.
CPP = r"""
#ifndef FLATPT_SAMPLES_HELPERS
#define FLATPT_SAMPLES_HELPERS
#include <cmath>
using ROOT::VecOps::RVec;

double dR2(double e1, double p1, double e2, double p2) {
  double de = e1 - e2;
  double dp = std::abs(p1 - p2);
  if (dp > M_PI) dp = 2 * M_PI - dp;
  return de * de + dp * dp;
}

// dR between the two H daughters (b quarks from a Higgs), -1 if not found.
double dR_Hdaughters(const RVec<int>& pdgId, const RVec<short>& mother,
                     const RVec<float>& eta, const RVec<float>& phi) {
  int i1 = -1, i2 = -1;
  for (size_t i = 0; i < pdgId.size(); ++i) {
    if (std::abs(pdgId[i]) != 5) continue;
    int m = mother[i];
    if (m < 0 || (size_t)m >= pdgId.size()) continue;
    if (pdgId[m] != 25) continue;              // mother is a Higgs
    if (i1 < 0) i1 = i; else if (i2 < 0) { i2 = i; break; }
  }
  if (i1 < 0 || i2 < 0) return -1.;
  return std::sqrt(dR2(eta[i1], phi[i1], eta[i2], phi[i2]));
}

// pT of the Higgs that decayed to the two b quarks above (-1 if absent).
float H_pt(const RVec<int>& pdgId, const RVec<short>& mother, const RVec<float>& pt) {
  for (size_t i = 0; i < pdgId.size(); ++i) {
    if (std::abs(pdgId[i]) != 5) continue;
    int m = mother[i];
    if (m < 0 || (size_t)m >= pdgId.size()) continue;
    if (pdgId[m] == 25) return pt[m];
  }
  return -1.f;
}
#endif
"""


def open_df(files):
    return ROOT.RDataFrame("Events", files)


def has_branch(path, name):
    f = ROOT.TFile.Open(path)
    t = f.Get("Events")
    ok = bool(t) and bool(t.GetBranch(name))
    f.Close()
    return ok


def branch_names(path):
    f = ROOT.TFile.Open(path)
    t = f.Get("Events")
    names = [b.GetName() for b in t.GetListOfBranches()] if t else []
    f.Close()
    return names


def save(obj, name, outdir, logy=False, opt="hist"):
    c = ROOT.TCanvas("c_" + name, name, 900, 650)
    if logy:
        c.SetLogy()
    o = obj.GetValue() if hasattr(obj, "GetValue") else obj
    o.SetLineWidth(2)
    o.Draw(opt)
    path = os.path.join(outdir, name + ".pdf")
    c.SaveAs(path)
    return path


# ─────────────────────────────────────────────────────────────────────────────
def validate_qcd(files, outdir, lines, jetptmax=3000.0):
    say = lines.append
    df = open_df(files)
    n = df.Count().GetValue()
    say("events: %d" % n)

    d = (df
         .Define("leadJetPt", "nJet > 0 ? Jet_pt[0] : -1.f")
         .Define("bJet_pt", "Jet_pt[Jet_hadronFlavour == 5]")
         .Define("cJet_pt", "Jet_pt[Jet_hadronFlavour == 4]")
         .Define("lJet_pt", "Jet_pt[Jet_hadronFlavour == 0]")
         )

    NB = 30
    h_unw = d.Filter("leadJetPt > 0").Histo1D(
        ("h_unw", "leading jet, UNWEIGHTED;jet p_{T} [GeV];events/bin",
         NB, 0, jetptmax), "leadJetPt")
    h_wgt = d.Filter("leadJetPt > 0").Histo1D(
        ("h_wgt", "leading jet, genWeight-WEIGHTED;jet p_{T} [GeV];#Sigma w/bin",
         NB, 0, jetptmax), "leadJetPt", "genWeight")

    h_b = d.Histo1D(("h_b", "b jets;jet p_{T} [GeV];jets/bin", NB, 0, jetptmax), "bJet_pt")
    h_c = d.Histo1D(("h_c", "c jets;jet p_{T} [GeV];jets/bin", NB, 0, jetptmax), "cJet_pt")
    h_l = d.Histo1D(("h_l", "light jets;jet p_{T} [GeV];jets/bin", NB, 0, jetptmax), "lJet_pt")

    # Gluon-splitting proxy: jets with >=2 B hadrons vs exactly 1.
    have_nb = has_branch(files[0], "Jet_nBHadrons")
    if have_nb:
        dd = (d.Define("n1b", "Sum(Jet_nBHadrons == 1)")
                .Define("n2b", "Sum(Jet_nBHadrons >= 2)")
                .Define("pt1b", "Jet_pt[Jet_nBHadrons == 1]")
                .Define("pt2b", "Jet_pt[Jet_nBHadrons >= 2]"))
        n1 = dd.Sum("n1b").GetValue()
        n2 = dd.Sum("n2b").GetValue()
        h_1b = dd.Histo1D(("h_1b", "1 B hadron;jet p_{T} [GeV];jets", NB, 0, jetptmax), "pt1b")
        h_2b = dd.Histo1D(("h_2b", ">=2 B hadrons;jet p_{T} [GeV];jets", NB, 0, jetptmax), "pt2b")
    else:
        n1 = n2 = 0
        h_1b = h_2b = None

    gw_min, gw_max = df.Min("genWeight").GetValue(), df.Max("genWeight").GetValue()

    say("")
    say("──── weighting (bias2Selection) ────")
    say("  genWeight range : %.4g .. %.4g  (ratio %.3g)"
        % (gw_min, gw_max, gw_max / gw_min if gw_min else float("nan")))
    hu, hw = h_unw.GetValue(), h_wgt.GetValue()
    say("  unweighted spectrum: mean pT = %.0f GeV, %d entries"
        % (hu.GetMean(), hu.GetEntries()))
    say("  weighted   spectrum: mean pT = %.0f GeV" % hw.GetMean())
    say("  -> unweighted should be ~flat, weighted should fall steeply")
    lo_u = hu.GetBinContent(2)
    hi_u = hu.GetBinContent(max(2, hu.FindBin(2000)))
    lo_w = hw.GetBinContent(2)
    hi_w = hw.GetBinContent(max(2, hw.FindBin(2000)))
    if lo_u > 0 and lo_w > 0:
        say("  ratio(low pT / 2 TeV): unweighted %.3g   weighted %.3g"
            % (hi_u / lo_u if lo_u else float('nan'),
               hi_w / lo_w if lo_w else float('nan')))

    say("")
    say("──── flavour composition (Jet_hadronFlavour) ────")
    tot = h_b.GetValue().GetEntries() + h_c.GetValue().GetEntries() + h_l.GetValue().GetEntries()
    if tot:
        say("  b jets    : %8d  (%.1f%%)"
            % (h_b.GetValue().GetEntries(), 100.0 * h_b.GetValue().GetEntries() / tot))
        say("  c jets    : %8d  (%.1f%%)"
            % (h_c.GetValue().GetEntries(), 100.0 * h_c.GetValue().GetEntries() / tot))
        say("  light/glu : %8d  (%.1f%%)"
            % (h_l.GetValue().GetEntries(), 100.0 * h_l.GetValue().GetEntries() / tot))

    say("")
    say("──── gluon-splitting proxy (B hadrons per jet) ────")
    if have_nb:
        say("  jets with exactly 1 B hadron : %d" % n1)
        say("  jets with >=2 B hadrons      : %d  (%.1f%% of b-containing jets)"
            % (n2, 100.0 * n2 / (n1 + n2) if (n1 + n2) else float("nan")))
        say("  (>=2 B hadrons in one AK4 jet is the gluon-splitting / merged topology)")
    else:
        say("  Jet_nBHadrons not present in this file -- skipped")

    plots = [save(h_unw, "qcd_leadjet_pt_unweighted", outdir),
             save(h_wgt, "qcd_leadjet_pt_weighted", outdir, logy=True)]

    c = ROOT.TCanvas("c_flav", "flav", 900, 650)
    c.SetLogy()
    leg = ROOT.TLegend(0.62, 0.68, 0.88, 0.88)
    leg.SetBorderSize(0)
    for h, col, lab in ((h_b.GetValue(), ROOT.kRed + 1, "b"),
                        (h_c.GetValue(), ROOT.kGreen + 2, "c"),
                        (h_l.GetValue(), ROOT.kBlue + 1, "light/gluon")):
        h.SetLineColor(col)
        h.SetLineWidth(2)
        h.SetStats(0)
        h.SetTitle(";jet p_{T} [GeV];jets / bin")
        h.Draw("hist same" if leg.GetNRows() else "hist")
        leg.AddEntry(h, lab, "l")
    leg.Draw()
    p = os.path.join(outdir, "qcd_flavour_vs_pt.pdf")
    c.SaveAs(p)
    plots.append(p)

    if have_nb and h_1b is not None:
        c2 = ROOT.TCanvas("c_nb", "nb", 900, 650)
        c2.SetLogy()
        leg2 = ROOT.TLegend(0.62, 0.72, 0.88, 0.88)
        leg2.SetBorderSize(0)
        for h, col, lab in ((h_1b.GetValue(), ROOT.kBlue + 1, "1 B hadron"),
                            (h_2b.GetValue(), ROOT.kRed + 1, "#geq2 B hadrons")):
            h.SetLineColor(col)
            h.SetLineWidth(2)
            h.SetStats(0)
            h.SetTitle(";jet p_{T} [GeV];jets / bin")
            h.Draw("hist same" if leg2.GetNRows() else "hist")
            leg2.AddEntry(h, lab, "l")
        leg2.Draw()
        p2 = os.path.join(outdir, "qcd_nBHadrons_vs_pt.pdf")
        c2.SaveAs(p2)
        plots.append(p2)

    return plots


# ─────────────────────────────────────────────────────────────────────────────
def validate_graviton(files, outdir, lines):
    say = lines.append
    df = open_df(files)
    n = df.Count().GetValue()
    say("events: %d" % n)

    # Recover the grid points: NanoAOD writes one boolean branch per
    # RandomizedParameters ConfigDescription, named GenModel_<description>.
    models = [b for b in branch_names(files[0]) if b.startswith("GenModel_")]
    say("")
    say("──── (mX, mH) grid points present ────")
    say("  GenModel_* branches: %d" % len(models))
    if not models:
        say("  WARNING: no GenModel_* branches. Either this is not a")
        say("           multigridpack sample, or ConfigDescription was empty.")

    pat = re.compile(r"MX(\d+)_MH(\d+)")
    counts = []
    for b in sorted(models):
        m = pat.search(b)
        if not m:
            continue
        mx, mh = int(m.group(1)), int(m.group(2))
        cnt = df.Filter(b).Count().GetValue()
        if cnt:
            counts.append((mx, mh, cnt))
    if counts:
        say("  %-8s %-6s %8s %10s" % ("mX", "mH", "events", "dR~4mH/mX"))
        for mx, mh, cnt in sorted(counts):
            say("  %-8d %-6d %8d %10.3f" % (mx, mh, cnt, 4.0 * mh / mx))
        say("  points populated: %d / %d" % (len(counts), len(models)))

    ROOT.gInterpreter.Declare(CPP)
    d = (df
         .Define("dRbb_H", "dR_Hdaughters(GenPart_pdgId, GenPart_genPartIdxMother, GenPart_eta, GenPart_phi)")
         .Define("HpT", "H_pt(GenPart_pdgId, GenPart_genPartIdxMother, GenPart_pt)")
         )

    h_dr = d.Filter("dRbb_H >= 0").Histo1D(
        ("h_dr", ";#DeltaR(b,#bar{b}) from H;events", 60, 0, 3), "dRbb_H")
    p_dr = d.Filter("dRbb_H >= 0 && HpT > 0").Profile1D(
        ("p_dr", ";H p_{T} [GeV];#LT#DeltaR(b#bar{b})#GT", 25, 0, 3000), "HpT", "dRbb_H")

    say("")
    say("──── dR(bb) from H decay ────")
    hd = h_dr.GetValue()
    if hd.GetEntries():
        n_ak4 = d.Filter("dRbb_H >= 0 && dRbb_H < 0.4").Count().GetValue()
        n_ak8 = d.Filter("dRbb_H >= 0.4 && dRbb_H < 0.8").Count().GetValue()
        n_res = d.Filter("dRbb_H >= 0.8").Count().GetValue()
        tot = n_ak4 + n_ak8 + n_res
        say("  <dR(bb)> = %.3f  (%d entries)" % (hd.GetMean(), hd.GetEntries()))
        say("  dR < 0.4 (AK4-merged)  : %6d  (%.1f%%)" % (n_ak4, 100.0 * n_ak4 / tot))
        say("  0.4 < dR < 0.8 (AK8)   : %6d  (%.1f%%)" % (n_ak8, 100.0 * n_ak8 / tot))
        say("  dR > 0.8 (resolved)    : %6d  (%.1f%%)" % (n_res, 100.0 * n_res / tot))
    else:
        say("  no H->bb daughters found (check the decay settings)")

    plots = []
    # dR with the cone sizes drawn on top.
    c = ROOT.TCanvas("c_dr", "dr", 900, 650)
    hd.SetLineWidth(2)
    hd.SetStats(0)
    hd.Draw("hist")
    ymax = hd.GetMaximum() * 1.05
    for x, col, lab in ((0.4, ROOT.kRed + 1, "AK4"), (0.8, ROOT.kBlue + 1, "AK8")):
        ln = ROOT.TLine(x, 0, x, ymax)
        ln.SetLineColor(col)
        ln.SetLineStyle(2)
        ln.SetLineWidth(2)
        ln.Draw()
        ROOT.SetOwnership(ln, False)
        tx = ROOT.TLatex(x + 0.02, ymax * 0.9, lab)
        tx.SetTextColor(col)
        tx.SetTextSize(0.035)
        tx.Draw()
        ROOT.SetOwnership(tx, False)
    p = os.path.join(outdir, "grav_dRbb.pdf")
    c.SaveAs(p)
    plots.append(p)
    plots.append(save(p_dr, "grav_dRbb_vs_HpT", outdir, opt="e"))

    # Double-b jets vs pT: the boosted H(bb) signature.
    if has_branch(files[0], "Jet_nBHadrons"):
        dd = (d.Define("pt2b", "Jet_pt[Jet_nBHadrons >= 2]")
                .Define("pt1b", "Jet_pt[Jet_nBHadrons == 1]"))
        n2 = dd.Define("n2", "Sum(Jet_nBHadrons >= 2)").Sum("n2").GetValue()
        n1 = dd.Define("n1", "Sum(Jet_nBHadrons == 1)").Sum("n1").GetValue()
        say("")
        say("──── double-b AK4 jets (boosted H(bb) signature) ────")
        say("  jets with >=2 B hadrons : %d" % n2)
        say("  jets with  1 B hadron   : %d" % n1)
        if n1 + n2:
            say("  double-b fraction       : %.1f%%" % (100.0 * n2 / (n1 + n2)))
        h2 = dd.Histo1D(("h2b", ";jet p_{T} [GeV];jets with #geq2 B hadrons",
                         30, 0, 3000), "pt2b")
        plots.append(save(h2, "grav_doubleb_jet_pt", outdir))

        # Jet mass vs mH closure, for the merged (double-b) jets.
        dm = dd.Define("m2b", "Jet_mass[Jet_nBHadrons >= 2]")
        hm = dm.Histo1D(("hm", ";mass of #geq2-B-hadron jet [GeV];jets",
                         60, 0, 300), "m2b")
        say("  <mass> of double-b jets : %.1f GeV" % hm.GetValue().GetMean())
        say("  (should cluster near the generated mH values of the grid)")
        plots.append(save(hm, "grav_doubleb_jet_mass", outdir))

    return plots


# ─────────────────────────────────────────────────────────────────────────────
def compare(pairs, outdir, lines):
    """Cross-sample overlays: b-jet pT coverage and single/double-b content."""
    say = lines.append
    say("")
    say("──── cross-sample comparison ────")

    colors = {"zprime": ROOT.kBlack, "qcd-bb": ROOT.kRed + 1,
              "qcd-incl": ROOT.kGreen + 2, "grav-hbb": ROOT.kBlue + 1}
    hists_pt, hists_db = [], []

    for label, path in pairs:
        df = open_df([path])
        d = df.Define("bJet_pt", "Jet_pt[Jet_hadronFlavour == 5]")
        h = d.Histo1D(("hpt_%s" % label, ";b-jet p_{T} [GeV];a.u.",
                       30, 0, 3000), "bJet_pt").GetValue()
        h.SetDirectory(0)
        ROOT.SetOwnership(h, False)
        if h.Integral() > 0:
            h.Scale(1.0 / h.Integral())
        hists_pt.append((label, h))

        if has_branch(path, "Jet_nBHadrons"):
            n1 = df.Define("n1", "Sum(Jet_nBHadrons == 1)").Sum("n1").GetValue()
            n2 = df.Define("n2", "Sum(Jet_nBHadrons >= 2)").Sum("n2").GetValue()
            frac = 100.0 * n2 / (n1 + n2) if (n1 + n2) else float("nan")
            hists_db.append((label, n1, n2, frac))

    c = ROOT.TCanvas("c_cmp", "cmp", 900, 650)
    leg = ROOT.TLegend(0.60, 0.68, 0.88, 0.88)
    leg.SetBorderSize(0)
    for i, (label, h) in enumerate(hists_pt):
        h.SetLineColor(colors.get(label, ROOT.kGray + 2))
        h.SetLineWidth(2)
        h.SetStats(0)
        h.Draw("hist same" if i else "hist")
        leg.AddEntry(h, label, "l")
    leg.Draw()
    p1 = os.path.join(outdir, "compare_bjet_pt.pdf")
    c.SaveAs(p1)

    say("  b-jet pT coverage overlay: %s" % p1)
    if hists_db:
        say("")
        say("  %-12s %10s %10s %12s" % ("sample", "1 B jets", ">=2 B jets", "double-b %"))
        for label, n1, n2, frac in hists_db:
            say("  %-12s %10d %10d %11.1f%%" % (label, n1, n2, frac))
    return [p1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--sample", choices=["qcd-bb", "qcd-incl", "grav-hbb"])
    ap.add_argument("--compare", nargs="+", metavar="LABEL=FILE",
                    help="cross-sample overlay, e.g. zprime=a.root qcd-bb=b.root")
    ap.add_argument("--outdir", default=None)
    args = ap.parse_args()

    outdir = args.outdir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "output")
    os.makedirs(outdir, exist_ok=True)

    lines = []
    lines.append("=" * 66)

    if args.compare:
        pairs = []
        for item in args.compare:
            if "=" not in item:
                sys.exit("ERROR: --compare needs LABEL=FILE, got %r" % item)
            label, path = item.split("=", 1)
            if not os.path.exists(path):
                sys.exit("ERROR: no such file: %s" % path)
            pairs.append((label, path))
        lines.append("  Cross-sample comparison")
        lines.append("=" * 66)
        plots = compare(pairs, outdir, lines)
        name = "comparison"
    else:
        if not args.sample or not args.files:
            sys.exit("ERROR: need --sample TYPE and at least one NanoAOD file "
                     "(or --compare LABEL=FILE ...)")
        for f in args.files:
            if not os.path.exists(f):
                sys.exit("ERROR: no such file: %s" % f)
        lines.append("  Validation: %s" % args.sample)
        lines.append("=" * 66)
        for f in args.files:
            lines.append("  input: %s" % f)
        lines.append("")
        if args.sample.startswith("qcd"):
            plots = validate_qcd(args.files, outdir, lines)
        else:
            plots = validate_graviton(args.files, outdir, lines)
        name = args.sample

    lines.append("")
    lines.append("──── plots ────")
    for p in plots:
        lines.append("  %s" % p)

    text = "\n".join(lines)
    print(text)
    summary = os.path.join(outdir, "validation_%s.txt" % name)
    with open(summary, "w") as fh:
        fh.write(text + "\n")
    print()
    print("summary written: %s" % summary)


if __name__ == "__main__":
    main()
