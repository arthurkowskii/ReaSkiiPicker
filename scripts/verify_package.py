"""Freeze and exercise the actual archive, not a later working-tree snapshot."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import zipfile
from build import ROOT, build

archive=build()
work=Path(os.environ['TMPDIR'])/('picker-package-'+str(time.time_ns())); work.mkdir()
with zipfile.ZipFile(archive) as zipped:
    zipped.extractall(work)
candidate=work/'ReaSkiiPicker'
manifest=json.loads((candidate/'manifest.json').read_text())
for name,expected in manifest['files'].items():
    assert hashlib.sha256((candidate/name).read_bytes()).hexdigest()==expected
assert not list(candidate.rglob('categories.json'))
assert not list(candidate.rglob('plugins.json'))
assert not list(candidate.rglob('*.dll'))
assert not list(candidate.rglob('license.key'))
results={}
for name,args in [('unit',['tests/run.py']),('native',['tests/run.py','--native']),('toggle',['tests/run.py','--toggle']),('gui',['tests/gui_test.py'])]:
    proc=subprocess.run([sys.executable,*args],cwd=candidate,capture_output=True,text=True,timeout=120)
    text=proc.stdout+proc.stderr
    (ROOT/'qa'/('package-'+name+'.log')).write_text(text)
    print(name,text,flush=True)
    assert proc.returncode==0,(name,proc.returncode,text)
    counts=[int(n) for n in re.findall(r'^DONE\s+(\d+)\s*$',text,re.M)]
    assert counts,(name,'No completion counts')
    results[name]={'checks':sum(counts),'log':'qa/package-'+name+'.log'}
for name,expected in manifest['files'].items():
    assert hashlib.sha256((candidate/name).read_bytes()).hexdigest()==expected
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected
report={'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'candidate':str(candidate),'suites':results,'total_checks':sum(v['checks'] for v in results.values()),'runtime':'REAPER 7.85 Linux + ReaImGui 0.10.0.5, isolated Xvfb','windows_runtime':'NOT_TESTED','independent_review':'NOT_PERFORMED','installed_on_daily_reaper':False}
(ROOT/'qa/package-report.json').write_text(json.dumps(report,indent=2))
for filename in ('picker-collection.png','picker-final.png','picker-global-search.png','picker-eq.png','picker-folders.png','picker-add-plugin.png'):
    from shutil import copy2
    copy2(candidate/'qa'/filename,ROOT/'qa'/filename)
print(json.dumps(report,indent=2))
