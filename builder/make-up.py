#!/usr/bin/env python3
"""Build an experimental Mazda-style .up package for OpenCMU.

The updater expects a ZIP archive containing main_instructions.ini and
versions.ini. This builder only writes those instructions; the actual payload
stays on the USB root (bootstrap.sh, install.sh, tweaks/).

WARNING: updater signature checks and instruction semantics are unverified.
Do not use this on a car. Bench unit only.
"""

import argparse
import random
import sys
import zipfile
import zlib
from pathlib import Path

MAIN_TEMPLATE = """[Settings]
PackageID        = {package_id}
CompressionType  = NONE
TotalStepsCount  = 1

[Instructions]
Count = 1
1 = Execute, "bootstrap", "execute.ini", 1

[Instructions_Ext]
Count = 1
1 = Execute, "bootstrap", "execute.ini", 1

[DataStorage]
Count = 5
UPType = "Reinstall"
SubUPType = "Mass"
ReTransmit = "1"
NewPackage = "1"
CMUBoardType = "3"
"""

VERSIONS_TEMPLATE = """[Settings]
CheckCompatibility = 1,"Compat_Section"
Labels = 2,"JCI_SW_VER","DisplayVersion"

[Compat_Section]
Count = 1
1 = CheckLabel,"JCI_SW_VER",1,"[>='{platform}_{min_firmware}']"

[JCI_SW_VER]
LabelName = "JCI_SW_VER"
LoadLocation = Custom

[DisplayVersion]
LabelName = "DisplayVersion"
LoadLocation = UP
LabelValue = "{display_version}"
"""


def build_zip(out_path: Path, main_ini: str, versions_ini: str) -> None:
    stamp = (1980, 1, 1, 0, 0, 0)
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_STORED) as zf:
        for name, text in (
            ("main_instructions.ini", main_ini),
            ("versions.ini", versions_ini),
        ):
            info = zipfile.ZipInfo(name, date_time=stamp)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            zf.writestr(info, text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build an experimental OpenCMU .up file")
    parser.add_argument("--out", default="dist/opencmu.up", help="output path")
    parser.add_argument("--min-firmware", default="74.00.324", help="minimum JCI_SW_VER")
    parser.add_argument("--display-version", default="74.00.324", help="DisplayVersion label")
    parser.add_argument("--platform", default="MAZ_CMU-140", help="platform prefix for the compatibility label")
    parser.add_argument("--package-id", type=int, default=None, help="numeric package id")
    parser.add_argument("--random-id", action="store_true", help="use a random package id instead of the deterministic default")
    parser.add_argument("--force", action="store_true", help="overwrite an existing output file")
    args = parser.parse_args()

    out = Path(args.out)
    if out.exists() and not args.force:
        print(f"refusing to overwrite {out} (use --force)", file=sys.stderr)
        return 1

    versions_ini = VERSIONS_TEMPLATE.format(
        platform=args.platform,
        min_firmware=args.min_firmware,
        display_version=args.display_version,
    )

    if args.package_id is not None:
        package_id = args.package_id
    elif args.random_id:
        package_id = random.randint(10**9, 10**10 - 1)
    else:
        # Deterministic by default so repeated builds are byte-identical.
        package_id = (zlib.crc32(versions_ini.encode("utf-8")) % 10**10) or 1

    main_ini = MAIN_TEMPLATE.format(package_id=package_id)

    out.parent.mkdir(parents=True, exist_ok=True)
    build_zip(out, main_ini, versions_ini)

    print(f"built {out} (experimental; bench testing only)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
