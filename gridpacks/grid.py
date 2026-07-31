"""
Single source of truth for the BulkGraviton -> HH (mX, mH) grid.

Imported by BOTH the card generation (gridpacks/gen_cards.sh via gen_cards.py)
and the multigridpack GEN fragment, so the fragment can never reference a point
that was not produced.

Physics: mX sets the H boost, mH sets the H -> bb opening angle.  For a Higgs
of mass mH and pT, dR(bb) ~ 2*mH/pT, and pT ~ mX/2, hence

    dR(bb) ~ 4*mH/mX

so the grid spans merged (dR < 0.4, inside one AK4 jet) through resolved.

PILOT GRID (default): mX 600..6000 step 600, mH {15,25,50,125,250} -> 50 points.
Deliberately small for a first private production.  To densify, see
`densify()` below and the Run 2 central choice documented in gridpacks/README.md
(mX step 100 via three interleaved parts, mH 15..250 in steps of 5-10).
"""

# Pilot grid -------------------------------------------------------------
MX_MIN = 600
MX_MAX = 6000
MX_STEP = 600

MH_VALUES = [15, 25, 50, 125, 250]

MODEL = "BulkGraviton_hh_GF_HH_narrow"


def mx_values(mx_min=MX_MIN, mx_max=MX_MAX, mx_step=MX_STEP):
    return list(range(mx_min, mx_max + 1, mx_step))


def grid(mh_values=None, **kwargs):
    """The (mX, mH) grid as a list of tuples, mX-major."""
    mhs = MH_VALUES if mh_values is None else mh_values
    return [(mx, mh) for mx in mx_values(**kwargs) for mh in mhs]


# Optional preset that populates the AK8 / transition band.  The pilot grid is
# dominated by deeply-merged points (44 of 50 have dR < 0.4) because it pairs
# light mH with mX up to 6 TeV.  Taggers are usually calibrated across the
# dR ~ 0.4-0.8 transition, which the pilot barely samples; these heavier-mH,
# lower-mX points fill it.  NOT enabled by default -- pass --preset transition
# to gen_cards.py, or import TRANSITION_POINTS explicitly.
# Chosen by solving 0.4 < 4*mH/mX < 0.8 (i.e. mH/mX in 0.1..0.2) per mX, rather
# than guessed: a first guess of heavy mH at low mX overshot into "resolved".
TRANSITION_POINTS = [
    (600, 75), (600, 100),
    (1200, 125), (1200, 200),
    (1800, 200), (1800, 350),
    (2400, 250), (2400, 350),
    (3000, 350), (3000, 500),
    (4200, 500), (4200, 750),
    (6000, 750), (6000, 1000),
]


def with_transition(**kwargs):
    """Pilot grid plus the transition-region points, de-duplicated."""
    seen, out = set(), []
    for pt in grid(**kwargs) + TRANSITION_POINTS:
        if pt not in seen:
            seen.add(pt)
            out.append(pt)
    return out


def densify(mx_step=300, mh_values=None):
    """
    A denser grid, for when the pilot production is validated.

    The Run 2 central sample used mx_step=100 split over three interleaved
    parts (start 600/700/800, each step 300) purely to keep each production
    request a manageable size -- physics-wise it is one grid.
    """
    return grid(mh_values=mh_values, mx_step=mx_step)


def point_name(mx, mh, model=MODEL):
    """Directory / gridpack basename for one point. Must match gen_cards.sh."""
    return "%s_MX%s_MH%s" % (model, mx, mh)


def dr_bb_estimate(mx, mh):
    """Rough dR(bb) for the H daughters: 4*mH/mX (see module docstring)."""
    return 4.0 * mh / float(mx)


def regime(mx, mh):
    dr = dr_bb_estimate(mx, mh)
    return "AK4-merged" if dr < 0.4 else "AK8-merged" if dr < 0.8 else "resolved"


if __name__ == "__main__":
    import collections
    import sys

    points = with_transition() if "--transition" in sys.argv else grid()
    print("grid: %d points  (mX %s..%s step %s, mH %s)"
          % (len(points), MX_MIN, MX_MAX, MX_STEP, MH_VALUES))
    print()
    print("%-8s %-6s %-10s %s" % ("mX", "mH", "dR(bb)~", "regime"))
    for mx, mh in points:
        print("%-8d %-6d %-10.3f %s"
              % (mx, mh, dr_bb_estimate(mx, mh), regime(mx, mh)))

    counts = collections.Counter(regime(mx, mh) for mx, mh in points)
    print()
    print("regime breakdown (%d points):" % len(points))
    for name in ("AK4-merged", "AK8-merged", "resolved"):
        print("  %-12s %3d" % (name, counts.get(name, 0)))
    if "--transition" not in sys.argv:
        print()
        print("note: the pilot grid is dominated by deeply-merged points.")
        print("      run with --transition to see the transition-band preset.")
