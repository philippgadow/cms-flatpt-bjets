# cms-flatpt-bjets

Private CMS MC production of **flat b-jet pT samples up to several TeV**, for
b-tagging performance studies at high pT. Analogous to the CMS "flat QCD"
samples, but pure b-jets, following the ATLAS "extended" Z' sample used for flavour tagging.

Four sample options cover complementary regions of b-jet phase space — see
[Sample options](#sample-options). The Z' is the primary, fully validated one;
run any of them with `--sample <type>`.

## Sample options

| Sample | `--sample` | b-jet topology | Flattening mechanism | Weights | Use case |
|---|---|---|---|---|---|
| **Z'→bb̄** (flat √ŝ) | `zprime` | isolated single-b jets, back-to-back, pT ≈ √ŝ/2 | custom `ZprimeFlatpT` UserHook | trial-level σ modified → normalisation unphysical | b-tag efficiency vs pT, clean single-b |
| **QCD bb̄ flat** | `qcd-bb` | ME b's, radiation, realistic environment | `bias2Selection` on pT-hat | **weighted** (`genWeight`) | b-tag in a QCD-like environment |
| **QCD inclusive flat** | `qcd-incl` | all flavours: light/g/c **+ gluon-splitting b's** | `bias2Selection` on pT-hat | **weighted** (`genWeight`) | mistag rates for all flavours |
| **BulkGraviton→HH→bb̄bb̄** | `grav-hbb` | **merged double-b** in one AK4/AK8 jet, ΔR(bb̄) set by mH/mX | discrete (mX, mH) multigridpack scan | per-point `ConfigWeight`; grid is not a physical spectrum | boosted H(bb)/double-b taggers, X→bb̄ |

**Which to use.** For b-tag efficiency vs pT on clean, isolated b jets → `zprime`.
For the same in a realistic QCD environment → `qcd-bb`. For mistag rates, and
for b jets from gluon splitting (which a matrix-element bb̄ sample does not
produce) → `qcd-incl`. For double-b taggers, where both b hadrons share a jet
→ `grav-hbb`.

**Why three different flattening mechanisms.** Not a style choice:
`PhaseSpace:bias2Selection` is documented (and enforced) as working for **2 → 2
processes only** — Pythia aborts otherwise. `ffbar → Z'` is 2 → 1, so it needs
the custom hook. The graviton grid is a discrete scan and is not flattened at
all. Details, including why `bias2Selection` was chosen over the central
`reweightGenEmp`, are in [`fragments/README.md`](fragments/README.md).

> ### ⚠ None of these samples has a physical normalisation
> The Z' modifies the trial cross section; the QCD samples are weighted by
> construction; the graviton grid is a scan, not a spectrum. All are
> **object-performance samples only** — never use them for rates or any
> cross-section measurement.
>
> For the QCD samples specifically: the *unweighted* spectrum is the flat one
> (uniform statistics per pT bin); any *physical* distribution must be filled
> with `genWeight`, which spans ~8 orders of magnitude.

Optional variants, not primary deliverables: `flatpT_Zprime_qq_fragment.py`
(Z' flavour mix) and `BulkGravitonToHHTo4Q_...` (H → bb/cc/light mix, the
merged-jet analogue of inclusive QCD for double-b mistag studies).

## Method (Z')

```
pp → ffbar → Z'(4 TeV) → b b̄        (Pythia8 2 → 1, NewGaugeBoson:ffbar2gmZZprime)
```

A Pythia8 `UserHook` (`ZprimeFlatpTHook`) multiplies the **trial cross section**
by a weight that

1. removes the Breit-Wigner of the Z', opening the whole mass range, and
2. inverts the residual, exponentially falling √ŝ spectrum,

so √ŝ is generated **flat**. The two b quarks recoil back-to-back with
pT ≈ √ŝ/2, giving a flat b-jet pT spectrum over the full range.

This follows the ATLAS flat-pT Z' approach; the hook is a (vibe-coded) port of
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
├── fragments/                   all GEN fragments + mechanism notes
│   ├── flatpT_Zprime_bb_fragment.py        Z' → bb̄  (primary)
│   ├── flatpT_QCD_bb_fragment.py           QCD bb̄ flat
│   ├── flatpT_QCD_incl_fragment.py         QCD inclusive flat
│   └── BulkGravitonToHHTo4B_...cff.py      graviton multigridpack
├── gridpacks/                   (mX, mH) grid, MadGraph cards, gridpack build
│   └── grid.py                  ★ single source of truth for the grid
├── production/
│   ├── env.sh                   ★ single point of configuration + select_sample
│   ├── setup.sh                 create releases, build the hook, install fragments
│   ├── steps/                   one script per cmsDriver step
│   ├── test_local.sh            10 events, GEN-SIM
│   └── run_fullchain.sh         GEN → NanoAOD (--sample, --no-pileup)
├── calibration/                 Z' two-pass flatness fit + QCD bias scan
├── condor/                      HTCondor submission for lxplus
├── crab/                        CRAB submission (PrivateMC + scriptExe)
└── validation/                  NanoAOD-level checks (generic + per-sample)
```

## Quick start

Requires lxplus EL9 (`lxplus9*`) or `cmssw-el9`, and a CMS VOMS proxy for
premixed pileup. Best to run on lxplus or you might have a bad time.

```bash
# 1. Releases + build the UserHook (~15 min the first time)
source production/setup.sh

# 2. Quick test: 10 events, GEN-SIM
./production/test_local.sh

# 3. Full chain to NanoAODv15, no pileup (fast)
./production/run_fullchain.sh --no-pileup                    # Z' (default)
./production/run_fullchain.sh --sample qcd-bb --no-pileup    # any other sample

# 4. Full chain with premixed pileup (needs a proxy)
voms-proxy-init -rfc -voms cms -valid 192:00
./production/run_fullchain.sh

# 5. Validate the NanoAOD
python3 validation/validate_nanoaod.py <path to NanoAOD>
```

## Production chain

Campaign `RunIII2024Summer24`: all definitions are in `production/env.sh`.

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

50k GEN events per pass, CP5 / NNPDF3.1 NNLO, fit over 200–13600 GeV.
"Spread" is how much the spectrum varies across 200 GeV – 7 TeV, i.e. the
quantity that actually matters for a performance sample:

| Pass | `p1` used | fitted slope `c1` [1/GeV] | spread to 7 TeV | in range |
|------|-----------|---------------------------|-----------------|----------|
| A (BW removal only) | 0 | −1.19526e−3 ± 6.2e−6 | ×3390 | 84.0% |
| B | +1.19526e−3 | −1.63486e−4 ± 1.7e−6 | ×3.04 | 97.9% |
| **C (converged)** | **+1.35874e−3** | **−3.16475e−5 ± 1.6e−6** | **×1.24** | **98.9%** |

**Converged**: the spectrum is flat to within a factor 1.24 up to 7 TeV, down
from ×3390 uncalibrated.

The ATLAS 13 TeV value `+1.626e−3` is ~20% steeper than the converged CMS
13.6 TeV result, which is why recalibration is mandatory.

One iteration is needed because Pass A's linear fit is made on a spectrum that
is still strongly falling, so the slope is underestimated. Corrections are
**additive**: `p1(new) = p1(old) − c1(measured)`.

> **Convergence is judged on the spread, not on σ.** At 50k events the
> statistical precision is so high that even a perfectly usable spectrum sits
> many σ from flat (Pass C is 19.7σ yet varies by only ×1.24). A σ-based
> criterion would never converge, so `calibrate.sh` requires a spread below ×2.

**Current fragment values** (`fragments/flatpT_Zprime_bb_fragment.py`):
`p0 = −15.5771`, `p1 = +1.35874e−3`.

To re-derive after changing beam energy, PDF or `MaxSHat`:

```bash
./calibration/calibrate.sh                 # Pass A + B
# put the printed values into the fragment, then close the loop:
REUSE_PASSA=1 ./calibration/calibrate.sh   # reuses Pass A, regenerates Pass B
```

## QCD flatness tuning (`qcd-bb`, `qcd-incl`)

The QCD samples flatten via `PhaseSpace:bias2SelectionPow`. The optimal
exponent is process- and energy-dependent — 4.5 is the central value for
inclusive QCD at 13 TeV, but the bb̄ 2 → 2 subprocess differs and we run at
13.6 TeV — so it is **measured**, not inherited:

```bash
python3 calibration/tune_qcd_bias.py --powers 4 4.5 5 5.5 --nevents 20000
```

Each point is an independent GEN-only job; the script histograms the
*unweighted* leading-jet pT spectrum, reports RMS/mean and the fitted slope for
each exponent, and picks the flattest. Outputs land in `calibration/output_qcd/`
(`bias_scan.pdf`, `bias_scan.json`).

### Scan results (20k events/point, leading GenJet, 100–3000 GeV)

"Spread" is how much the unweighted spectrum varies across the range — the
quantity that matters, as in the Z' calibration.

| `bias2SelectionPow` | RMS/mean | slope [1/GeV] | spread |
|---|---|---|---|
| 4.0 | 2.474 | −5.02e−3 | ×2.1e6 |
| 4.5 (central Run 2 value) | 2.132 | −3.69e−3 | ×4.4e4 |
| 5.0 | 1.656 | −2.67e−3 | ×2.3e3 |
| 5.5 | 1.286 | −1.89e−3 | ×243 |

**The scan is monotonic with no turnover**, so the optimum lies above 5.5 —
the central 4.5 is clearly too low for ME bb̄ at 13.6 TeV. The scan is being
extended (6.0–7.0; Pythia allows up to 10). **The fragments still carry the
placeholder 4.5** and must be updated once the optimum is bracketed.

Note this only affects how uniformly statistics are spread over pT — the
physics is unchanged, since the compensating `genWeight` makes any weighted
distribution correct regardless of the exponent.

## Graviton gridpacks (`grav-hbb`)

This sample needs MadGraph gridpacks — one per (mX, mH) point — before it can
run. See [`gridpacks/README.md`](gridpacks/README.md) for the full workflow and
the CMSSW mechanism details. In short:

```bash
python3 gridpacks/grid.py                    # inspect the grid (50 pilot points)
python3 gridpacks/gen_cards.py               # cards for every point
./gridpacks/make_gridpacks.sh --smoke        # ONE gridpack first
./gridpacks/test_gridpack.sh <tarball> 10    # verify it runs
./gridpacks/make_gridpacks.sh --all --submit # full grid (ask first)
```

Both `condor/submit.sh` and `crab/submit.sh` refuse to submit `--sample
grav-hbb` unless **every** grid point has a gridpack, since a missing point
only fails once it is randomly drawn.

Key mechanism (verified in CMSSW_14_0_19): the gridpack is re-run **per
luminosity block**, so `EVENTS_PER_LUMI` sets the events per grid point, and the
point is recorded in `GenLumiInfoHeader` → NanoAOD `GenModel_*` branches.
`Pythia8GeneratorFilter` is mandatory — the concurrent variant never calls
`generateLHE`.

## Batch production

Two backends run the same per-job payload (`run_fullchain.sh`): lxplus
**HTCondor** (validated default) and **CRAB** (grid-wide capacity). There is no
input dataset at GEN, so CRAB runs in `PrivateMC` mode with a `scriptExe` that
executes the full multi-release chain on the worker node.

### HTCondor (lxplus)

All samples use the same submission, selected with `--sample`:

```bash
# quick test: one short job
./condor/submit.sh --njobs 1 --nevents 20 --no-pileup --flavour espresso

# real submission
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

### CRAB

Same interface, same pre-flight checks, all four samples via `--sample`.
Requires a VOMS proxy and `production/setup.sh` run beforehand — the CRAB
sandbox is packed from the GEN-SIM release area, which is how the
`ZprimeFlatpT` hook and the fragment reach the worker node. The other releases
are created there from cvmfs.

```bash
voms-proxy-init -rfc -voms cms -valid 192:00

# quick test: one short job
./crab/submit.sh --njobs 1 --nevents 20 --no-pileup

# real submission: 100k Z' events
./crab/submit.sh --njobs 200 --nevents 500

# other samples
./crab/submit.sh --njobs 200 --nevents 500 --sample qcd-bb
./crab/submit.sh --njobs 200 --nevents 500 --sample qcd-incl
./crab/submit.sh --njobs 200 --nevents 500 --sample grav-hbb

./crab/status.sh                      # list tasks
./crab/status.sh <TASK>               # crab status of one task
./crab/status.sh <TASK> --merge       # merge NanoAOD output (CERNBox)
crab resubmit -d crab/work/<TASK>/crab_*   # resubmit failed jobs
```

Differences from HTCondor:

- Seeds are `seedbase + CRAB_Id` and CRAB job ids are **1-based**
  (`seedbase+1 .. seedbase+N`, vs `seedbase+0 ..` on condor). As always, pass a
  fresh `--seedbase` when topping up an existing sample.
- Output goes to `Site.storageSite` (default `T3_CH_CERNBOX`) under
  `/store/user/$USER/cms-flatpt-bjets/crab/<dataset>/<tag>/...`, i.e. on
  `/eos/user` next to the condor output; override with `--site` / `--outlfn`.
- CRAB caps the job runtime at 2750 min (~46 h, vs 3 days for `testmatch`), so
  keep premix jobs at O(500) events or fewer.
- For `grav-hbb`, grid worker nodes cannot mount `/eos/user`, so **every job
  first downloads the full gridpack set** (all grid points, typically a few
  GB) over xrootd from `$GRIDPACK_EOS` (override the location with
  `--gridpack-url`). Submission enforces the same all-points-present check as
  condor. With ~50 points this per-job overhead is acceptable; condor remains
  the cheaper backend for this sample.
- A resubmitted CRAB job reuses its `CRAB_Id` and therefore its seed — safe.

#### Publication (DBS phys03)

Pass `--publish` to publish **both MiniAOD and NanoAOD** as private datasets
that anyone in CMS can find in DAS and run over with CRAB:

```bash
./crab/submit.sh --njobs 2000 --nevents 500 --site T2_DE_DESY \
                 --publish --tag NoXsecPerformanceOnly
```

They appear (after the transfers finish) as
`/flatpT_Zprime_bb/<user>-RunIII2024Summer24_<tag>_<timestamp>-<hash>/USER`
in the `prod/phys03` DBS instance; check with `crab status --long` or DAS.
Mechanics and caveats:

- Publishability is decided by the CRAB **client, at submission time**, from
  `crab/PSet.py`: it declares the two outputs as EDM output modules
  (`MINIAODSIMoutput` / `NANOAODSIMoutput`) on scheduled EndPaths, each with a
  `dataset.filterName`. Without that declaration the files are transferred but
  silently never published (the task shows a
  `/FakeDataset/fakefile-FakePublish-…/USER` placeholder forever). The PSet is
  never executed in the job — it only tells the client what to expect, and its
  filenames follow `--sample` via `production/env.sh`.
- **Check this immediately after submitting**, in
  `crab/work/<TASK>/crab_*/crab.log`:

  ```bash
  grep "EDM output files will be collected" crab/work/<TASK>/crab_*/crab.log
  ```

  It must list **both** ROOT files. An empty `[]` (or a "will not be published,
  as they are not EDM files" warning) means the task will never publish — kill
  it and fix the PSet rather than waiting days for DAS.
- At runtime, publication uses the framework job reports of the actual
  Mini/Nano cmsRun steps: `crab_job.sh` has steps 3–4 write their reports
  (`FLATPT_FJR_*`) and merges them into one `FrameworkJobReport.xml`
  (`crab/merge_fjr.py`), rewriting the output PFNs to the stage-out directory
  and dropping `<InputFile>` sections — CRAB stats every PFN in the report, and
  the originals point at deleted chain intermediates.
- CRAB jobs get **unique (lumi, event) ranges** (`FLATPT_FIRSTLUMI/FIRSTEVENT`,
  strides of 10000 lumis and `nevents` events per job), so the published
  datasets contain no duplicate event ids. Condor/local runs are unchanged
  (every job starts at lumi 1, event 1) — condor output is therefore **not**
  publishable as-is.
- The published files live on (and must stay on) the storage site's
  LocalGroupDisk; deleting them breaks the dataset for everyone.
- **Verify publication with the 1-job smoke test first**: the `crab.log` grep
  above at submission time, then two datasets in DAS with the right event
  counts before a large submission.
- These samples have **no physical normalisation** — keep a marker like
  `NoXsecPerformanceOnly` in the tag so nobody mistakes them for a physics
  sample.

## Validation

Generic checks (any sample):

```bash
python3 validation/validate_nanoaod.py <nano.root> [more.root ...]
```

Sample-specific checks:

```bash
python3 validation/validate_samples.py --sample qcd-bb   <nano.root>
python3 validation/validate_samples.py --sample grav-hbb <nano.root>
python3 validation/validate_samples.py --compare zprime=a.root qcd-bb=b.root
```

- **QCD**: unweighted vs `genWeight`-weighted spectra (flat vs falling),
  flavour fractions from `Jet_hadronFlavour`, and a gluon-splitting proxy from
  `GenJet_nBHadrons` (≥2 B hadrons in one AK4 GenJet).
- **Graviton**: (mX, mH) recovered per event from the `GenModel_*` branches,
  ΔR(bb̄) vs H pT with the AK4/AK8 cones overlaid, double-b jet pT, and jet
  mass vs mH closure.
- **`--compare`**: cross-sample b-jet pT coverage and single-b vs double-b
  content.

Checks, with PDF plots and a text summary in `validation/output/`:

- pT spectrum of b-flavoured GenJets and reco Jets (`hadronFlavour == 5`) —
  should be ~flat to ~3 TeV, quantified as RMS/mean over 100–3000 GeV;
- fraction of events with ≥ 2 b jets, and ⟨ΔR(bb)⟩ vs pT (expect ≈ π,
  back-to-back);
- √ŝ / m(Z') flatness — closure of the calibration;
- sanity: event count, `genWeight` present, all required branches non-empty.

## References

- CMS GenProductions: https://github.com/cms-sw/genproductions
- Pythia 8 UserHooks: https://pythia.org/latest-manual/UserHooks.html
