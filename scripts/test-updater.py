#!/usr/bin/env python3
"""Exercise Sparkle's actual installer and signature checks without visible UI.

Only generated fixture apps under build/UpdateIntegration are changed. Never targets
the installed DocBrown app or the user's history. Requires the signing Keychain key.
"""
import functools
import http.server
import os
import pathlib
import plistlib
import shutil
import subprocess
import threading
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / 'build' / 'UpdateIntegration'
SDK = ROOT / '.build/artifacts/sparkle/Sparkle'
FRAMEWORK = next((SDK / 'Sparkle.xcframework').glob('macos-*/Sparkle.framework'))
DRIVER = WORK / 'Driver.app'

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, **kwargs)

def sign(app):
    run('codesign', '--force', '--deep', '--options', 'runtime', '--entitlements', ROOT / 'Resources/DocBrown.entitlements', '--sign', '-', app)

def plist(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(contents))

WORK.mkdir(parents=True, exist_ok=True)
if DRIVER.exists():
    shutil.rmtree(DRIVER)
(DRIVER / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(DRIVER / 'Contents/Frameworks').mkdir(parents=True, exist_ok=True)
shutil.copytree(FRAMEWORK, DRIVER / 'Contents/Frameworks/Sparkle.framework', symlinks=True, dirs_exist_ok=True)
run('swiftc', '-parse-as-library', '-module-cache-path', ROOT / '.build/ModuleCache', '-F', FRAMEWORK.parent,
    '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
    ROOT / 'scripts/UpdateTestDriver.swift', '-o', DRIVER / 'Contents/MacOS/Driver')
plist(DRIVER / 'Contents/Info.plist', {
    'CFBundleIdentifier': 'ai.docbrown.update-test-driver', 'CFBundleName': 'Update Test',
    'CFBundleExecutable': 'Driver', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSUIElement': True,
    'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
})
sign(DRIVER)
source = WORK / 'fixture.c'
source.write_text('int main(void) { return 0; }\n')
run('clang', source, '-o', WORK / 'fixture')
public_key = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['SUPublicEDKey']

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(WORK)))
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for mode in ('valid', 'bad-archive', 'bad-feed', 'missing-archive'):
        case = WORK / (mode + '-' + uuid.uuid4().hex[:8])
        files = case / 'files'
        files.mkdir(parents=True)
        installed = case / 'installed/Fixture.app'
        target = case / 'target/Fixture.app'
        feed = f'http://127.0.0.1:{server.server_port}/{case.name}/files/appcast.xml'
        identity = 'ai.docbrown.update-test.' + case.name
        for app, version in ((installed, '1'), (target, '2')):
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy2(WORK / 'fixture', app / 'Contents/MacOS/Fixture')
            plist(app / 'Contents/Info.plist', {
                'CFBundleIdentifier': identity, 'CFBundleName': 'Fixture', 'CFBundleExecutable': 'Fixture',
                'CFBundlePackageType': 'APPL', 'CFBundleVersion': version, 'CFBundleShortVersionString': version,
                'LSMinimumSystemVersion': '14.0', 'LSUIElement': True, 'SUFeedURL': feed,
                'SUPublicEDKey': public_key, 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
                'SUEnableAutomaticChecks': False,
            })
            sign(app)
        archive = files / 'Fixture-2.zip'
        run('ditto', '-c', '-k', '--keepParent', target, archive)
        key = os.environ.get('SPARKLE_PRIVATE_KEY')
        signing = ['--ed-key-file', '-'] if key else ['--account', 'ai.docbrown.macos.sparkle']
        run(SDK / 'bin/generate_appcast', *signing, '--maximum-deltas', '0',
            '--download-url-prefix', feed.rsplit('/', 1)[0] + '/', files, input=key)
        if mode == 'bad-archive':
            with archive.open('ab') as handle:
                handle.write(b'tampered')
        elif mode == 'bad-feed':
            appcast = files / 'appcast.xml'
            appcast.write_bytes(appcast.read_bytes().replace(b'<title>', b'<title>tampered', 1))
        elif mode == 'missing-archive':
            archive.unlink()
        args = [DRIVER / 'Contents/MacOS/Driver', installed]
        if mode != 'valid':
            args.append('--expect-failure')
        result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=55)
        (case / 'result.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'{mode}: driver failed ({result.returncode}): {result.stdout}\n{result.stderr}')
        version = plistlib.loads((installed / 'Contents/Info.plist').read_bytes())['CFBundleVersion']
        assert version == ('2' if mode == 'valid' else '1'), (mode, version)
        run('codesign', '--verify', '--deep', '--strict', installed)
        print(f'PASS: {mode} (installed version {version})', flush=True)
finally:
    server.shutdown()
