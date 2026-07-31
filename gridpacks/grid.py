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


if __name__ == "__main__":
    points = grid()
    print("grid: %d points  (mX %s..%s step %s, mH %s)"
          % (len(points), MX_MIN, MX_MAX, MX_STEP, MH_VALUES))
    print()
    print("%-8s %-6s %-10s %s" % ("mX", "mH", "dR(bb)~", "regime"))
    for mx, mh in points:
        dr = dr_bb_estimate(mx, mh)
        regime = ("AK4-merged" if dr < 0.4 else
                  "AK8-merged" if dr < 0.8 else "resolved")
        print("%-8d %-6d %-10.3f %s" % (mx, mh, dr, regime))
