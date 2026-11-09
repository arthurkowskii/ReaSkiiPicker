"""Generate a self-contained ReaScript installer from a committed runtime, never experimental working files."""
from pathlib import Path
import argparse
import importlib.util
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('runtime_release',ROOT/'scripts/runtime_release.py')
assert spec and spec.loader
runtime=importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)


def literal(value):
    text=value.decode('utf-8')
    delimiter='='
    while ']'+delimiter+']' in text:
        delimiter+='='
    # Lua discards one newline immediately following a long-string opener.
    return '['+delimiter+'[\n'+text+']'+delimiter+']'


def build(root,ref,output,verification_report=None):
    root,output=Path(root),Path(output)
    built=runtime.build(root,ref,output)
    if verification_report:
        runtime.verify_evidence(built,verification_report)
    payload={}
    with zipfile.ZipFile(built['archive']) as archive:
        for path in archive.namelist():
            payload[path.removeprefix('ReaSkiiPicker/')]=archive.read(path)
    entries=[]
    for name,value in sorted(payload.items()):
        entries.append(' {name='+json.dumps(name)+',content='+literal(value)+'},')
    template=(root/'installer/setup.template.lua').read_text()
    # Substitute before inserting sources so tokens inside payloads cannot alter runtime bytes.
    text=template.replace('__VERSION__',built['version']).replace('__PAYLOAD__','\n'.join(entries))
    asset=output/('ReaSkiiPicker-'+built['version']+'-setup.lua')
    asset.write_text(text,encoding='utf-8',newline='\n')
    return {**built,'installer':str(asset),'installer_sha256':runtime.sha(asset.read_bytes()),
            'installer_bytes':asset.stat().st_size,'payload':payload}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref',default='HEAD')
    parser.add_argument('--output',type=Path,default=ROOT/'dist')
    parser.add_argument('--verification-report',type=Path)
    args=parser.parse_args()
    result=build(ROOT,args.ref,args.output,args.verification_report)
    print(json.dumps({k:v for k,v in result.items() if k!='payload'},indent=2))
