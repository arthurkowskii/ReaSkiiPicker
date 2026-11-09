"""Build installation-only archives from committed, verified sources, and publish private releases.

Usage: python scripts/runtime_release.py --ref HEAD --publish --verification-report qa/package-report.json
Uncommitted changes are deliberately ignored. QA/deployment evidence stays local.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = 'arthurkowskii/ReaSkiiPicker'


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(root, ref, output):
    root, output = Path(root), Path(output)
    commit = git(root, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    entry = git(root, 'show', commit + ':ReaSkii_Picker.lua')
    match = re.search(rb'^-- @version ([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?)\r?$', entry, re.M)
    if not match:
        raise ValueError('Missing or invalid committed entry-point version')
    version = match.group(1).decode()
    names = git(root, 'ls-tree', '-r', '-z', '--name-only', commit).decode().split('\0')
    selected = []
    for name in names:
        path = PurePosixPath(name)
        if '..' in path.parts or path.is_absolute():
            raise ValueError('Unsafe tree path')
        if name == 'ReaSkii_Picker.lua' or (name.startswith('src/') and name.endswith('.lua')) or (
            name.startswith('vendor/') and (name.endswith('.lua') or 'license' in path.name.lower())
        ):
            selected.append(name)
    required = {'ReaSkii_Picker.lua', 'src/ui.lua', 'src/model.lua', 'src/store.lua', 'src/host.lua',
                'vendor/json.lua', 'vendor/json-LICENSE'}
    if not required.issubset(selected):
        raise ValueError('Runtime module or third-party legal notice missing')
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(selected):
            item = zipfile.ZipInfo('ReaSkiiPicker/' + name, (2026, 1, 1, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100644 << 16
            archive.writestr(item, git(root, 'show', commit + ':' + name))
    payload = data.getvalue()
    output.mkdir(parents=True, exist_ok=True)
    target = output / ('ReaSkiiPicker-' + version + '-install.zip')
    if target.exists() and target.read_bytes() != payload:
        raise ValueError('This version already has a different install archive; bump the runtime version')
    target.write_bytes(payload)
    return {'archive': str(target), 'sha256': sha(payload), 'commit': commit,
            'version': version, 'runtime_files': len(selected)}


def verify_evidence(built, report_path):
    report = json.loads(Path(report_path).read_text())
    if not report.get('installed_on_daily_reaper'):
        raise ValueError('Publication requires verified deployment evidence')
    checks = sum(s['checks'] for s in report['suites'].values())
    if checks <= 0 or checks != report['total_checks']:
        raise ValueError('Inconsistent test counts')
    tested = Path(report['archive'])
    if sha(tested.read_bytes()) != report['archive_sha256']:
        raise ValueError('Tested archive checksum mismatch')
    with zipfile.ZipFile(built['archive']) as runtime, zipfile.ZipFile(tested) as frozen:
        version = json.loads(frozen.read('ReaSkiiPicker/manifest.json'))['version']
        if version != built['version']:
            raise ValueError('Verified version differs from release')
        for name in runtime.namelist():
            if runtime.read(name) != frozen.read(name):
                raise ValueError('Runtime differs from verified candidate: ' + name)
    deployment = json.loads(Path(report['windows_deployment_report']).read_text(encoding='utf-8-sig'))
    if deployment['archive_sha256'] != report['archive_sha256'] or deployment['runtime']['status'] != 'running':
        raise ValueError('Deployment evidence does not match tested archive')
    return report


def gh(*args):
    return subprocess.check_output(['gh', *args], cwd=ROOT, text=True)


def publish(built, report_path):
    report = verify_evidence(built, report_path)
    repo = json.loads(gh('repo', 'view', REPO, '--json', 'isPrivate,url'))
    if repo.get('isPrivate') is not True:
        raise ValueError('Refuse to publish outside the private repository')
    remote = json.loads(gh('api', 'repos/' + REPO + '/commits/' + built['commit']))
    if remote['sha'] != built['commit']:
        raise ValueError('Commit has not been pushed')
    tag = 'v' + built['version']
    ref = subprocess.run(['gh', 'api', 'repos/' + REPO + '/git/ref/tags/' + tag],
                         cwd=ROOT, capture_output=True, text=True)
    if ref.returncode == 0:
        value = json.loads(ref.stdout)['object']
        if value['type'] != 'commit' or value['sha'] != built['commit']:
            raise ValueError('Existing tag does not identify this exact commit')
    elif '404' not in ref.stderr:
        raise RuntimeError(ref.stderr)
    notes = f'''Archive d'installation uniquement : `{Path(built['archive']).name}`.

Extraire le dossier `ReaSkiiPicker` dans `Scripts` du dossier de ressources REAPER.
Dans REAPER : Options > Show REAPER resource path in explorer/finder.
Charger `Scripts/ReaSkiiPicker/ReaSkii_Picker.lua` depuis Actions.
ReaImGui 0.10 ou supérieur doit être installé via ReaPack (extension et shim Lua).
Ne pas remplacer `REAPER/ReaSkiiPicker/library.json` : ce sont vos données, pas le programme.

Sources : `{built['commit']}`. Runtime identique à la version vérifiée ({report['total_checks']} contrôles ; preuves de tests et de démarrage Windows distinctes).
SHA256 de l'archive d'installation : `{built['sha256']}`.

Les liens « Source code » ajoutés par GitHub ne sont pas le paquet d'installation.
'''
    scratch = Path(os.environ.get('TMPDIR', str(Path.home() / '.hermes/cache/scratch')))
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch) as work:
        notes_path = Path(work) / 'notes.md'
        notes_path.write_text(notes)
        gh('release', 'create', tag, built['archive'], '--repo', REPO, '--target', built['commit'],
           '--prerelease', '--title', 'ReaSkii Picker ' + built['version'], '--notes-file', str(notes_path))
        release = json.loads(gh('release', 'view', tag, '--repo', REPO, '--json',
                                'url,tagName,isDraft,isPrerelease,assets'))
        if release['isDraft'] or not release['isPrerelease'] or release['tagName'] != tag:
            raise ValueError('Unexpected published release state')
        asset = Path(built['archive']).name
        if len(release['assets']) != 1 or release['assets'][0]['name'] != asset:
            raise ValueError('Unexpected release assets')
        remote_ref = json.loads(gh('api', 'repos/' + REPO + '/git/ref/tags/' + tag))['object']
        if remote_ref['sha'] != built['commit']:
            raise ValueError('Published tag has the wrong commit')
        gh('release', 'download', tag, '--repo', REPO, '--pattern', asset, '--dir', work)
        if sha((Path(work) / asset).read_bytes()) != built['sha256']:
            raise ValueError('Downloaded release asset checksum mismatch')
    return release


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--verification-report', type=Path)
    args = parser.parse_args()
    if args.publish and not args.verification_report:
        parser.error('--publish requires --verification-report')
    built = build(ROOT, args.ref, args.output)
    if args.publish:
        built['release'] = publish(built, args.verification_report)
    print(json.dumps(built, indent=2))
