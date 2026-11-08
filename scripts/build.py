"""Build a deterministic alpha archive containing sources, never private Picker data."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]

def build():
    sources=[ROOT/'ReaSkii_Picker.lua',ROOT/'README.md',ROOT/'requirements-dev.txt']
    for folder in ('src','vendor','tests','scripts'):
        sources.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc')
    sources=sorted(sources)
    payload={str(p.relative_to(ROOT)):p.read_bytes() for p in sources}
    manifest={'version':'0.1.1-alpha','entrypoint':'ReaSkii_Picker.lua','files':{n:hashlib.sha256(b).hexdigest() for n,b in payload.items()}}
    payload['manifest.json']=(json.dumps(manifest,indent=2,sort_keys=True)+'\n').encode()
    output=ROOT/'dist/ReaSkiiPicker-0.1.1-alpha.zip'; output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        for name,data in sorted(payload.items()):
            entry=zipfile.ZipInfo('ReaSkiiPicker/'+name,(2026,1,1,0,0,0)); entry.compress_type=zipfile.ZIP_DEFLATED
            entry.external_attr=0o100644<<16; archive.writestr(entry,data)
    with zipfile.ZipFile(output) as archive:
        for name,expected in manifest['files'].items():
            assert hashlib.sha256(archive.read('ReaSkiiPicker/'+name)).hexdigest()==expected
    print(json.dumps({'archive':str(output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'files':len(payload),'bytes':output.stat().st_size},indent=2))
    return output

if __name__=='__main__': build()
