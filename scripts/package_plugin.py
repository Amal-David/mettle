#!/usr/bin/env python3
"""Package the prebuilt local Figma exporter; never publish or modify its source."""
import argparse
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-id", help="Numeric ID from Figma New plugin; optional for development")
    args = parser.parse_args()
    if args.plugin_id and not re.fullmatch(r"[0-9]{1,64}", args.plugin_id):
        parser.error("--plugin-id must be the numeric ID assigned by Figma")
    source = ROOT / "plugin"
    manifest = json.loads((source / "manifest.json").read_text())
    if args.plugin_id:
        manifest["id"] = args.plugin_id
    target = ROOT / "artifacts" / "local-plugin"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("code.js", "ui.html"):
        if not (source / name).is_file():
            parser.error(f"Missing prebuilt {name}; run npm run build in plugin first")
        shutil.copyfile(source / name, target / name)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copyfile(ROOT / "LICENSE", target / "LICENSE")
    (target / "README.md").write_text("# Mettle — experimental local plugin\n\nIn Figma Desktop: Plugins > Development > Import new plugin from manifest. Choose manifest.json from this extracted folder. No server or npm install is needed. Keep the folder in place.\n\nFull guide: https://github.com/Amal-David/mettle/blob/main/docs/LOCAL_SETUP.md\n\nThis is a development install, not a published Community plugin. If an ID is required, use Figma New plugin to obtain your own and follow the guide.\n")
    archive = target.parent / "mettle-local-plugin.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as out:
        for name in ("manifest.json", "code.js", "ui.html", "LICENSE", "README.md"):
            out.write(target / name, "mettle-plugin/" + name)
    print(f"Import: {target / 'manifest.json'}\nZIP: {archive}\nNo publication was performed.")

if __name__ == "__main__":
    main()
