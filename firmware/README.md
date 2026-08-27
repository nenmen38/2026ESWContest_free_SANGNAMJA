# 2026 ESW Contest Firmware

This workspace contains the ESP32-C3 motor firmware (`main`), air-quality
firmware (`sensor`), shared embedded components (`common`), and the high-level
Flutter device SDK (`sdk`).

Flutter applications should start with [`sdk/README.md`](sdk/README.md). The
SDK exposes device operations and typed readings without requiring application
developers to understand the internal MQTT contract.

# Provisioning QR labels

Generate a device-specific PNG and print-ready SVG from the repository root:

```powershell
python -m pip install "qrcode[pil]"
python .\tools\generate_provisioning_qr.py --service-name PROV-MOTOR-A1B2
```

The tool prompts for the device PoP without echoing it. Pass the exact BLE
service name printed by the firmware log or shown by a BLE scan.

Outputs are written under the ignored `provisioning-labels/` directory. Use
the SVG for printing and do not commit generated labels because the QR embeds
the device PoP.
