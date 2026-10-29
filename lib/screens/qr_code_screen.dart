import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:gal/gal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/figma_app_chrome.dart';

class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({super.key});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _createController = TextEditingController();
  final _resultController = TextEditingController();
  int _tab = 0;
  bool _handledScan = false;
  bool _isReadingImage = false;
  bool _isSaving = false;
  bool _isGenerated = false;
  bool _isCameraReady = false;
  bool _isCheckingCamera = true;
  String? _result;

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  @override
  void dispose() {
    _scanner.dispose();
    _createController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  void _setResult(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    setState(() {
      _result = cleaned;
      _resultController.text = cleaned;
      _handledScan = true;
      _isGenerated = false;
    });
    _scanner.stop();
  }

  Future<void> _selectTab(int tab) async {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _handledScan = false;
      _result = null;
      _resultController.clear();
      _isGenerated = false;
    });
    if (tab == 0) {
      await _prepareCamera();
      if (_isCameraReady) await _scanner.start();
    } else {
      await _scanner.stop();
    }
  }

  Future<void> _prepareCamera() async {
    if (mounted) setState(() => _isCheckingCamera = true);
    final prefs = await SharedPreferences.getInstance();
    const requestKey = 'qr_camera_permission_requested_v1';
    var status = await Permission.camera.status;
    if (!status.isGranted && prefs.getBool(requestKey) != true) {
      await prefs.setBool(requestKey, true);
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _isCameraReady = status.isGranted;
      _isCheckingCamera = false;
    });
  }

  Future<void> _openCameraSettings() async {
    await openAppSettings();
    if (mounted) await _prepareCamera();
  }

  Future<void> _pickQrImage() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null || path.isEmpty) return;
    setState(() => _isReadingImage = true);
    try {
      final value = await _readQrFromImage(path);
      if (value.isEmpty) {
        _showMessage(
          'No QR code detected. For long-text QR codes, use the original PNG or a sharp, uncropped image.',
          error: true,
        );
        return;
      }
      _setResult(value);
    } catch (e) {
      _showMessage('Could not read this image: $e', error: true);
    } finally {
      if (mounted) setState(() => _isReadingImage = false);
    }
  }

  Future<String> _readQrFromImage(String path) async {
    // ML Kit is fast for ordinary QR images.
    try {
      final capture = await _scanner.analyzeImage(path);
      for (final item in capture?.barcodes ?? const <Barcode>[]) {
        if (item.format == BarcodeFormat.qrCode) {
          final value = item.rawValue?.trim() ?? '';
          if (value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // A second decoder below handles images ML Kit cannot read.
    }

    // Dense codes created from long paragraphs have tiny modules. ZXing-C++
    // retries with rotation, inversion, and a larger source image.
    final fallback = await zxing.zx.readBarcodeImagePathString(
      path,
      zxing.DecodeParams(
        format: zxing.Format.qrCode,
        tryHarder: true,
        tryRotate: true,
        tryInverted: true,
        maxSize: 4096,
      ),
    );
    return fallback.isValid ? fallback.text?.trim() ?? '' : '';
  }

  void _createQr() {
    final value = _createController.text.trim();
    if (value.isEmpty) {
      _showMessage('Enter a link or text first.', error: true);
      return;
    }
    setState(() {
      _result = value;
      _isGenerated = true;
    });
  }

  Future<void> _saveGeneratedQr() async {
    final value = _result;
    if (value == null) return;
    setState(() => _isSaving = true);
    try {
      final painter = QrPainter(
        data: value,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      painter.paint(canvas, const Size(1024, 1024));
      final image = await recorder.endRecording().toImage(1024, 1024);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not create the QR image.');
      await Gal.putImageBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        name: 'convert2file_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (mounted) _showMessage('QR code saved to your gallery.');
    } catch (e) {
      if (mounted) _showMessage('Could not save QR image: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _copyResult() async {
    final value = _result;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _showMessage('QR content copied.');
  }

  Future<void> _openLink() async {
    final value = _result;
    if (value == null) return;
    final opened = await launchUrl(
      Uri.parse(value),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Could not open this link.', error: true);
    }
  }

  void _showMessage(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), backgroundColor: error ? Colors.red : null),
    );
  }

  bool get _isLink {
    final uri = Uri.tryParse(_result ?? '');
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  _QrInterpretation get _interpretation => _QrInterpretation.fromRaw(_result!);

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: 'QR Code',
      subtitle: 'Scan, read, and create QR codes',
      selectedIndex: 1,
      showBack: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 0, icon: const Icon(Icons.qr_code_scanner), label: constraints.maxWidth < 350 ? null : const Text('Scan')),
                    ButtonSegment(value: 1, icon: const Icon(Icons.image_search_outlined), label: constraints.maxWidth < 350 ? null : const Text('Upload')),
                    ButtonSegment(value: 2, icon: const Icon(Icons.qr_code_2), label: constraints.maxWidth < 350 ? null : const Text('Create')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) => _selectTab(value.first),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_tab == 0) _buildScanner(),
            if (_tab == 1) _buildImageUpload(),
            if (_tab == 2) _buildCreator(),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResult(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    if (_isCheckingCamera) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (!_isCameraReady) {
      return FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.camera_alt_outlined, size: 34),
          const SizedBox(height: 10),
          const Text('Camera permission is off', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Camera permission is requested only once. Enable it in Android Settings to scan QR codes.'),
          const SizedBox(height: 14),
          ElevatedButton.icon(onPressed: _openCameraSettings, icon: const Icon(Icons.settings_outlined), label: const Text('Open Settings')),
        ]),
      );
    }
    return FigmaCard(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  if (_handledScan) return;
                  for (final barcode in capture.barcodes) {
                    if (barcode.format == BarcodeFormat.qrCode &&
                        barcode.rawValue != null) {
                      _setResult(barcode.rawValue!);
                      break;
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Point your camera at a QR code.', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
  }

  Widget _buildImageUpload() => FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.image_search_outlined, size: 34),
          const SizedBox(height: 10),
          const Text('Read QR from Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Choose an image containing one clear QR code. Images without a QR code are rejected.'),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _isReadingImage ? null : _pickQrImage,
            icon: _isReadingImage ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload),
            label: const Text('Choose QR Image'),
          ),
        ]),
      );

  Widget _buildCreator() => FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Use a link or plain text. QR codes are readable by anyone who scans them—do not use this for unencrypted secrets.'),
          const SizedBox(height: 14),
          TextField(
            controller: _createController,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(labelText: 'Link or text', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          FigmaPrimaryButton(label: 'Create QR Code', icon: Icons.qr_code_2, onPressed: _createQr),
        ]),
      );

  Widget _buildResult() => FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _isGenerated ? 'Generated QR Code' : 'Scan Result',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: QrImageView(
                data: _result!,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isGenerated)
            FigmaPrimaryButton(
              label: _isSaving ? 'Saving QR...' : 'Save QR as PNG',
              icon: Icons.download_rounded,
              onPressed: _isSaving ? null : _saveGeneratedQr,
            )
          else ...[
            TextField(
              controller: _resultController,
              readOnly: true,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Original QR content'),
            ),
            const SizedBox(height: 10),
            _buildInterpretation(),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _copyResult, icon: const Icon(Icons.copy_outlined), label: const Text('Copy'))),
              if (_isLink) ...[const SizedBox(width: 10), Expanded(child: ElevatedButton.icon(onPressed: _openLink, icon: const Icon(Icons.open_in_new), label: const Text('Open link')))],
            ]),
          ],
        ]),
      );

  Widget _buildInterpretation() {
    final item = _interpretation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FigmaAppColors.fill(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FigmaAppColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: FigmaAppColors.primary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Readable version',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(item.description,
                    style: TextStyle(color: FigmaAppColors.subtext(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrInterpretation {
  final String title;
  final String description;
  final IconData icon;

  const _QrInterpretation(this.title, this.description, this.icon);

  factory _QrInterpretation.fromRaw(String raw) {
    final value = raw.trim();
    final lower = value.toLowerCase();
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
      return _QrInterpretation('Website link', uri.toString(), Icons.link_rounded);
    }
    if (lower.startsWith('wifi:')) {
      final name = _field(value.substring(5), 'S') ?? 'Unnamed network';
      final security = _field(value.substring(5), 'T') ?? 'Unknown security';
      return _QrInterpretation('Wi-Fi network', 'Network: $name • Security: $security', Icons.wifi_rounded);
    }
    if (lower.startsWith('mailto:')) {
      return _QrInterpretation('Email address', value.substring(7), Icons.email_outlined);
    }
    if (lower.startsWith('tel:')) {
      return _QrInterpretation('Phone number', value.substring(4), Icons.phone_outlined);
    }
    if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
      final data = value.substring(value.indexOf(':') + 1);
      return _QrInterpretation('Text message', data, Icons.sms_outlined);
    }
    if (lower.startsWith('geo:')) {
      return _QrInterpretation('Location coordinates', value.substring(4), Icons.location_on_outlined);
    }
    if (lower.contains('begin:vcard')) {
      final name = _vCardValue(value, 'FN') ?? _vCardValue(value, 'N') ?? 'Contact card';
      final phone = _vCardValue(value, 'TEL');
      final email = _vCardValue(value, 'EMAIL');
      final details = [if (phone != null) phone, if (email != null) email].join(' • ');
      return _QrInterpretation('Contact: $name', details.isEmpty ? 'Contact information included.' : details, Icons.person_outline);
    }
    if (lower.contains('begin:vevent')) {
      final title = _vCardValue(value, 'SUMMARY') ?? 'Calendar event';
      return _QrInterpretation('Calendar event', title, Icons.event_outlined);
    }
    if (value.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
      return const _QrInterpretation('App or protected data', 'This QR contains non-text data that may only work in its original app.', Icons.lock_outline);
    }
    return _QrInterpretation('Text content', value, Icons.notes_outlined);
  }

  static String? _field(String data, String key) {
    final match = RegExp('(?:^|;)$key:([^;]*)', caseSensitive: false).firstMatch(data);
    return match?.group(1)?.replaceAll(r'\\;', ';').trim();
  }

  static String? _vCardValue(String data, String key) {
    final match = RegExp('^$key(?:;[^:]*)?:(.+)\$', multiLine: true, caseSensitive: false).firstMatch(data);
    return match?.group(1)?.trim();
  }
}
