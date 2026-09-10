# Minimal parameter set for the CRAB submission (PrivateMC + scriptExe).
#
# CRAB requires a cmsRun config even though scriptExe replaces cmsRun; the real
# work happens in crab_job.sh (the full multi-release chain).  This config only
#   - passes CRAB's submission-time validation (PrivateMC needs an EmptySource),
#   - is run once at the end of crab_job.sh to produce the
#     FrameworkJobReport.xml that CRAB requires from every scriptExe job.
import os

import FWCore.ParameterSet.Config as cms

process = cms.Process('FLATPT')

process.source = cms.Source('EmptySource')
process.maxEvents = cms.untracked.PSet(input=cms.untracked.int32(1))

# CRAB refuses to submit unless this matches JobType.numCores.  submit.sh sets
# numCores from $NTHREADS (production/env.sh, default 4) and exports it before
# `crab submit` imports this file, so the two always agree.
process.options = cms.untracked.PSet(
    numberOfThreads=cms.untracked.uint32(int(os.environ.get('NTHREADS', '4'))),
    numberOfStreams=cms.untracked.uint32(0),
)

# CRAB tweaks per-job seeds into this service; it must exist for the tweak to
# land.  The chain's real seeds are handled in crab_job.sh (seedbase + CRAB_Id).
process.RandomNumberGeneratorService = cms.Service(
    'RandomNumberGeneratorService',
    generator=cms.PSet(initialSeed=cms.untracked.uint32(1)),
)
