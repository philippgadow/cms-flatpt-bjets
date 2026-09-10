#!/usr/bin/env python3
"""Merge cmsRun FrameworkJobReports into one for CRAB.

A scriptExe job hands CRAB a single FrameworkJobReport.xml, but this chain
produces its publishable outputs (MiniAOD + NanoAOD) in two separate cmsRun
steps.  CRAB publishes exactly the output <File> sections found in the report,
so combine them: keep the base report (the final NanoAOD step) whole and
append the output-file sections of the other reports, as if one cmsRun had run
with several output modules.  The module labels (MINIAODSIMoutput /
NANOAODSIMoutput) stay distinct, which is what keeps the published datasets
apart.

Two fix-ups are applied for CRAB's post-processing (CMSRunAnalysis.py):

- --pfn-dir DIR rewrites each output <PFN> to DIR/<basename>: the reports were
  written while the outputs lived in the chain workdir, but crab_job.sh moves
  them to the job directory before stage-out, and CRAB stats the PFN to add
  size and checksums.
- <InputFile> sections are dropped: they point at intermediate chain files
  that are deleted before stage-out, and the real chain inputs are not in DBS
  anyway (no parentage).

Usage: merge_fjr.py [--pfn-dir DIR] <base_fjr.xml> <extra_fjr.xml> [...] \
           > FrameworkJobReport.xml
"""
import os
import sys
import xml.etree.ElementTree as ET


def fix_files(root, pfn_dir):
    """Drop InputFile sections; point output PFNs at pfn_dir."""
    for inp in root.findall('InputFile'):
        root.remove(inp)
    if not pfn_dir:
        return
    for f in root.findall('File'):
        pfn = f.find('PFN')
        if pfn is not None and pfn.text:
            base = os.path.basename(pfn.text.replace('file:', ''))
            pfn.text = os.path.join(pfn_dir, base)


def main():
    args = sys.argv[1:]
    pfn_dir = None
    if args and args[0] == '--pfn-dir':
        pfn_dir = args[1]
        args = args[2:]
    if len(args) < 2:
        sys.exit(__doc__)
    root = ET.parse(args[0]).getroot()
    fix_files(root, pfn_dir)
    for extra in args[1:]:
        extra_root = ET.parse(extra).getroot()
        fix_files(extra_root, pfn_dir)
        files = extra_root.findall('File')
        if not files:
            sys.exit("ERROR: no output <File> section in %s" % extra)
        for f in files:
            root.append(f)
    sys.stdout.write(ET.tostring(root, encoding='unicode'))


if __name__ == '__main__':
    main()
