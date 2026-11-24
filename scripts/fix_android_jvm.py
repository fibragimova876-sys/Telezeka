"""Align file_picker Kotlin JVM target with its Java 11 target."""
import json, re
from pathlib import Path
from urllib.parse import urlparse, unquote
cfg=Path('build_app/.dart_tool/package_config.json').resolve()
packages=json.loads(cfg.read_text())['packages']
entry=next(p for p in packages if p['name']=='file_picker')
uri=urlparse(entry['rootUri'])
root=Path(unquote(uri.path)) if uri.scheme=='file' else (cfg.parent/unquote(entry['rootUri'])).resolve()
for path in (root/'android/build.gradle',root/'android/build.gradle.kts'):
    if not path.exists(): continue
    s=path.read_text()
    s,n=re.subn(r"(jvmTarget\s*=\s*['\"])1\.8(['\"])",r"\g<1>11\2",s)
    if not n:
        if path.suffix=='.kts':
            s+='\n tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach { compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11) }\n'
        else:
            s+='\n tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach { kotlinOptions.jvmTarget = "11" }\n'
    path.write_text(s)
    print("Aligned Kotlin target with Java 11:", path)
    break
else: raise RuntimeError('file_picker Android Gradle file not found')
