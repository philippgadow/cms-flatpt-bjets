# cms-flatpt-bjets

Private CMS MC production of a **flat b-jet pT sample up to several TeV**, for
b-tagging performance studies at high pT. Analogous to the CMS "flat QCD"
samples, but pure b-jets.

## Method

```
pp → ffbar → Z'(4 TeV) → b b̄        (Pythia8 2 → 1, NewGaugeBoson:ffbar2gmZZprime)
```

A Pythia8 `UserHook` (`ZprimeFlatpTHook`) multiplies the **trial cross section**
by a weight that

1. removes the Breit-Wigner of the Z', opening the whole mass range, and
2. inverts the residual, exponentially falling √ŝ spectrum,

so √ŝ is generated **flat**. The two b quarks recoil back-to-back with
pT ≈ √ŝ/2, giving a flat b-jet pT spectrum over the full range.

This follows the ATLAS flat-pT Z' approach; the hook is a port of
`Pythia8_i/ZprimeFlatpT.cxx` to the CMSSW `CustomHookFactory` pattern.

> ### ⚠ The sample has no physical normalisation
> The hook modifies the trial cross section, so the cross section reported by
> Pythia8 and the per-event `genWeight` are **unphysical** (the smoke test
> reports σ ≈ 10⁹ pb). This is an **object-performance sample only** — never use
> it for rates, normalisation or any cross-section measurement.

## Layout

```
cms-flatpt-bjets/
├── CLAUDE.md                    conventions: releases, containers, EOS, test-first workflow
├── userhook/                    ZprimeFlatpT CMSSW port + build instructions
├── fragments/
│   ├── flatpT_Zprime_bb_fragment.py   ← the deliverable (100% Z' → bb̄)
│   └── flatpT_Zprime_qq_fragment.py   optional bb/cc/ss/uu/dd/gg mix
├── production/
│   ├── env.sh                   ★ single point of configuration
│   ├── setup.sh                 create releases + build the hook
│   ├── steps/                   one script per cmsDriver step
│   ├── test_local.sh            10 events, GEN-SIM
│   └── run_fullchain.sh         ~100 events GEN → NanoAOD (--no-pileup option)
├── calibration/                 two-pass flatness fit
├── condor/                      HTCondor submission for lxplus
└── validation/                  NanoAOD-level checks
```

## Quick start

Requires lxplus EL9 (`lxplus9*`) or `cmssw-el9`, and a CMS VOMS proxy for
premixed pileup.

```bash
# 1. Releases + build the UserHook (~15 min the first time)
source production/setup.sh

# 2. Smoke test: 10 events, GEN-SIM
./production/test_local.sh

# 3. Full chain to NanoAODv15, no pileup (fast)
./production/run_fullchain.sh --no-pileup

# 4. Full chain with premixed pileup (needs a proxy)
voms-proxy-init -rfc -voms cms -valid 192:00
./production/run_fullchain.sh

# 5. Validate the NanoAOD
python3 validation/validate_nanoaod.py <path to NanoAOD>
```

## Production chain

Campaign RunIII2024Summer24, values taken from
[`philippgadow/cms-hza-eventproducer`](https://github.com/philippgadow/cms-hza-eventproducer)
`02_signal_production` (validated against McM). All in `production/env.sh`.

| Step | Script | Release | Global tag |
|------|--------|---------|-----------|
| 0 | `step0_gensim.sh` | `CMSSW_14_0_19` | `140X_mcRun3_2024_realistic_v26` |
| 1 | `step1_digihlt.sh` | `CMSSW_14_0_21` | `140X_mcRun3_2024_realistic_v26` |
| 2 | `step2_reco.sh` | `CMSSW_14_0_21` | `140X_mcRun3_2024_realistic_v26` |
| 3 | `step3_miniaod.sh` | `CMSSW_15_0_2` | `150X_mcRun3_2024_realistic_v2` |
| 4 | `step4_nanoaod.sh` | `CMSSW_15_0_2` | `150X_mcRun3_2024_realistic_v2` |

Era `Run3_2024`, HLT menu `2024v14`, beamspot `DBrealistic`, beam energy
6800 GeV. There is **no LHE step** — the process is pure Pythia8.

Each step script takes `<infile> <nevents> [seed] <outfile>` and can be run
standalone; `run_fullchain.sh` chains them and supports `--skip-to N`.

## Flatness calibration

`p0`/`p1` of `weightpT = exp(p0 + p1·√ŝ)` depend on beam energy and PDF. **The
ATLAS values are not valid for CMS** and must be re-derived:

```bash
./calibration/calibrate.sh [nevents] [fitmin] [fitmax]   # default 50000 200 13600
```

- **Pass A** — GEN-only with `p0 = p1 = 0` (BW removal only); fit
  `ln(dN/d√ŝ) = c0 + c1·√ŝ`.
- **Fit** — set `p1 = −c1`; `p0` is chosen so the mean weight over the range is
  ≈ 1, keeping trial weights O(1).
- **Pass B** — regenerate with those values and confirm `c1 ≈ 0` (closure).

The script prints the recommended parameters and a converged/iterate verdict;
it deliberately does **not** edit the fragment, so the change stays reviewable.
Outputs (`passA/B_shat.pdf`, `*_fit.json`) land in `calibration/output/`.

GEN-only runs drop everything but `genParticles`, so 50k events cost ~1.3 GB
instead of ~13 GB.

### Measured for CMS at 13.6 TeV

With BW removal only, the CMS spectrum falls with `c1 ≈ −1.25e−3 /GeV`
(NNPDF3.1 NNLO, CP5), giving `p1 ≈ +1.25e−3` — measurably different from the
ATLAS 13 TeV value of `+1.626e−3`, which is why recalibration is mandatory.
See `calibration/output/` for the current fit.

## Batch production

lxplus HTCondor (not CRAB — there is no input dataset at GEN):

```bash
# smoke test: one short job
./condor/submit.sh --njobs 1 --nevents 20 --no-pileup --flavour espresso

# real submission (ask before large ones)
./condor/submit.sh --njobs 200 --nevents 500

./condor/status.sh                    # list batches
./condor/status.sh <TAG>              # status of one batch
./condor/status.sh <TAG> --failed     # tails of failed job logs
./condor/status.sh <TAG> --merge      # merge NanoAOD output
```

Seeds are `seedbase + ProcId`, so every job differs; pass a fresh `--seedbase`
when topping up an existing sample. Default flavour `testmatch` (3 days) suits
O(500–1000) events per job. MiniAOD + NanoAOD are staged to
`$EOS_OUTDIR/<TAG>/`; intermediates are deleted.

## Validation

```bash
python3 validation/validate_nanoaod.py <nano.root> [more.root ...]
```

Checks, with PDF plots and a text summary in `validation/output/`:

- pT spectrum of b-flavoured GenJets and reco Jets (`hadronFlavour == 5`) —
  should be ~flat to ~3 TeV, quantified as RMS/mean over 100–3000 GeV;
- fraction of events with ≥ 2 b jets, and ⟨ΔR(bb)⟩ vs pT (expect ≈ π,
  back-to-back);
- √ŝ / m(Z') flatness — closure of the calibration;
- sanity: event count, `genWeight` present, all required branches non-empty.

## References

- Reference chain: [philippgadow/cms-hza-eventproducer](https://github.com/philippgadow/cms-hza-eventproducer)
- CMS GenProductions: https://github.com/cms-sw/genproductions
- Pythia 8 UserHooks: https://pythia.org/latest-manual/UserHooks.html
