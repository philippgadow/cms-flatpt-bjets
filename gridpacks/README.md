# BulkGraviton → HH gridpacks (option B)

MadGraph gridpacks for the `grav-hbb` sample: a discrete (mX, mH) scan giving
**merged double-b jets** with a tunable opening angle.

```
p p → X(mX) → H(mH) H(mH),   H → b b̄
```

Both b hadrons from one H land in a single AK4 or AK8 jet when

```
ΔR(bb̄) ≈ 2·mH/pT(H) ≈ 4·mH/mX
```

so scanning (mX, mH) scans ΔR from deeply merged to resolved. This is the
topology neither the Z' nor QCD-bb̄ provides.

## Files

| File | Purpose |
|---|---|
| `grid.py` | **the** (mX, mH) grid — imported by card generation *and* the fragment |
| `cards/` | genproductions card templates, beam energy changed to 6800 GeV |
| `gen_cards.py` | expand the templates over the grid |
| `make_gridpacks.sh` | build gridpacks (`--smoke`, `--point`, `--all`) |
| `test_gridpack.sh` | stand-alone smoke test of one tarball |

`grid.py` is the single source of truth: the fragment builds its
`RandomizedParameters` from it, so a fragment can never reference a point that
was never produced.

## The grid

Pilot (default): mX = 600…6000 step 600, mH ∈ {15, 25, 50, 125, 250} → **50
points**. Inspect it with:

```bash
python3 gridpacks/grid.py
```

To densify once the pilot is validated, use `densify()` (mX step 300) or pass
`--dense` to `gen_cards.py`. The Run 2 central sample used mX step 100, split
over three interleaved parts (start 600/700/800, each step 300) purely to keep
each production request manageable — physics-wise it is one grid.

> ⚠️ **The pilot grid is heavily skewed to the merged regime**: 44 of the 50
> points have ΔR < 0.4 (AK4-merged), only 3 land in 0.4 < ΔR < 0.8 (AK8) and 3
> are resolved. That follows from pairing light mH with mX up to 6 TeV.
>
> Merged double-b is the stated goal, so this is not wrong — but taggers are
> usually calibrated across the ΔR ≈ 0.4–0.8 transition, which the pilot barely
> samples. An opt-in preset fills it (AK8 points 3 → 15, pilot untouched):
>
> ```bash
> python3 gridpacks/grid.py --transition        # inspect
> python3 gridpacks/gen_cards.py --transition   # 62 points instead of 50
> ```
>
> The added points come from solving 0.4 < 4·mH/mX < 0.8 per mX, not from
> guesswork. **Off by default** — enabling it costs 12 more gridpacks.

## Workflow

```bash
# 1. cards for every grid point
python3 gridpacks/gen_cards.py

# 2. ONE gridpack first -- never build 50 before validating the setup
./gridpacks/make_gridpacks.sh --smoke

# 3. verify the tarball runs and produces the right masses
./gridpacks/test_gridpack.sh <path to tarball> 10

# 4. only then the full grid (ASK FIRST -- O(30-90) min CPU per point)
./gridpacks/make_gridpacks.sh --all --submit
```

Tarballs are staged to `$GRIDPACK_EOS` (default
`$EOS_OUTDIR/gridpacks`), which the worker nodes can read. cvmfs placement is
only needed for *central* production.

## Build environment (read from genproductions, not assumed)

`gridpack_generation.sh` selects the architecture and release from
`/etc/redhat-release`:

| OS | scram_arch | CMSSW |
|---|---|---|
| EL7 | `slc7_amd64_gcc10` | `CMSSW_12_4_8` |
| EL8 | `el8_amd64_gcc10` | `CMSSW_12_4_8` |
| **EL9** | **`el9_amd64_gcc11`** | **`CMSSW_13_2_9`** |

with **MG5_aMC v2.9.18**. On lxplus9 this runs natively — **no container
needed**. Arguments are `gridpack_generation.sh <name> <carddir> <queue>
<jobstep>`.

This deliberately differs from our GEN-SIM release (`el9_amd64_gcc12` /
`CMSSW_14_0_19`): the gridpack is a self-contained tarball executed through
`run_generic_tarball_cvmfs.sh`, exactly as CMSSW itself runs it. The tarball
name encodes the build arch, which is why the fragment composes paths from
`FLATPT_GRIDPACK_ARCH` / `FLATPT_GRIDPACK_RELEASE`.

## Cards

Copied from genproductions
`bin/MadGraph5_aMCatNLO/cards/production/2017/13TeV/BulkGraviton_hh_granular/example_Cards`,
with **one** physics change: `ebeam1`/`ebeam2` 6500 → **6800 GeV** (13.6 TeV).

Kept as-is: the `RS_bulk_ktilda` model, the narrow width
(`decay 39 1e-3`), and `generate p p > y, ( y > H H )`.

`*_extramodels.dat` (`dibosonResonanceModel.tar.gz`) is required — it is what
fetches the `RS_bulk_ktilda` model. Do not drop it.

## How CMSSW runs the multigridpack (verified in CMSSW_14_0_19)

`gen::BaseHadronizer` (`GeneratorInterface/Core`):

1. `randomizeIndex()` is called from **`beginLuminosityBlockProduce`** — once
   per luminosity block — picking one `RandomizedParameters` PSet weighted by
   `ConfigWeight`.
2. `generateLHE()` then **forks** `run_generic_tarball_cvmfs.sh` with that
   point's `GridpackPath`, `numberEventsInLuminosityBlock`, a derived seed and
   `nThreads`, producing `cmsgrid_final.lhe`.
3. The chosen point is recorded in **`GenLumiInfoHeader`**
   (`setConfigDescription`).

Three consequences that shape the whole design:

- **The grid point is constant within a lumi block**, not per event. So
  `EVENTS_PER_LUMI` (→ `numberEventsInLuminosityBlock`) sets how many events
  come from each point; `env.sh` uses 50 for this sample.
- **`ConfigDescription` is not in `GenEventInfoProduct`.** NanoAOD's
  `GenWeightsTableProducer` turns it into a per-event branch named
  `GenModel_<ConfigDescription>`, which is how `validation/validate_samples.py`
  recovers (mX, mH).
- **`Pythia8GeneratorFilter` is mandatory.** `ConcurrentGeneratorFilter` calls
  `randomizeIndex` but **never** `generateLHE`, so a concurrent filter would
  silently never run the gridpack. This is the real form of the "randomized
  parameters vs multithreading" caveat in this release: the rest of the chain
  stays multithreaded, and MadGraph itself receives `nThreads`.

## Normalisation

The grid is a scan of discrete points, not a physical mass spectrum.
`ConfigWeight` controls only relative sampling. Like every sample in this repo,
there is no physical cross section — object-performance use only.

## Ancestry

Run 2 central equivalents:

```
/BulkGravitonToHHTo4Q_MX-600to6000_MH-15to250_part{1,2,3}_TuneCP5_13TeV-madgraph_pythia8
  /RunIIAutumn18MiniAOD-multigridpack_102X_upgrade2018_realistic_v15-v1/MINIAODSIM
```

(and the RunIIFall17 equivalent). Fragment structure follows
`hqucms/event-producer`.
