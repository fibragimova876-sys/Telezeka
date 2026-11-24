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

# Build native launcher assets from the same generated brand mark.
import base64
from io import BytesIO
try:
    from PIL import Image
except ImportError:
    subprocess.run([os.sys.executable,'-m','pip','install','Pillow==11.3.0'],check=True)
    from PIL import Image
mark=Image.open(BytesIO(base64.b64decode((src/'assets/brand.png.b64').read_text(),validate=True))).convert('RGBA')
assets=dst/'assets'; assets.mkdir(exist_ok=True)
def icon(size,opaque=False):
    canvas=Image.new('RGBA',(size,size),'#064637' if opaque else (0,0,0,0))
    factor=int(size*.86)/max(mark.size)
    m=mark.resize((max(1,round(mark.width*factor)),max(1,round(mark.height*factor))),Image.Resampling.LANCZOS)
    canvas.alpha_composite(m,((size-m.width)//2,(size-m.height)//2))
    return canvas.convert('RGB') if opaque else canvas
icon(256).save(assets/'brand.png')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    p=dst/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    if p.exists(): icon(size).save(p)
p=dst/'windows/runner/resources/app_icon.ico'
if p.exists(): icon(256).save(p,sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
p=dst/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
if p.exists():
    for f in p.glob('*.png'):
        with Image.open(f) as current: size=current.width
        icon(size,True).save(f)
