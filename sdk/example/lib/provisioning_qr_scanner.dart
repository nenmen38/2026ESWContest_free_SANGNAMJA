import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

final class ProvisioningQrScannerPage extends StatefulWidget {
  const ProvisioningQrScannerPage({super.key});

  @override
  State<ProvisioningQrScannerPage> createState() =>
      _ProvisioningQrScannerPageState();
}

final class _ProvisioningQrScannerPageState
    extends State<ProvisioningQrScannerPage> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _completed = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completed) return;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;
      try {
        final payload = ProvisioningQrPayload.parse(rawValue);
        _completed = true;
        Navigator.of(context).pop(payload);
        return;
      } on FormatException {
        if (mounted) {
          setState(() => _error = 'ESW 장치 등록 QR이 아닙니다.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('장치 QR 스캔')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '카메라를 사용할 수 없습니다.\n${error.errorDetails?.message ?? error.errorCode.name}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Center(
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error ?? '인쇄된 ESW 장치 QR을 사각형 안에 맞추세요.',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
