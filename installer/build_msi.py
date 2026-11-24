"""Create a branded, native WiX MSI from a complete Flutter Windows release."""
import argparse, hashlib, os, subprocess, uuid, base64
from io import BytesIO
from pathlib import Path
from xml.etree import ElementTree as E
from PIL import Image, ImageDraw, ImageFont

WIX="http://wixtoolset.org/schemas/v4/wxs"
UI=WIX+"/ui"
E.register_namespace("",WIX); E.register_namespace("ui",UI)
def node(parent,tag,**attrs):
    return E.SubElement(parent,"{"+WIX+"}"+tag,{k:str(v) for k,v in attrs.items()})
def ident(prefix,path):
    return prefix+hashlib.sha256(str(path).replace("\\","/").lower().encode()).hexdigest()[:28]
def font(size,bold=False):
    return ImageFont.truetype(str(Path(os.environ["WINDIR"])/"Fonts"/("segoeuib.ttf" if bold else "segoeui.ttf")),size)
def logo(draw,cx,cy,scale=1):
    # Same generated mark used by the Flutter app and all native launchers.
    asset=Path(__file__).resolve().parents[1]/"client/assets/brand.png.b64"
    mark=Image.open(BytesIO(base64.b64decode(asset.read_text(),validate=True))).convert("RGBA")
    size=max(1,round(54*scale))
    factor=size/max(mark.size)
    mark=mark.resize((max(1,round(mark.width*factor)),max(1,round(mark.height*factor))),Image.Resampling.LANCZOS)
    draw._image.paste(mark,(round(cx-mark.width/2),round(cy-mark.height/2)),mark)
def brand(out):
    b=Image.new("RGB",(493,58),"#FFFFFF"); d=ImageDraw.Draw(b)
    d.rectangle((0,55,493,57),fill="#226B55")
    logo(d,355,27,.48); d.text((376,12),"Telezeka",font=font(19,True),fill="#193D35")
    d.text((377,35),"WINDOWS SETUP",font=font(8),fill="#63798F")
    b.save(out/"banner.bmp")
    b=Image.new("RGB",(493,312),"#FFFFFF");d=ImageDraw.Draw(b)
    d.rectangle((0,0,163,312),fill="#142C29")
    d.ellipse((-105,163,176,444),outline="#34534D",width=1)
    d.ellipse((-88,185,158,431),outline="#34534D",width=1)
    d.rectangle((0,0,163,5),fill="#226B55")
    logo(d,82,87,1.2)
    d.text((82,133),"Telezeka",anchor="mt",font=font(24,True),fill="#FFFFFF")
    d.text((82,169),"GLOBAL",anchor="mt",font=font(12),fill="#B0D8C6")
    d.line((26,258,137,258),fill="#34546B",width=1)
    d.text((82,271),"WINDOWS",anchor="mt",font=font(10),fill="#C3D6CE")
    b.save(out/"dialog.bmp")
    i=Image.new("RGBA",(256,256),(0,0,0,0));logo(ImageDraw.Draw(i),128,128,4.4)
    i.save(out/"telezeka.ico",sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
    def rtf(t):
        return "".join(ch if ord(ch)<128 and ch not in "\\{}" else "\\u"+str(ord(ch))+"?" for ch in t)
    terms=["Telezeka — предварительная версия","Установка обновляет предыдущую MSI-версию Telezeka, удаляет её старые файлы и добавляет ярлык в меню «Пуск». Аккаунты и переписка на сервере не удаляются.","Для работы требуется доступный HTTPS-сервер. Эта тестовая сборка не предназначена для конфиденциальной переписки.","Установщик и приложение могут не иметь цифровой подписи. Устанавливайте только файлы из официального репозитория Telezeka.","Продолжая установку, вы подтверждаете, что ознакомились с условиями тестирования."]
    (out/"notice.rtf").write_text(r"{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\fs20 "+r"\par ".join(rtf(t) for t in terms)+"}",encoding="ascii")
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--version",default="0.2.0")
    a=p.parse_args()
    source=a.source.resolve(); target=a.output.resolve()
    if not (source/"telezeka.exe").is_file() or not (source/"flutter_windows.dll").is_file() or not (source/"data").is_dir():
        raise SystemExit("Incomplete Windows application")
    work=target.parent/"msi-work";work.mkdir(parents=True,exist_ok=True);target.parent.mkdir(parents=True,exist_ok=True)
    brand(work)
    root=E.Element("{"+WIX+"}Wix")
    pkg=node(root,"Package",Name="Telezeka",Manufacturer="Telezeka",Version=a.version,UpgradeCode="D94688F4-10AE-47DC-B2D6-E24A30AA94B2",Scope="perMachine",Language="1049",InstallerVersion="500")
    node(pkg,"MajorUpgrade",Schedule="afterInstallInitialize",MigrateFeatures="yes",DowngradeErrorMessage="Уже установлена более новая версия Telezeka.")
    # Older EXE editions are per-user Inno Setup installations, not MSI products.
    # Detect them rather than executing a user-writable uninstaller with elevated rights.
    for prop,app_id in [("LEGACY_PREVIEW","TelezekaPreview"),("LEGACY_EXE","Telezeka")]:
        property_node=node(pkg,"Property",Id=prop,Secure="yes")
        node(property_node,"RegistrySearch",Id=prop+"Search",Root="HKCU",Key="Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"+app_id+"_is1",Name="UninstallString",Type="raw",Bitness="always32")
    node(pkg,"Launch",Condition="Installed OR (NOT LEGACY_PREVIEW AND NOT LEGACY_EXE)",Message="Обнаружена старая EXE-версия Telezeka. Удалите её через Параметры Windows — Приложения, затем запустите MSI снова. Переписка на сервере сохранится.")
    node(pkg,"MediaTemplate",EmbedCab="yes")
    node(pkg,"Icon",Id="TelezekaIcon",SourceFile=work/"telezeka.ico")
    node(pkg,"Property",Id="ARPPRODUCTICON",Value="TelezekaIcon")
    node(pkg,"Property",Id="ARPURLINFOABOUT",Value="https://github.com/fibragimova876-sys/Telezeka")
    pf=node(pkg,"StandardDirectory",Id="ProgramFiles64Folder")
    install=node(pf,"Directory",Id="INSTALLFOLDER",Name="Telezeka")
    node(pkg,"StandardDirectory",Id="ProgramMenuFolder")
    feature=node(pkg,"Feature",Id="Main",Title="Telezeka",Level="1")
    dirs={Path("."):install}
    def directory(rel):
        if rel not in dirs:
            dirs[rel]=node(directory(rel.parent),"Directory",Id=ident("D",rel),Name=rel.name)
        return dirs[rel]
    for f in sorted(source.rglob("*")):
        if not f.is_file(): continue
        rel=f.relative_to(source); cid=ident("C",rel)
        comp=node(directory(rel.parent),"Component",Id=cid,Guid=str(uuid.uuid5(uuid.UUID("48b91dbf-23e8-4a62-9627-5bca68c48945"),str(rel).replace("\\","/").lower())),Bitness="always64")
        file=node(comp,"File",Id=ident("F",rel),Source=f,KeyPath="yes")
        if rel.as_posix().lower()=="telezeka.exe":
            node(file,"Shortcut",Id="TelezekaStart",Directory="ProgramMenuFolder",Name="Telezeka",Advertise="yes",Icon="TelezekaIcon",WorkingDirectory="INSTALLFOLDER")
        node(feature,"ComponentRef",Id=cid)
    E.SubElement(pkg,"{"+UI+"}WixUI",{"Id":"WixUI_InstallDir","InstallDirectory":"INSTALLFOLDER"})
    for k,v in [("WixUIBannerBmp","banner.bmp"),("WixUIDialogBmp","dialog.bmp"),("WixUILicenseRtf","notice.rtf")]:
        node(pkg,"WixVariable",Id=k,Value=work/v)
    node(pkg,"Property",Id="WIXUI_EXITDIALOGOPTIONALTEXT",Value="Telezeka установлена. Откройте приложение из меню «Пуск».")
    # The final screen checkbox runs a small embedded helper in the installing user's context.
    helper=work/"DesktopShortcut.exe"
    csc=Path(os.environ["WINDIR"])/"Microsoft.NET"/"Framework64"/"v4.0.30319"/"csc.exe"
    subprocess.run([str(csc),"/nologo","/target:winexe","/optimize+","/reference:Microsoft.CSharp.dll","/reference:System.Windows.Forms.dll","/out:"+str(helper),str(Path(__file__).with_name("DesktopShortcut.cs"))],check=True)
    node(pkg,"Binary",Id="DesktopShortcutHelper",SourceFile=helper)
    node(pkg,"CustomAction",Id="CreateDesktopShortcut",BinaryRef="DesktopShortcutHelper",ExeCommand='"[#'+ident("F",Path("telezeka.exe"))+']"',Execute="immediate",Impersonate="yes",Return="ignore")
    node(pkg,"Property",Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT",Value="Создать ярлык на рабочем столе")
    node(pkg,"Property",Id="WIXUI_EXITDIALOGOPTIONALCHECKBOX",Value="1")
    ui=node(pkg,"UI")
    node(ui,"Publish",Dialog="ExitDialog",Control="Finish",Event="DoAction",Value="CreateDesktopShortcut",Order="1",Condition="WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 AND NOT Installed")
    wxs=work/"Telezeka.wxs";E.indent(root);E.ElementTree(root).write(wxs,encoding="utf-8",xml_declaration=True)
    subprocess.run(["wix","build","-arch","x64","-culture","ru-RU","-ext","WixToolset.UI.wixext",str(wxs),"-o",str(target)],check=True)
    if not target.is_file(): raise SystemExit("MSI not created")
if __name__=="__main__": main()
