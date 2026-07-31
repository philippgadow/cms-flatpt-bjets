# QCD `bias2SelectionPow` scan — CMS 13.6 TeV, CP5

Archived output of `calibration/tune_qcd_bias.py` for the `qcd-bb` fragment
(matrix-element bb̄). 20k GEN events per point; the metric is the **unweighted**
leading GenJet pT spectrum over 100–3000 GeV.

"Spread" is how much that spectrum varies across the range — the same physical
flatness measure the Z' calibration uses. Smaller is flatter.

| `bias2SelectionPow` | RMS/mean | slope [1/GeV] | spread |
|---|---|---|---|
| 4.0 | 2.474 | −5.02e−3 | ×2.1e6 |
| 4.5 ← central Run 2 value | 2.132 | −3.69e−3 | ×4.4e4 |
| 5.0 | 1.656 | −2.67e−3 | ×2.3e3 |
| 5.5 | 1.286 | −1.89e−3 | ×243 |
| 6.0 | *pending* | | |
| 6.5 | *pending* | | |
| 7.0 | *pending* | | |

## Status: not yet converged

The first four points are **monotonic with no turnover**, so 5.5 was the edge
of the scanned range rather than an optimum. The scan is being extended to
6.0–7.0 (Pythia allows `bias2SelectionPow` up to 10).

**The fragments still carry the placeholder 4.5.** Do not treat any value here
as tuned until the scan brackets a minimum.

## Why the central 4.5 is not right here

4.5 is the central value for **inclusive** QCD at **13 TeV**. This sample is
matrix-element bb̄ at **13.6 TeV**: the bb̄ subprocess has a different pT-hat
dependence, so the exponent that flattens it differs. That is exactly why the
value is measured rather than inherited.

## This does not affect physics correctness

The exponent controls only how uniformly statistics are spread over pT. Pythia
assigns the exact compensating weight `(pTRef/pTHat)^pow`, which reaches
`genWeight`, so **any** weighted distribution is correct for any exponent. A
poorly chosen value costs statistical power at high pT, not accuracy.

## Reproduce

```bash
python3 calibration/tune_qcd_bias.py --powers 4 4.5 5 5.5 6 6.5 7 --nevents 20000
```

`--skip-gen` reuses existing GEN files in `calibration/output_qcd/`.
