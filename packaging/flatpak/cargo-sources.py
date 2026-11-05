#!/usr/bin/env python3
"""Generate cargo-sources.json for the Flatpak build from Cargo.lock.

Flathub builds run without network access, so every crate is listed as a
flatpak-builder source (download URL + sha256 from Cargo.lock) and unpacked
into a local vendor directory that cargo is pointed at. Only crates.io
packages are supported (Wordloom has no git dependencies).

Usage, from the repository root:
    packaging/flatpak/cargo-sources.py            # rewrite the file
    packaging/flatpak/cargo-sources.py --check    # fail if it is stale (CI)
"""

import json
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "cargo-sources.json"
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"
VENDOR = "cargo/vendor"


def sources() -> list:
    lock = tomllib.loads((ROOT / "Cargo.lock").read_text())
    out = []
    for pkg in sorted(lock["package"], key=lambda p: (p["name"], p["version"])):
        src = pkg.get("source")
        if src is None:
            continue  # a workspace member
        if src != CRATES_IO:
            sys.exit(f"unsupported source for {pkg['name']}: {src}")
        name, version, sha = pkg["name"], pkg["version"], pkg["checksum"]
        dest = f"{VENDOR}/{name}-{version}"
        out.append({
            "type": "archive",
            "archive-type": "tar-gzip",
            "url": f"https://static.crates.io/crates/{name}/{name}-{version}.crate",
            "sha256": sha,
            "dest": dest,
        })
        # cargo checks vendored crates against this file.
        out.append({
            "type": "inline",
            "contents": json.dumps({"package": sha, "files": {}}),
            "dest": dest,
            "dest-filename": ".cargo-checksum.json",
        })
    out.append({
        "type": "inline",
        "contents": (
            "[source.vendored-sources]\n"
            f'directory = "{VENDOR}"\n\n'
            "[source.crates-io]\n"
            'replace-with = "vendored-sources"\n'
        ),
        "dest": "cargo",
        "dest-filename": "config.toml",
    })
    return out


def main() -> None:
    text = json.dumps(sources(), indent=4) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            sys.exit("cargo-sources.json is out of date: run packaging/flatpak/cargo-sources.py")
        return
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
