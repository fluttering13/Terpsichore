"""Smoke-test an optimized release on an emulator, without clearing app data."""

import argparse
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--apk', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.serial):
        parser.error('Use a test emulator; this test force-stops the app.')
    root = Path(__file__).resolve().parents[1]
    gradle = (root / 'android/app/build.gradle.kts').read_text(encoding='utf-8')
    package = re.search(r'^\s*applicationId\s*=\s*"([\w.]+)"', gradle, re.M)[1]
    output = root / 'build/release-startup'
    output.mkdir(parents=True, exist_ok=True)

    def adb(*command):
        return subprocess.run(
            ['adb', '-s', args.serial, *command], check=True,
            capture_output=True, encoding='utf-8', errors='replace', timeout=60,
        ).stdout.strip()

    if args.apk:
        adb('install', '-r', str(args.apk.resolve(strict=True)))
    info = adb('shell', 'dumpsys', 'package', package)
    if 'versionCode=' not in info or re.search(r'flags=\[[^\]]*DEBUGGABLE', info):
        raise RuntimeError('Install a non-debuggable release APK before testing.')

    for attempt in range(1, 3):
        adb('shell', 'am', 'force-stop', package)
        launch = adb('shell', 'am', 'start', '-W', '-n', f'{package}/.FlutterLauncherIcon')
        (output / f'launch-{attempt}.txt').write_text(launch, encoding='utf-8')
        if 'Status: ok' not in launch:
            raise RuntimeError(f'Launcher failed: {launch}')
        time.sleep(5)
        # am start can return success even when the startup provider crashes.
        try:
            process = adb('shell', 'pidof', package)
        except subprocess.CalledProcessError:
            crash = adb('logcat', '-b', 'crash', '-d')
            (output / f'crash-{attempt}.txt').write_text(crash, encoding='utf-8')
            raise RuntimeError('Release died during startup; see build/release-startup.')
        if not process:
            raise RuntimeError('Release process did not survive startup.')
        for _ in range(5):
            adb('shell', 'uiautomator', 'dump', '/sdcard/terpsichore-release-test.xml')
            xml = adb('shell', 'cat', '/sdcard/terpsichore-release-test.xml')
            (output / f'ui-{attempt}.xml').write_text(xml, encoding='utf-8')
            if 'Dance · Learn · Grow' in xml:
                break
            for node in ET.fromstring(xml).iter('node'):
                label = node.get('content-desc') or node.get('text')
                if label in ('稍後再說', 'Later'):
                    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
                    adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
            time.sleep(1)
        else:
            raise RuntimeError('Release stayed alive but did not display the home screen.')
        if adb('shell', 'pidof', package) != process:
            raise RuntimeError('Release process restarted during the home-screen check.')
        crash = adb('logcat', '-b', 'crash', '-d', f'--pid={process}')
        if re.search(r'FATAL EXCEPTION|Fatal signal', crash):
            raise RuntimeError(f'Release crash: {crash}')
        print(f'PASS release cold start {attempt}: home visible, process {process} alive')


if __name__ == '__main__':
    main()
