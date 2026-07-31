#!/usr/bin/env python3
"""
Tune PhaseSpace:bias2SelectionPow for the flat-pT QCD samples.

The optimal exponent is not universal: 4.5 is the central value for inclusive
QCD at 13 TeV, but the bb-bar 2 -> 2 subprocess has a different pT-hat
dependence, and we run at 13.6 TeV.  This scans a few values, histograms the
UNWEIGHTED leading-jet pT spectrum for each, and reports which is flattest.

"Flattest" is measured as the RMS/mean of the bin contents over the tuning
range, plus the fitted slope of ln(dN/dpT) -- the same flatness language the Z'
calibration uses (see fit_flatness.py).

Usage:
  python3 tune_qcd_bias.py --fragment <path> --powers 4 4.5 5 5.5 \\
                           [--nevents 20000] [--outdir DIR] [--jetpt-max 3000]

Each point is an independent GEN-only job, so this is embarrassingly parallel;
run with --submit to send the scan to condor instead of running locally.
"""

import argparse
import json
import math
import os
import subprocess
import sys

import ROOT

ROOT.gROOT.SetBatch(True)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_gen(fragment, power, nevents, seed, outfile, nthreads=4):
    """Run a GEN-only job with bias2SelectionPow set to `power`."""
    env = dict(os.environ)
    env["QCD_BIAS_POW"] = str(power)
    cmd = [os.path.join(REPO, "calibration", "run_genonly_qcd.sh"),
           fragment, str(nevents), str(seed), str(power), outfile]
    print("  running: pow=%s nevents=%s -> %s" % (power, nevents, outfile))
    res = subprocess.run(cmd, env=env)
    if res.returncode != 0:
        sys.exit("ERROR: GEN job failed for pow=%s" % power)


def leading_jet_pt(path, unweighted=True):
    """Leading GenJet pT per event, and the per-event weight."""
    from DataFormats.FWLite import Events, Handle

    events = Events(path)
    h_jets = Handle("std::vector<reco::GenJet>")
    h_info = Handle("GenEventInfoProduct")

    pts, weights = [], []
    for event in events:
        event.getByLabel("ak4GenJets", h_jets)
        event.getByLabel("generator", h_info)
        jets = h_jets.product()
        if not jets.size():
            continue
        # GenJets are pT-ordered; take the leading one.
        pts.append(jets[0].pt())
        weights.append(h_info.product().weight())
    return pts, weights


def flatness_metrics(pts, lo, hi, nbins, name="h"):
    """RMS/mean of bin contents and the fitted slope of ln(dN/dpT)."""
    hist = ROOT.TH1D(name, ";leading GenJet p_{T} [GeV];jets/bin", nbins, lo, hi)
    # Detach from the current TDirectory so ROOT does not delete it when the
    # next file is opened -- otherwise the overlay plot gets null histograms.
    hist.SetDirectory(0)
    ROOT.SetOwnership(hist, False)
    for p in pts:
        hist.Fill(p)

    vals = [hist.GetBinContent(b) for b in range(1, nbins + 1)
            if hist.GetBinContent(b) > 0]
    if len(vals) < 3:
        return None
    mean = sum(vals) / len(vals)
    rms = math.sqrt(sum((v - mean) ** 2 for v in vals) / len(vals))

    graph = ROOT.TGraphErrors()
    for b in range(1, nbins + 1):
        n = hist.GetBinContent(b)
        if n < 1:
            continue
        i = graph.GetN()
        graph.SetPoint(i, hist.GetBinCenter(b), math.log(n))
        graph.SetPointError(i, 0.0, 1.0 / math.sqrt(n))
    line = ROOT.TF1("line", "[0]+[1]*x", lo, hi)
    graph.Fit(line, "QN")

    return {
        "rms_over_mean": rms / mean if mean else float("nan"),
        "slope": line.GetParameter(1),
        "slope_err": line.GetParError(1),
        "n_bins_filled": len(vals),
        "mean_per_bin": mean,
        "n_jets": len(pts),
        # How much the spectrum varies across the range -- the same physical
        # flatness measure used by the Z' calibration.
        "spread": math.exp(abs(line.GetParameter(1)) * (hi - lo)),
        "hist": hist,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fragment", default=os.path.join(
        REPO, "fragments", "flatpT_QCD_bb_fragment.py"))
    ap.add_argument("--powers", nargs="+", type=float,
                    default=[4.0, 4.5, 5.0, 5.5])
    ap.add_argument("--nevents", type=int, default=20000)
    ap.add_argument("--outdir", default=os.path.join(REPO, "calibration", "output_qcd"))
    ap.add_argument("--jetpt-min", type=float, default=100.0)
    ap.add_argument("--jetpt-max", type=float, default=3000.0)
    ap.add_argument("--bins", type=int, default=30)
    ap.add_argument("--skip-gen", action="store_true",
                    help="reuse existing GEN files in --outdir")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    results = {}

    for i, power in enumerate(args.powers):
        tag = "pow%s" % str(power).replace(".", "p")
        genfile = os.path.join(args.outdir, "qcd_%s_GEN.root" % tag)
        if not (args.skip_gen and os.path.exists(genfile)):
            run_gen(args.fragment, power, args.nevents, 900000 + i * 1000, genfile)

        pts, weights = leading_jet_pt(genfile)
        m = flatness_metrics(pts, args.jetpt_min, args.jetpt_max, args.bins,
                             name="h_%s" % tag)
        if m is None:
            print("  pow=%s: too few filled bins, skipping" % power)
            continue
        results[power] = m
        print("  pow=%-4s  RMS/mean=%.3f  slope=%+.3e  spread=x%.3g  jets=%d"
              % (power, m["rms_over_mean"], m["slope"], m["spread"], m["n_jets"]))

    if not results:
        sys.exit("ERROR: no usable scan points")

    # Best = flattest spectrum, i.e. smallest spread across the range.
    best = min(results, key=lambda p: results[p]["spread"])

    print()
    print("=" * 66)
    print("  bias2SelectionPow SCAN  (%.0f - %.0f GeV, leading GenJet, UNWEIGHTED)"
          % (args.jetpt_min, args.jetpt_max))
    print("=" * 66)
    print("  %-6s %10s %14s %10s" % ("pow", "RMS/mean", "slope [1/GeV]", "spread"))
    for p in sorted(results):
        m = results[p]
        mark = "  <-- flattest" if p == best else ""
        print("  %-6s %10.3f %+14.3e %10.3g%s"
              % (p, m["rms_over_mean"], m["slope"], m["spread"], mark))
    print()
    print("  => use  'PhaseSpace:bias2SelectionPow = %s'" % best)
    print("=" * 66)

    # Overlay plot of all scanned spectra.
    canvas = ROOT.TCanvas("c", "c", 900, 650)
    canvas.SetLogy()
    colors = [ROOT.kBlack, ROOT.kRed + 1, ROOT.kBlue + 1, ROOT.kGreen + 2,
              ROOT.kMagenta + 1, ROOT.kOrange + 7]
    legend = ROOT.TLegend(0.62, 0.68, 0.88, 0.88)
    legend.SetBorderSize(0)
    for i, p in enumerate(sorted(results)):
        h = results[p]["hist"]
        h.SetLineColor(colors[i % len(colors)])
        h.SetLineWidth(2)
        h.SetStats(0)
        h.Draw("hist same" if i else "hist")
        legend.AddEntry(h, "pow = %s" % p, "l")
    legend.Draw()
    plot = os.path.join(args.outdir, "bias_scan.pdf")
    canvas.SaveAs(plot)
    print("  plot: %s" % plot)

    summary = {str(p): {k: v for k, v in results[p].items() if k != "hist"}
               for p in results}
    summary["best_power"] = best
    summary["range"] = [args.jetpt_min, args.jetpt_max]
    with open(os.path.join(args.outdir, "bias_scan.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    print("  json: %s" % os.path.join(args.outdir, "bias_scan.json"))


if __name__ == "__main__":
    main()
