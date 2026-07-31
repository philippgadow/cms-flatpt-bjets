# GEN fragments

| Fragment | Sample type | Deliverable? |
|---|---|---|
| `flatpT_Zprime_bb_fragment.py` | `zprime` | ✅ primary (validated) |
| `flatpT_Zprime_qq_fragment.py` | — | optional flavour-mix variant |
| `flatpT_QCD_bb_fragment.py` | `qcd-bb` | ✅ option A1 |
| `flatpT_QCD_incl_fragment.py` | `qcd-incl` | ✅ option A2 |
| `BulkGravitonToHHTo4B_...cff.py` | `grav-hbb` | ✅ option B |
| `BulkGravitonToHHTo4Q_...cff.py` | — | optional 4Q flavour mix |

Select one with `--sample <type>`; the mapping lives in `production/env.sh`
(`select_sample`).

## Flattening mechanisms — why each sample uses a different one

The three samples flatten different variables by different means. This is not
arbitrary: **`bias2Selection` cannot be used for the Z'**.

### 1. Z' — custom `ZprimeFlatpT` UserHook

`ffbar → Z'` is a **2 → 1** process. Pythia's own biasing is documented
(`PhaseSpaceCuts.xml`, verified in 8.309) as working for 2 → 2 only:

> "Possibility to switch on a biased phase space sampling … for 2 → 2
> processes. Can only be used under the specific conditions explained … under
> other conditions the initialization will abort."

Hence the custom hook, which modifies the trial cross section directly
(removing the Breit-Wigner and inverting the residual slope). See
`userhook/README.md`.

### 2. QCD — `PhaseSpace:bias2Selection`

QCD hard scattering is 2 → 2, so Pythia's native biasing applies: a process at
scale `pTHat` is oversampled by `(pTHat/pTRef)^pow` and given the inverse as a
compensating weight. Tunable through a single exponent, and the weight is
exactly recoverable — which is why it is preferred here.

Constraint: `pTHatMin` must be **> 0**, since a `pTHat = 0` event would carry
infinite weight. We use 15 GeV.

### 3. Graviton — no flattening at all

The (mX, mH) grid is a **discrete scan**, not a continuous spectrum. Each grid
point is a separate MadGraph gridpack; `ConfigWeight` sets only how often each
point is drawn.

## `bias2Selection` vs `reweightGenEmp`

The central UL "Flat2018" QCD samples used the CMSSW `reweightGenEmp` hook
rather than `bias2Selection`. **Both exist in CMSSW_14_0_19** — `reweightGenEmp`
is handled in `Pythia8Hadronizer.cc` (it instantiates `PtHatEmpReweightUserHook`
from a `reweightGenEmp` PSet with a `tune` string), alongside
`reweightGenPtHatRap` used by the older 8 TeV flat-pT bb̄ fragment.

We chose `bias2Selection` because:

- it is Pythia-native and documented, rather than a CMSSW-side empirical curve;
- it is tunable through one exponent, which we *measure* rather than inherit
  (`calibration/tune_qcd_bias.py`);
- `reweightGenEmp`'s empirical parameterisation is tied to a specific tune and
  collision energy, and we run CP5 at 13.6 TeV rather than the 13 TeV it was
  derived for.

`reweightGenPtHatRap` (flat in both pT and rapidity) is a third option, used by
the 8 TeV `QCD_BBbar_Pt_15to500_..._FlatPtEta` fragment. Not used here: we want
flat pT, and flattening rapidity too would distort the η distribution that
b-tagging performance depends on.

## Weights — read this before plotting anything

| Sample | `genWeight` | What is flat |
|---|---|---|
| `zprime` | trivial (=1); σ itself is meaningless | √ŝ, hence b-jet pT |
| `qcd-bb`, `qcd-incl` | **non-trivial, spans many orders of magnitude** | *unweighted* jet pT |
| `grav-hbb` | per-point `ConfigWeight` | nothing — a discrete scan |

For the QCD samples, measured over 100 events: 100 distinct weights spanning a
factor 4.4 × 10⁸; the unweighted pT-hat spectrum is roughly uniform per bin
while the weighted one falls over ~8 orders of magnitude.

- **Uniform statistics per pT bin** (efficiency vs pT): use events *unweighted*.
- **Any physical distribution or rate**: fill with `genWeight`.

None of the samples carries a usable absolute normalisation. They are
object-performance samples.
