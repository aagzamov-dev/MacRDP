#!/usr/bin/env python3
"""Bundle this build's Homebrew dylibs and license files for a self-contained app."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

identity = subprocess.check_output(['scripts/signing-identity.sh'], text=True).strip()
app = pathlib.Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
frameworks = app / 'Contents/Frameworks'
licenses = app / 'Contents/Resources/ThirdPartyLicenses'
frameworks.mkdir(exist_ok=True)
licenses.mkdir(parents=True, exist_ok=True)
extra_prefix = os.environ.get('MACRDP_BUNDLE_PREFIX')
def is_local_dependency(path):
    return path.startswith('/opt/homebrew/') or (extra_prefix and path.startswith(extra_prefix + '/'))
copied = {}
queue = [(executable, executable)]

def dependencies(path):
    lines = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]
    return [line.strip().split(' (', 1)[0] for line in lines]

while queue:
    original, target = queue.pop(0)
    for dependency in dependencies(original):
        if not is_local_dependency(dependency):
            continue
        source = pathlib.Path(dependency).resolve(strict=True)
        name = source.name
        if name in copied and copied[name] != source:
            raise RuntimeError(f'Conflicting library names: {name}')
        if name not in copied:
            copied[name] = source
            destination = frameworks / name
            shutil.copy2(source, destination)
            destination.chmod(0o755)
            subprocess.run(['install_name_tool', '-id', '@rpath/' + name, str(destination)], check=True)
            queue.append((source, destination))
            if 'Cellar' in source.parts:
                index = source.parts.index('Cellar')
                keg = pathlib.Path(*source.parts[:index + 3])
                license_folder = licenses / f'{source.parts[index + 1]}-{source.parts[index + 2]}'
                license_folder.mkdir(exist_ok=True)
                for candidate in keg.rglob('*'):
                    if candidate.is_file() and candidate.name.upper().startswith(('LICENSE', 'COPYING', 'COPYRIGHT', 'NOTICE')):
                        relative = candidate.relative_to(keg)
                        out = license_folder / relative
                        out.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(candidate, out)
                receipt = keg / 'INSTALL_RECEIPT.json'
                if receipt.exists():
                    shutil.copy2(receipt, license_folder / receipt.name)
        replacement = ('@rpath/' if target == executable else '@loader_path/') + name
        subprocess.run(['install_name_tool', '-change', dependency, replacement, str(target)], check=True)

for name in copied:
    target = frameworks / name
    if any(is_local_dependency(item) for item in dependencies(target)):
        raise RuntimeError(f'Unbundled dependency in {name}')
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', str(target)], check=True)
if any(is_local_dependency(item) for item in dependencies(executable)):
    raise RuntimeError('Unbundled application dependency')
if extra_prefix:
    custom_license = licenses / 'FreeRDP-3.32.2-hardware-test'
    custom_license.mkdir(exist_ok=True)
    source = pathlib.Path('build/hardware-decoding/FreeRDP-3.32.2')
    for name in ('LICENSE', 'NOTICE'):
        if (source / name).exists():
            shutil.copy2(source / name, custom_license / name)
    shutil.copy2('patches/freerdp-3.32.2-videotoolbox.patch', custom_license)
sparkle_license = pathlib.Path('Vendor/Sparkle/LICENSE')
if sparkle_license.exists():
    shutil.copy2(sparkle_license, licenses / 'Sparkle-LICENSE')
subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Bundled and signed {len(copied)} native libraries.')
