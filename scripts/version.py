#!/usr/bin/env python3
"""Release version: <rxminer version>.<app revision>, e.g. 0.2.0.1.

The first three numbers always equal the rxminer version the app is built
against; the fourth counts this app's own releases of that miner version.
apps/miner/pubspec.yaml holds it as `version: 0.2.0+1`. This script checks
that every place agreeing on it does, and prints values for CI.

  version.py check [--tag vX.Y.Z.N[-label]]   fail on any mismatch
  version.py env                      print VERSION=..., BUILD_NAME=... lines
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "apps/miner/pubspec.yaml"
LOCK = ROOT / "packages/rxminer/native/Cargo.lock"
MANIFEST = ROOT / "packages/rxminer/native/Cargo.toml"
BRAND = ROOT / "apps/miner/lib/ui/brand.dart"


def read():
    pub = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$",
                    PUBSPEC.read_text(), re.M)
    if not pub:
        sys.exit(f"{PUBSPEC}: version must look like 0.2.0+1")
    major, minor, patch, revision = map(int, pub.groups())
    lock = re.search(r'name = "rxminer"\nversion = "([^"]+)"\nsource = "[^"]*rev=([0-9a-f]+)',
                     LOCK.read_text())
    if not lock:
        sys.exit(f"{LOCK}: no rxminer package")
    rev = re.search(r'rxminer = \{[^}]*rev = "([0-9a-f]+)"', MANIFEST.read_text())
    brand = BRAND.read_text()
    shown_version = re.search(r"const minerVersion = '([^']+)';", brand)
    shown_rev = re.search(r"const minerRevision = '([0-9a-f]+)';", brand)
    return {
        "name": f"{major}.{minor}.{patch}",
        "revision": revision,
        "parts": (major, minor, patch, revision),
        "miner": lock.group(1),
        "lock_rev": lock.group(2),
        "manifest_rev": rev.group(1) if rev else None,
        "shown_version": shown_version.group(1) if shown_version else None,
        "shown_rev": shown_rev.group(1) if shown_rev else None,
    }


def check(tag=None):
    v = read()
    errors = []
    if v["name"] != v["miner"]:
        errors.append(f"pubspec version {v['name']} must equal the rxminer version {v['miner']} in Cargo.lock")
    if v["revision"] < 1 or v["revision"] > 999:
        errors.append("the app revision (after +) must be 1 to 999")
    if v["manifest_rev"] != v["lock_rev"]:
        errors.append("Cargo.toml and Cargo.lock pin different rxminer commits; run cargo update -p rxminer")
    if v["shown_version"] != v["miner"]:
        errors.append(f"minerVersion in brand.dart must be {v['miner']}")
    if not v["shown_rev"] or not v["lock_rev"].startswith(v["shown_rev"]):
        errors.append(f"minerRevision in brand.dart must be {v['lock_rev'][:7]}")
    version = f"{v['name']}.{v['revision']}"
    # A suffix such as -beta.1 marks a prerelease of the same version.
    if tag is not None and not re.fullmatch(rf"v{re.escape(version)}(-[0-9A-Za-z.]+)?", tag):
        errors.append(f"tag {tag} does not match the app version; expected v{version} or v{version}-<label>")
    if errors:
        sys.exit("\n".join(errors))
    print(f"version {version} (rxminer {v['miner']} at {v['lock_rev'][:7]}, app revision {v['revision']})")


def env():
    v = read()
    major, minor, patch, revision = v["parts"]
    # Android needs a version code that only grows, across miner versions too.
    code = ((major * 100 + minor) * 100 + patch) * 1000 + revision
    print(f"VERSION={v['name']}.{revision}")
    print(f"BUILD_NAME={v['name']}")
    print(f"BUILD_NUMBER={revision}")
    print(f"ANDROID_VERSION_CODE={code}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["check"]:
        check(args[2] if args[1:2] == ["--tag"] else None)
    elif args[:1] == ["env"]:
        env()
    else:
        sys.exit(__doc__)
