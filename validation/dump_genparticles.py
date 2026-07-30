#!/usr/bin/env python3
"""
Quick generator-level dump for a GEN or GEN-SIM file: Z' mass, daughter flavour
and pT.  Used by production/test_local.sh as an immediate sanity check.

Usage: python3 dump_genparticles.py <file.root> [nevents]
"""

import sys

import ROOT

ROOT.gROOT.SetBatch(True)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: dump_genparticles.py <file.root> [nevents]")
    path = sys.argv[1]
    nmax = int(sys.argv[2]) if len(sys.argv) > 2 else 20

    from DataFormats.FWLite import Events, Handle

    events = Events(path)
    handle = Handle("std::vector<reco::GenParticle>")

    masses, flavours, n_two_b = [], {}, 0
    for i, event in enumerate(events):
        if i >= nmax:
            break
        event.getByLabel("genParticles", handle)
        parts = handle.product()
        zprimes = [p for p in parts if abs(p.pdgId()) == 32]
        if not zprimes:
            print("evt %3d: no Z' found!" % i)
            continue
        zp = zprimes[-1]
        masses.append(zp.mass())

        daughters = [p for p in parts
                     if p.mother() and abs(p.mother().pdgId()) == 32
                     and abs(p.pdgId()) != 32]
        for d in daughters:
            flavours[abs(d.pdgId())] = flavours.get(abs(d.pdgId()), 0) + 1
        bs = [d for d in daughters if abs(d.pdgId()) == 5]
        if len(bs) >= 2:
            n_two_b += 1

        desc = "  ".join("pdg=%+d pT=%.0f" % (d.pdgId(), d.pt()) for d in daughters[:2])
        print("evt %3d: m(Z')=%8.1f GeV   %s" % (i, zp.mass(), desc))

    if not masses:
        sys.exit("ERROR: no Z' found in any event")

    print()
    print("events with Z'        : %d" % len(masses))
    print("events with >=2 b     : %d  (%.0f%%)"
          % (n_two_b, 100.0 * n_two_b / len(masses)))
    print("m(Z') range           : %.0f .. %.0f GeV" % (min(masses), max(masses)))
    print("m(Z') mean            : %.0f GeV" % (sum(masses) / len(masses)))
    print("daughter flavours     : %s"
          % ", ".join("pdg %d: %d" % (k, v) for k, v in sorted(flavours.items())))


if __name__ == "__main__":
    main()
