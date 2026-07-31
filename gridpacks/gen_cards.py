#!/usr/bin/env python3
"""
Generate MadGraph cards for every point of the (mX, mH) grid.

Python port of the genproductions `gen_card.sh`, driven by gridpacks/grid.py so
that the cards and the GEN fragment can never disagree about the grid.

Templates in gridpacks/cards/ are the genproductions
`BulkGraviton_hh_granular/example_Cards` with the beam energies changed from
6500 to 6800 GeV (13.6 TeV).

Usage:
  python3 gen_cards.py [--outdir gridpacks/cards_generated] [--dense]
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grid as gridmod  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(HERE, "cards")
TEMPLATE_BASE = "BulkGraviton_hh_GF_HH_narrow_MX_MH"
SUFFIXES = ["_run_card.dat", "_customizecards.dat",
            "_proc_card.dat", "_extramodels.dat"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=os.path.join(HERE, "cards_generated"))
    ap.add_argument("--dense", action="store_true",
                    help="use the denser grid (mX step 300) instead of the pilot")
    args = ap.parse_args()

    points = gridmod.densify() if args.dense else gridmod.grid()

    missing = [s for s in SUFFIXES
               if not os.path.exists(os.path.join(TEMPLATE_DIR, TEMPLATE_BASE + s))]
    if missing:
        sys.exit("ERROR: missing templates in %s: %s" % (TEMPLATE_DIR, missing))

    os.makedirs(args.outdir, exist_ok=True)
    print("generating cards for %d points -> %s" % (len(points), args.outdir))

    for mx, mh in points:
        name = gridmod.point_name(mx, mh)
        pdir = os.path.join(args.outdir, name)
        os.makedirs(pdir, exist_ok=True)
        for suffix in SUFFIXES:
            with open(os.path.join(TEMPLATE_DIR, TEMPLATE_BASE + suffix)) as fh:
                text = fh.read()
            text = text.replace("<MASS_X>", str(mx)).replace("<MASS_H>", str(mh))
            with open(os.path.join(pdir, name + suffix), "w") as fh:
                fh.write(text)

    print("done: %d card sets" % len(points))
    print()
    print("next: ./gridpacks/make_gridpacks.sh --smoke   # one point only")


if __name__ == "__main__":
    main()
