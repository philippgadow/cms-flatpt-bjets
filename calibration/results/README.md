# Calibration results — CMS 13.6 TeV, CP5 / NNPDF3.1 NNLO

Archived output of `calibrate.sh` (50k GEN events per pass, fit over
200–13600 GeV). These are the numbers behind the `p0`/`p1` currently in
`fragments/flatpT_Zprime_bb_fragment.py`.

| Pass | `p1` used | fitted `c1` [1/GeV] | spread to 7 TeV | in range |
|------|-----------|---------------------|-----------------|----------|
| A | 0 (BW removal only) | −1.19526e−3 ± 6.2e−6 | ×3390 | 84.0% |
| B | +1.19526e−3 | −1.63486e−4 ± 1.7e−6 | ×3.04 | 97.9% |
| **C** | **+1.35874e−3** | **−3.16475e−5 ± 1.6e−6** | **×1.24** | **98.9%** |

Converged at pass C: `p0 = −15.5771`, `p1 = +1.35874e−3`.

Each `pass*_shat.pdf` has two panels: the √ŝ spectrum (log y) and
`ln(dN/d√ŝ)` with the fitted straight line.

Regenerate with `./calibration/calibrate.sh`; see the top-level README for the
iteration procedure and why convergence is judged on the spread rather than on
the slope's statistical significance.
