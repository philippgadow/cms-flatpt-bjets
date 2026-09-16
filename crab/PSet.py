# Minimal parameter set for the CRAB submission (PrivateMC + scriptExe).
#
# CRAB requires a cmsRun config even though scriptExe replaces cmsRun; the real
# work happens in crab_job.sh (the full multi-release chain).  This config
#   - passes CRAB's submission-time validation (PrivateMC needs an EmptySource),
#   - DECLARES THE TWO EDM OUTPUTS so CRAB will publish them
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

# Output filenames: exactly what the chain writes and what crab_job.sh leaves
# in the job directory.  submit.sh sources production/env.sh (and resolves the
# sample) before `crab submit`, so these come from the same single source of
# truth rather than being duplicated here.
_SAMPLE = os.environ.get('SAMPLE', 'flatpT_Zprime_bb')
_MINI = '%s_%s.root' % (os.environ.get('CAMPAIGN_MINI',
                                       'RunIII2024Summer24MiniAODv6'), _SAMPLE)
_NANO = '%s_%s.root' % (os.environ.get('CAMPAIGN_NANO',
                                       'RunIII2024Summer24NanoAODv15'), _SAMPLE)

process.MINIAODSIMoutput = cms.OutputModule(
    'PoolOutputModule',
    fileName=cms.untracked.string('file:%s' % _MINI),
    dataset=cms.untracked.PSet(
        dataTier=cms.untracked.string('MINIAODSIM'),
        filterName=cms.untracked.string(''),
    ),
)

process.NANOAODSIMoutput = cms.OutputModule(
    'NanoAODOutputModule',
    fileName=cms.untracked.string('file:%s' % _NANO),
    dataset=cms.untracked.PSet(
        dataTier=cms.untracked.string('NANOAODSIM'),
        filterName=cms.untracked.string(''),
    ),
)

process.MINIAODSIMoutput_step = cms.EndPath(process.MINIAODSIMoutput)
process.NANOAODSIMoutput_step = cms.EndPath(process.NANOAODSIMoutput)
process.schedule = cms.Schedule(process.MINIAODSIMoutput_step,
                                process.NANOAODSIMoutput_step)
