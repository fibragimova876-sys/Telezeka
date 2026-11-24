from pathlib import Path
import shutil, subprocess, os, plistlib
root=Path(__file__).resolve().parents[1]; dst=root/'build_app'; src=root/'client'
if not dst.exists():
    subprocess.run([shutil.which('flutter') or 'flutter','create','--platforms=android,windows,ios','--org','com.telezeka','--project-name','telezeka',str(dst)],check=True,shell=os.name=='nt')
shutil.copyfile(src/'pubspec.yaml',dst/'pubspec.yaml')
shutil.copyfile(src/'lib/main.dart',dst/'lib/main.dart')
p=dst/'android/app/src/main/AndroidManifest.xml'
if p.exists():
    s=p.read_text(encoding='utf-8')
    for x in ['INTERNET','RECORD_AUDIO','CAMERA','MODIFY_AUDIO_SETTINGS','ACCESS_NETWORK_STATE','BLUETOOTH_CONNECT']:
        if f'android.permission.{x}' not in s: s=s.replace('<application',f'<uses-permission android:name="android.permission.{x}" />\n    <application',1)
    s=s.replace('android:label="telezeka"','android:label="Telezeka"'); p.write_text(s,encoding='utf-8')
p=dst/'android/app/build.gradle.kts'
if p.exists():
    s=p.read_text(); s=s.replace('minSdk = flutter.minSdkVersion','minSdk = 23'); p.write_text(s)
p=dst/'ios/Runner/Info.plist'
if p.exists():
    with p.open('rb') as f: data=plistlib.load(f)
    data.update(CFBundleDisplayName='Telezeka',NSMicrophoneUsageDescription='Microphone for voice messages and calls',NSCameraUsageDescription='Camera for video calls and video messages',NSPhotoLibraryUsageDescription='Choose media to send')
    with p.open('wb') as f: plistlib.dump(data,f)
for rel in ('windows/runner/main.cpp','windows/runner/Runner.rc'):
    f=dst/rel
    if f.exists():
        t=f.read_text(encoding='utf-8'); t=t.replace('L"telezeka"','L"Telezeka"').replace('"telezeka\\0"','"Telezeka\\0"'); f.write_text(t,encoding='utf-8')
