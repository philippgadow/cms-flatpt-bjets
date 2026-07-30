# cms-flatpt-bjets — conventions

Private CMS MC production: a **flat b-jet pT spectrum up to several TeV** for
b-tagging performance studies at high pT.

## Physics in one paragraph

`ffbar → Z'(4 TeV) → bb̄` generated as a Pythia8 2 → 1 process. A UserHook
(`ZprimeFlatpTHook`) reweights the trial cross section to (a) remove the
Breit-Wigner and (b) flatten the √ŝ spectrum. The two b quarks are back-to-back
with pT ≈ √ŝ/2, so a flat √ŝ spectrum gives a flat b-jet pT spectrum. Method
follows the ATLAS flat-pT Z' samples.

**The sample has no physical cross section.** The hook multiplies the trial σ by
an arbitrary weight, so σ and `genWeight` are meaningless. Object-performance
studies only — never rates or normalisation.

## Releases and architecture

All steps use `SCRAM_ARCH=el9_amd64_gcc12`. Campaign = RunIII2024Summer24,
taken from `philippgadow/cms-hza-eventproducer` (`02_signal_production`), which
was validated against McM.

| Step | Release | Global tag |
|------|---------|-----------|
| GEN + SIM | `CMSSW_14_0_19` | `140X_mcRun3_2024_realistic_v26` |
| DIGI + DATAMIX + L1 + HLT:2024v14 | `CMSSW_14_0_21` | `140X_mcRun3_2024_realistic_v26` |
| RECO → AOD | `CMSSW_14_0_21` | `140X_mcRun3_2024_realistic_v26` |
| PAT → MiniAODv6 | `CMSSW_15_0_2` | `150X_mcRun3_2024_realistic_v2` |
| NANO → NanoAODv15 | `CMSSW_15_0_2` | `150X_mcRun3_2024_realistic_v2` |

Era `Run3_2024`, beamspot `DBrealistic`, √s = 13.6 TeV (beam energy 6800 GeV),
tune CP5, PDF NNPDF3.1 NNLO.

**Never invent cmsDriver arguments, global tags or the premix dataset name.**
They are all centralised in `production/env.sh` and were copied from the
reference repo. If something looks inconsistent, stop and ask rather than guess.

## Single points of configuration

- `production/env.sh` — releases, GTs, era, HLT menu, premix dataset, campaign
  names, `EOS_OUTDIR`, and the `setup_release` / `check_proxy` / `require_el9`
  helpers. **Every script sources this.** Change campaign settings here only.
- `fragments/flatpT_Zprime_bb_fragment.py` — the deliverable fragment,
  including the calibrated `p0`/`p1`.

## Containers

lxplus is EL9, so the chain runs natively on `lxplus9*`. On anything older,
enter `cmssw-el9` first. `require_el9` in `env.sh` enforces this. Condor jobs
request the el9 image explicitly via `MY.SingularityImage`.

## Storage

- Large outputs → `$EOS_OUTDIR` (default `/eos/user/p/pgadow/cms-flatpt-bjets`),
  parametrised in `production/env.sh` only.
- CMSSW releases → `releases/` (gitignored). AFS work quota is 100 GB and was
  already 60% full; releases are ~2 GB each.
- Never commit `.root` files. `.gitignore` covers `releases/`, `*.root`,
  `test_*/`, `fullchain_*/`, `*/output/`, `condor/logs/`.
- Intermediate chain files (GEN-SIM/RAW/AOD) are **not** staged out; only
  MiniAOD + NanoAOD go to EOS.

## A VOMS proxy is required for premix

The DIGI step reads the premix pileup library over AAA. `check_proxy` fails
early with a clear message rather than letting a job die 20 minutes in. Use
`--no-pileup` for fast chain validation without a proxy.

```bash
voms-proxy-init -rfc -voms cms -valid 192:00
```

## Test-first workflow (required)

Every stage is tested with a handful of events before scaling up:

1. `./production/test_local.sh` — 10 events, GEN-SIM only. Run after **any**
   change to the hook or the fragment.
2. `./production/run_fullchain.sh --no-pileup` — ~100 events to NanoAOD.
3. `./production/run_fullchain.sh` — same with premix pileup.
4. `./condor/submit.sh --njobs 1 --nevents 20 --no-pileup --flavour espresso`
   — one smoke job on the batch system.
5. Only then a large submission — **ask first.**

Calibration changes must be closed with Pass B (`calibration/calibrate.sh`)
before any production submission.

## Event content note

For calibration runs, `run_genonly.sh` drops everything except `genParticles`
and `GenEventInfoProduct` (`outputCommands`), reducing 270 kB/event to 26 kB.
Full RAWSIM content for 50k GEN events is ~13 GB and will threaten the AFS
quota — keep the slimming.

## Gotcha: the UserHook BuildFile

The hook sources must **not** have `Hook` in the filename and need their own
`<library>` stanza in the package BuildFile, or the plugin registers in both the
HepMC2 and HepMC3 libraries and every job dies with `MultiplePlugins`. See
`userhook/README.md`.

## Random seeds

Seeds must differ per job. `condor/run_job.sh` derives
`seed = seedbase + ProcId`. When adding statistics to an existing sample, pass a
new `--seedbase` or events will be duplicated.
