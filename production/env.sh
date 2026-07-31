#!/bin/bash
#
# Central configuration for the cms-flatpt-bjets production chain.
# Every script sources this; change campaign settings HERE ONLY.
#
# Campaign values are taken from the RunIII2024Summer24 chain of
# philippgadow/cms-hza-eventproducer (02_signal_production), which was
# validated against McM for this campaign.

# ─── Output location (single point of parametrisation) ───────────────────────
# Large outputs (MiniAOD/NanoAOD) go here.
export EOS_OUTDIR="${EOS_OUTDIR:-/eos/user/p/pgadow/cms-flatpt-bjets}"

# ─── Architecture and releases ──────────────────────────────────────────────
export ARCH="el9_amd64_gcc12"
export CMSSW_GS="CMSSW_14_0_19"    # GEN + SIM
export CMSSW_DR="CMSSW_14_0_21"    # DIGI + DATAMIX + L1 + HLT, RECO
export CMSSW_MINI="CMSSW_15_0_2"   # MiniAODv6 + NanoAODv15

# ─── Conditions ─────────────────────────────────────────────────────────────
export GT_GS="140X_mcRun3_2024_realistic_v26"
export GT_DR="140X_mcRun3_2024_realistic_v26"
export GT_MINI="150X_mcRun3_2024_realistic_v2"

export ERA="Run3_2024"
export HLT_MENU="2024v14"
export BEAMSPOT="DBrealistic"
export PREMIX_DATASET="/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX"

# ─── Campaign naming ────────────────────────────────────────────────────────
export CAMPAIGN_GS="RunIII2024Summer24GS"
export CAMPAIGN_DR="RunIII2024Summer24DRPremix"
export CAMPAIGN_RECO="RunIII2024Summer24RECO"
export CAMPAIGN_MINI="RunIII2024Summer24MiniAODv6"
export CAMPAIGN_NANO="RunIII2024Summer24NanoAODv15"

# ─── Sample types ───────────────────────────────────────────────────────────
# select_sample <type> sets SAMPLE (file/dir naming) and FRAGMENT (GEN input).
# Types:
#   zprime     flat-sqrt(sHat) Z'->bb, custom ZprimeFlatpT hook   [default]
#   qcd-bb     flat-pT QCD, matrix-element bb-bar
#   qcd-incl   flat-pT inclusive QCD, all flavours (mistag)
#   grav-hbb   BulkGraviton->HH->bbbb multigridpack (merged double-b)
#
# The Z' path is the validated default and is unchanged by the additions.
select_sample() {
    local TYPE="${1:-zprime}"
    case "$TYPE" in
        zprime)
            export SAMPLE="flatpT_Zprime_bb"
            export FRAGMENT="$REPO_DIR/fragments/flatpT_Zprime_bb_fragment.py"
            ;;
        qcd-bb)
            export SAMPLE="flatpT_QCD_bb"
            export FRAGMENT="$REPO_DIR/fragments/flatpT_QCD_bb_fragment.py"
            ;;
        qcd-incl)
            export SAMPLE="flatpT_QCD_incl"
            export FRAGMENT="$REPO_DIR/fragments/flatpT_QCD_incl_fragment.py"
            ;;
        grav-hbb)
            export SAMPLE="BulkGravitonToHHTo4B"
            export FRAGMENT="$REPO_DIR/fragments/BulkGravitonToHHTo4B_MX-flat_MH-flat_TuneCP5_13p6TeV-madgraph_pythia8_cff.py"
            # The gridpack is re-run per luminosity block, so this also sets how
            # many events come from each (mX, mH) point. Smaller than the
            # default 100 so a job of a given size covers more grid points.
            # An explicit EVENTS_PER_LUMI in the environment still wins.
            export EVENTS_PER_LUMI="${EVENTS_PER_LUMI_OVERRIDE:-50}"
            # Gridpacks must be readable from the worker node.
            export FLATPT_GRIDPACK_DIR="${GRIDPACK_EOS:-$EOS_OUTDIR/gridpacks}"
            ;;
        *)
            echo "ERROR: unknown sample type '$TYPE'"
            echo "       valid: zprime | qcd-bb | qcd-incl | grav-hbb"
            return 1
            ;;
    esac
    export SAMPLE_TYPE="$TYPE"
}

# Default sample type; SAMPLE/FRAGMENT are resolved below, once REPO_DIR exists.
export SAMPLE_TYPE="${SAMPLE_TYPE:-zprime}"

# Events per luminosity block. Only the graviton sample cares (it drives how
# many events are drawn per grid point); the others use the CMS default of 100.
export EVENTS_PER_LUMI="${EVENTS_PER_LUMI:-100}"

# Where gridpack tarballs live (option B).
export GRIDPACK_EOS="${GRIDPACK_EOS:-$EOS_OUTDIR/gridpacks}"

# ─── Resources ──────────────────────────────────────────────────────────────
export NTHREADS="${NTHREADS:-4}"

# ─── Release areas ──────────────────────────────────────────────────────────
# All releases live under releases/ next to this repo.
_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR="$(cd "$_ENV_DIR/.." && pwd)"
export RELEASE_DIR="${RELEASE_DIR:-$REPO_DIR/releases}"
# Anchor for fragments that import repo modules (e.g. gridpacks/grid.py): the
# installed copy of a fragment lives inside CMSSW, where a __file__-relative
# path no longer finds the repo.
export FLATPT_REPO_DIR="$REPO_DIR"

# Resolve the sample now that REPO_DIR is known.  Scripts source env.sh AFTER
# inheriting an already-resolved sample from their caller, so do NOT clobber a
# value that is already set -- otherwise every sub-script silently falls back
# to the Z' fragment (this bug installed QCD content under the Z' name).
if [ -z "${SAMPLE:-}" ]; then
    select_sample "$SAMPLE_TYPE" > /dev/null
fi

# ─── Helpers ────────────────────────────────────────────────────────────────

# setup_release <CMSSW_X_Y_Z> -- create the release if needed and enter its env.
setup_release() {
    local RELEASE="$1"
    source /cvmfs/cms.cern.ch/cmsset_default.sh
    export SCRAM_ARCH="$ARCH"

    if [ ! -d "$RELEASE_DIR/$RELEASE/src" ]; then
        echo "  creating $RELEASE in $RELEASE_DIR ..."
        mkdir -p "$RELEASE_DIR"
        pushd "$RELEASE_DIR" > /dev/null
        scram p CMSSW "$RELEASE"
        popd > /dev/null
    fi

    pushd "$RELEASE_DIR/$RELEASE/src" > /dev/null
    eval $(scram runtime -sh)
    popd > /dev/null
}

# check_proxy -- premix input needs a valid VOMS proxy; fail early otherwise.
check_proxy() {
    if ! voms-proxy-info -exists -valid 0:10 > /dev/null 2>&1; then
        echo "ERROR: no valid VOMS proxy (need >10 min remaining)."
        echo "       Premixed pileup reads from DBS/AAA and will fail without one."
        echo "       Run:  voms-proxy-init -rfc -voms cms -valid 192:00"
        return 1
    fi
    echo "  VOMS proxy OK: $(voms-proxy-info -timeleft 2>/dev/null)s remaining"
}

# require_el9 -- the whole chain uses el9_amd64_gcc12; enter a container if needed.
require_el9() {
    local OS_MAJOR
    OS_MAJOR=$(grep '^VERSION_ID' /etc/os-release | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$OS_MAJOR" != "9" ] && [ -z "$SINGULARITY_NAME" ] && [ ! -d /.singularity.d ]; then
        echo "ERROR: this chain needs el9 (found el${OS_MAJOR})."
        echo "       Start a container first:  cmssw-el9"
        return 1
    fi
}
