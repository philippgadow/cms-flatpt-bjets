#!/usr/bin/env python3
"""
Flatness calibration for the ZprimeFlatpTHook.

Reads a GEN(-SIM) file, histograms the Z' mass (= sqrt(sHat) for the 2 -> 1
process) from genParticles, fits

    ln(dN/dsqrt(sHat)) = c0 + c1 * sqrt(sHat)

over the requested range and reports the hook parameters that invert it.

Pass A (p1 = 0, BW removal only) measures the residual slope c1, which is
driven by the falling parton luminosity.  Setting

    p1 = -c1

cancels it.  p0 only sets the overall weight scale; it is chosen so the mean
weight over the fit range is ~1, keeping the trial weights O(1).

Usage:
    python3 fit_flatness.py <genfile.root> [--min 200] [--max 13600]
                            [--bins 60] [--plot out.pdf] [--json out.json]
"""

import argparse
import json
import math
import sys

import ROOT

ROOT.gROOT.SetBatch(True)
ROOT.PyConfig.IgnoreCommandLineOptions = True


def collect_masses(path):
    """Return the list of Z' masses (GeV), one per event, via FWLite."""
    from DataFormats.FWLite import Events, Handle

    events = Events(path)
    handle = Handle("std::vector<reco::GenParticle>")
    masses = []
    for event in events:
        event.getByLabel("genParticles", handle)
        # Take the last Z' copy in the record (after any showering bookkeeping).
        zprimes = [p for p in handle.product() if abs(p.pdgId()) == 32]
        if zprimes:
            masses.append(zprimes[-1].mass())
    return masses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("genfile")
    ap.add_argument("--min", type=float, default=200.0,
                    help="lower edge of the fit range in GeV (default 200)")
    ap.add_argument("--max", type=float, default=13600.0,
                    help="upper edge, should match the hook MaxSHat (default 13600)")
    ap.add_argument("--bins", type=int, default=60)
    ap.add_argument("--plot", default=None)
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    masses = collect_masses(args.genfile)
    if not masses:
        sys.exit("ERROR: no Z' (pdgId 32) found in %s" % args.genfile)

    hist = ROOT.TH1D("h_shat", ";#sqrt{#hat{s}} [GeV];events / bin",
                     args.bins, args.min, args.max)
    n_in_range = 0
    for m in masses:
        hist.Fill(m)
        if args.min <= m < args.max:
            n_in_range += 1

    print("events read           : %d" % len(masses))
    print("events in fit range   : %d  (%.1f%%)"
          % (n_in_range, 100.0 * n_in_range / len(masses)))
    if n_in_range < 200:
        print("WARNING: <200 events in range; the fit will be poorly constrained.")

    # Fit ln(dN/dx) with a straight line, using only populated bins so that
    # empty high-mass bins do not bias the slope.
    graph = ROOT.TGraphErrors()
    for b in range(1, hist.GetNbinsX() + 1):
        n = hist.GetBinContent(b)
        if n < 1:
            continue
        x = hist.GetBinCenter(b)
        i = graph.GetN()
        graph.SetPoint(i, x, math.log(n))
        graph.SetPointError(i, 0.0, 1.0 / math.sqrt(n))  # d(ln n) = 1/sqrt(n)

    if graph.GetN() < 3:
        sys.exit("ERROR: only %d populated bins; need more statistics." % graph.GetN())

    line = ROOT.TF1("line", "[0]+[1]*x", args.min, args.max)
    line.SetParameters(math.log(max(1.0, n_in_range / args.bins)), -1e-4)
    fit = graph.Fit(line, "QS")

    c0, c1 = line.GetParameter(0), line.GetParameter(1)
    c1_err = line.GetParError(1)
    chi2, ndf = line.GetChisquare(), line.GetNDF()

    print()
    print("fit  ln(dN/dx) = c0 + c1*x   over [%.0f, %.0f] GeV" % (args.min, args.max))
    print("  c0 = %+.6g" % c0)
    print("  c1 = %+.6g +- %.3g  (1/GeV)" % (c1, c1_err))
    print("  chi2/ndf = %.1f/%d" % (chi2, ndf) if ndf > 0 else "  chi2/ndf = n/a")

    # Invert: the weight must cancel the measured slope.
    p1_new = -c1
    # Choose p0 so that <exp(p0 + p1*x)> ~ 1 over the fit range, i.e.
    # p0 = -ln( mean of exp(p1*x) ).  Computed numerically over the range.
    n_samp = 1000
    acc = 0.0
    for i in range(n_samp):
        x = args.min + (args.max - args.min) * (i + 0.5) / n_samp
        acc += math.exp(p1_new * x)
    p0_new = -math.log(acc / n_samp)

    print()
    print("=" * 62)
    print("recommended hook parameters (put these in the fragment):")
    print("    p0 = cms.double(%.6g)," % p0_new)
    print("    p1 = cms.double(%.6g)," % p1_new)
    print("=" * 62)
    print()
    print("Pass B should then give c1 ~ 0 within its uncertainty.")
    print("Residual slope significance in THIS pass: %.1f sigma"
          % (abs(c1) / c1_err if c1_err > 0 else float("nan")))

    if args.plot:
        canvas = ROOT.TCanvas("c", "c", 900, 700)
        canvas.Divide(1, 2)
        canvas.cd(1)
        ROOT.gPad.SetLogy()
        hist.SetLineWidth(2)
        hist.Draw("hist e")
        canvas.cd(2)
        graph.SetTitle(";#sqrt{#hat{s}} [GeV];ln(dN/dx)")
        graph.SetMarkerStyle(20)
        graph.Draw("ap")
        line.Draw("same")
        canvas.SaveAs(args.plot)
        print("plot written: %s" % args.plot)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({
                "n_events": len(masses),
                "n_in_range": n_in_range,
                "fit_min": args.min,
                "fit_max": args.max,
                "c0": c0, "c1": c1, "c1_err": c1_err,
                "chi2": chi2, "ndf": ndf,
                "p0_recommended": p0_new,
                "p1_recommended": p1_new,
            }, fh, indent=2)
        print("json written: %s" % args.json)


if __name__ == "__main__":
    main()
