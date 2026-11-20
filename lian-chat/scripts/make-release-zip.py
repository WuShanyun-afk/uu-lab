"""Package the web source tree into Lian-<version>.zip (sibling of the folder).

    python scripts/make-release-zip.py 1.9.4

The zip mirrors the lian-chat folder layout (index.html + js/ + css/ + assets/
+ docs/ + tests/ + scripts/), so it can be unzipped and opened with
start-Lian.bat without any build step.
"""
import os
import sys
import zipfile

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".cache", ".idea", ".vscode"}
SKIP_FILES = {".DS_Store", "Thumbs.db"}


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: make-release-zip.py <version>")
        return 2
    version = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(os.path.dirname(root), f"Lian-{version}.zip")
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            for name in sorted(filenames):
                if name in SKIP_FILES or name.endswith(".pyc"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                bundle.write(full, rel)
                count += 1
    print(f"{out}\nfiles={count} bytes={os.path.getsize(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
