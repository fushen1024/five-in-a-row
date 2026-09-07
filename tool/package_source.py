"""Package portable source without SDKs, caches, generated outputs or local paths."""
from pathlib import Path
import os
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / 'deliverables'
output.mkdir(exist_ok=True)
archive = output / 'pine-gomoku-source.zip'
folders = ['lib', 'android', 'ios', 'test', 'docs', 'tool', '.github']
excluded_dirs = {'.gradle', 'build', 'Pods', '.symlinks', 'ephemeral', '__pycache__'}
excluded_files = {'local.properties', 'Generated.xcconfig', 'flutter_export_environment.sh'}
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.gitignore', '.metadata', 'README.md', '项目说明文档.txt']:
        bundle.write(root / name, name)
    for folder in folders:
        for base, dirs, files in os.walk(root / folder):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for name in files:
                if name in excluded_files or name.endswith(('.iml', '.pyc')):
                    continue
                path = Path(base) / name
                bundle.write(path, path.relative_to(root).as_posix())
print(f'{archive} ({archive.stat().st_size:,} bytes)')
