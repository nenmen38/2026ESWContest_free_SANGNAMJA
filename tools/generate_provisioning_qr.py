#!/usr/bin/env python3
"""Generate print-ready ESP BLE provisioning QR labels."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import sys
from pathlib import Path


SERVICE_NAME_RE = re.compile(r"^PROV-(MOTOR|SENSOR)-[0-9A-F]{4}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate SVG and PNG provisioning QR files without printing the PoP."
    )
    parser.add_argument(
        "--service-name",
        required=True,
        help="advertised BLE name, for example PROV-MOTOR-A1B2",
    )
    parser.add_argument(
        "--pop-env",
        metavar="NAME",
        help="read the PoP from this environment variable instead of prompting",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("provisioning-labels"),
        help="output directory (default: provisioning-labels)",
    )
    return parser.parse_args()


def service_name_from_args(args: argparse.Namespace) -> str:
    service_name = args.service_name.upper()

    if not SERVICE_NAME_RE.fullmatch(service_name):
        raise ValueError(
            "service name must match PROV-MOTOR-XXXX or PROV-SENSOR-XXXX"
        )
    return service_name


def read_pop(environment_name: str | None) -> str:
    if environment_name:
        pop = os.environ.get(environment_name, "")
        if not pop:
            raise ValueError(f"environment variable {environment_name!r} is empty or unset")
    else:
        pop = getpass.getpass("Device PoP (hidden): ")
    if not pop:
        raise ValueError("PoP must not be empty")
    return pop


def main() -> int:
    args = parse_args()
    try:
        import qrcode
        import qrcode.image.svg
        from qrcode.constants import ERROR_CORRECT_M
    except ImportError:
        print(
            'Missing dependency. Run: python -m pip install "qrcode[pil]"',
            file=sys.stderr,
        )
        return 2

    try:
        service_name = service_name_from_args(args)
        pop = read_pop(args.pop_env)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    payload = json.dumps(
        {
            "ver": "v1",
            "name": service_name,
            "pop": pop,
            "transport": "ble",
        },
        separators=(",", ":"),
    )
    qr = qrcode.QRCode(
        error_correction=ERROR_CORRECT_M,
        box_size=12,
        border=4,
    )
    qr.add_data(payload)
    qr.make(fit=True)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stem = service_name.lower()
    png_path = args.output_dir / f"{stem}.png"
    svg_path = args.output_dir / f"{stem}.svg"
    qr.make_image(fill_color="black", back_color="white").save(png_path)
    qr.make_image(image_factory=qrcode.image.svg.SvgPathImage).save(svg_path)

    print(f"Created {png_path}")
    print(f"Created {svg_path} (recommended for printing)")
    print(f"Service name: {service_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
