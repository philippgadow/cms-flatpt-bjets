# ZprimeFlatpT UserHook (CMSSW port)

Pythia8 `UserHooks` plugin that reweights the trial cross section of the 2 → 1
process `ffbar → Z'` so that the generated √ŝ spectrum — and hence the b-jet
pT ≈ √ŝ/2 — is **flat** up to several TeV.

Ported from the ATLAS implementation (`Pythia8_i/ZprimeFlatpT.cxx`) used for
flat-pT Z'→qq̄ samples.

## Files

| File | Purpose |
|------|---------|
| `ZprimeFlatpT.h` | class declaration + `REGISTER_USERHOOK` |
| `ZprimeFlatpT.cc` | `multiplySigmaBy()` implementation |
| `BuildFile.xml.patched` | reference copy of the patched package BuildFile |

## The weight

`multiplySigmaBy()` returns `weightBW × weightpT × weightDecay`:

1. **`weightBW = (ŝ − m²)² + (ŝ·Γ/m)²`** — Pythia's trial σ for a resonance
   carries the Breit-Wigner factor `1/[(ŝ − m²)² + (ŝΓ/m)²]`, so multiplying by
   the denominator removes the peak at m(Z') and opens the full mass range.
2. **`weightpT = exp(p0 + p1·√ŝ)`** — inverts the residual, exponentially
   falling spectrum (driven by the parton luminosity). Zero above `MaxSHat`.
3. **`weightDecay`** — optional extra weight below `DoDecayWeightBelow`,
   **disabled by default** (`DoDecayWeightBelow = 0`).

Trials that are not 2 → 1 (`nFinal() != 1`) return 0.

> **`p0`/`p1` are collision-energy and PDF dependent.** The ATLAS values
> (−8.95719, 1.62584e−3) were fitted for ATLAS at 13 TeV and are **not** correct
> for CMS at 13.6 TeV with CP5/NNPDF3.1. Re-derive them with
> `calibration/calibrate.sh` — see the top-level README.

## Parameters

All are `cms.double` entries in the hook's `PSet`, so **recalibration never
needs a recompile**:

| Parameter | Default in fragment | Meaning |
|-----------|--------------------|---------|
| `p0` | calibrated | offset of `exp(p0 + p1√ŝ)`; sets the weight scale |
| `p1` | calibrated | slope; must cancel the measured spectrum slope |
| `MaxSHat` | `13600.` | √ŝ [GeV] above which the weight is 0 |
| `DoDecayWeightBelow` | `0.` | apply the low-mass decay weight below this √ŝ; 0 = off |
| `DecayWeightP0` | `-0.000527117` | low-mass weight parameter |
| `DecayWeightP1` | `2.64665e-06` | low-mass weight parameter |
| `DecayWeightNorm` | `0.008` | low-mass weight numerator |

## CMSSW registration mechanism

The hook uses the `CustomHookFactory` pattern from
`GeneratorInterface/Pythia8Interface/interface/CustomHook.h`:

```cpp
typedef edmplugin::PluginFactory<Pythia8::UserHooks*(const edm::ParameterSet&)> CustomHookFactory;
#define REGISTER_USERHOOK(type) DEFINE_EDM_PLUGIN(CustomHookFactory, type, #type)
```

`Pythia8Hadronizer` instantiates every entry of the generator's
`UserCustomization` VPSet by `pluginName` and calls `addUserHooksPtr()`, so no
hadronizer code has to be touched. Activation from the fragment:

```python
generator = cms.EDFilter("Pythia8GeneratorFilter",
    ...
    UserCustomization = cms.VPSet(
        cms.PSet(
            pluginName = cms.string('ZprimeFlatpTHook'),
            p0 = cms.double(...),
            p1 = cms.double(...),
            MaxSHat = cms.double(13600.),
            DoDecayWeightBelow = cms.double(0.),
            DecayWeightP0 = cms.double(-0.000527117),
            DecayWeightP1 = cms.double(2.64665e-06),
            DecayWeightNorm = cms.double(0.008),
        )
    )
)
```

## Build workflow (reproducible)

`production/setup.sh` does all of this automatically. Manually:

```bash
export SCRAM_ARCH=el9_amd64_gcc12
scram p CMSSW CMSSW_14_0_19
cd CMSSW_14_0_19/src
cmsenv

git cms-init --upstream-only
git cms-addpkg GeneratorInterface/Pythia8Interface

cp <repo>/userhook/ZprimeFlatpT.h  GeneratorInterface/Pythia8Interface/plugins/
cp <repo>/userhook/ZprimeFlatpT.cc GeneratorInterface/Pythia8Interface/plugins/
```

Then append a **dedicated library stanza** to
`GeneratorInterface/Pythia8Interface/plugins/BuildFile.xml`:

```xml
<library file="ZprimeFlatpT*.cc" name="GeneratorInterfacePythia8ZprimeFlatpTHook">
</library>
```

```bash
scram b -j 12
```

### Why the dedicated library is required

The package BuildFile builds **two** plugin libraries from a `*Hook*.cc` glob —
`GeneratorInterfacePythia8Filters` (HepMC2) and
`GeneratorInterfacePythia8HepMC3Filters` (HepMC3). A source file whose name
contains `Hook` is compiled into **both**, so the plugin gets registered twice
and any job using it dies at construction time with:

```
An exception of category 'MultiplePlugins' occurred
The plugin 'ZprimeFlatpTHook' is found in multiple files
 '"pluginGeneratorInterfacePythia8Filters.so"'
 '"pluginGeneratorInterfacePythia8HepMC3Filters.so"'
```

Two things avoid this, and both are applied here (the same approach upstream
uses for `SuepDecay` and `JetMatchingEWKFxFx`):

1. the sources are named `ZprimeFlatpT.{h,cc}` — **no `Hook` in the filename**,
   so the generic glob does not pick them up;
2. they get their own `<library>` stanza.

Verify the plugin is registered exactly once:

```bash
grep -c ZprimeFlatpTHook $CMSSW_BASE/lib/$SCRAM_ARCH/.edmplugincache   # -> 1
```

## Validated against

- CMSSW_14_0_19, `el9_amd64_gcc12`, Pythia 8.309
- API confirmed in-release: `SigmaProcess::nFinal()`, `resonanceB()`,
  `PhaseSpace::sHat()`, `UserHooks::multiplySigmaBy(const SigmaProcess*, const PhaseSpace*, bool)`
