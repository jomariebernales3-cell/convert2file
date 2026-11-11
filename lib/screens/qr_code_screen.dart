import 'dart:ui' as ui;
import 'dart:io';

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
import 'package:path_provider/path_provider.dart';

import '../widgets/figma_app_chrome.dart';
import '../widgets/report_problem_entry.dart';
import '../theme/app_colors.dart';
import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../services/file_storage.dart';
import 'history_screen.dart';

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
  bool _isSaved = false;
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
      _isSaved = false;
    });
  }

  Future<void> _saveGeneratedQr() async {
    final value = _result;
    if (value == null || _isSaving || _isSaved) return;
    setState(() => _isSaving = true);
    String? temporaryPath;
    try {
      final userId = AuthService().currentUser?.id ??
          await DatabaseHelper.instance.getOrCreateGuestUserId();
      final wifiPayload = value.startsWith('WIFI:');
      final wifiName = RegExp(r'(?:^|;)S:((?:\\.|[^;])*)').firstMatch(value)?.group(1)
          ?.replaceAll(r'\;', ';');
      final qrType = wifiPayload ? 'wifi' : (_isLink ? 'link' : 'text');
      final metadataContent = wifiPayload ? (wifiName ?? 'Wi-Fi network') : value;
      final existing = await DatabaseHelper.instance.findQrOutputByContent(
        userId: userId,
        content: metadataContent,
      );
      if (existing != null) {
        if (mounted) {
          setState(() => _isSaved = true);
          _showMessage('Already saved');
        }
        return;
      }
      final qrCode = QrCode.fromData(
        data: value,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final painter = QrPainter(
        data: value,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );
      const imageSize = 1024.0;
      final moduleSize = imageSize / (qrCode.moduleCount + 8);
      final quietZone = moduleSize * 4;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.save();
      canvas.translate(quietZone, quietZone);
      painter.paint(canvas, Size(imageSize - quietZone * 2, imageSize - quietZone * 2));
      canvas.restore();
      final image = await recorder.endRecording().toImage(1024, 1024);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not create the QR image.');
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final originalName = 'QR_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
      temporaryPath = '${tempDir.path}${Platform.pathSeparator}convert2file_qr_${now.millisecondsSinceEpoch}.png';
      await File(temporaryPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await FileStorage.saveOutputFile(
        temporaryPath,
        'qr',
        originalName,
        userId: userId,
        metadata: {
          'qr_type': qrType,
          'content': metadataContent,
          'created_at': now.toIso8601String(),
        },
      );
      if (mounted) setState(() => _isSaved = true);

      try {
        var allowed = await Gal.hasAccess(toAlbum: true);
        if (!allowed) allowed = await Gal.requestAccess(toAlbum: true);
        if (!allowed) {
          _showSaveMessage(
            'Saved to Outputs. Photos permission was denied',
            action: 'Open settings',
            onAction: openAppSettings,
          );
        } else {
          await Gal.putImage(temporaryPath, album: 'Convert2File');
          _showSaveMessage(
            'Saved to Photos and Outputs',
            action: 'View',
            onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const HistoryScreen(savedFilesMode: true, initialSection: 'outputs'),
            )),
          );
        }
      } on GalException catch (error) {
        debugPrint('[QR] Photos save failed: $error');
        if (error.type == GalExceptionType.accessDenied) {
          _showSaveMessage(
            'Saved to Outputs. Photos permission was denied',
            action: 'Open settings',
            onAction: openAppSettings,
          );
        } else {
          final reason = switch (error.type) {
            GalExceptionType.notEnoughSpace => 'There is not enough space in Photos.',
            GalExceptionType.notSupportedFormat => 'Photos does not support this image format.',
            _ => 'Photos could not save the image.',
          };
          _showSaveMessage(
            'Saved to Outputs. $reason',
            action: 'View',
            onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const HistoryScreen(savedFilesMode: true, initialSection: 'outputs'),
            )),
          );
        }
      } catch (error) {
        debugPrint('[QR] Photos save failed: $error');
        _showSaveMessage(
          'Saved to Outputs. Photos could not save the image.',
          action: 'View',
          onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const HistoryScreen(savedFilesMode: true, initialSection: 'outputs'),
          )),
        );
      }
    } catch (error) {
      debugPrint('[QR] Output save failed: $error');
      if (mounted) _showMessage('Could not save the QR code to Outputs.', error: true);
    } finally {
      if (temporaryPath != null) {
        try { await File(temporaryPath).delete(); } catch (error) { debugPrint('[QR] Temp cleanup failed: $error'); }
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSaveMessage(String text, {required String action, required VoidCallback onAction}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notification = messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(action),
              ),
              IconButton(
                tooltip: 'Dismiss notification',
                onPressed: messenger.hideCurrentSnackBar,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    ));
    Future<void>.delayed(const Duration(seconds: 5), notification.close);
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
      SnackBar(
        backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
        content: Text(
          value,
          style: error
              ? TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)
              : null,
        ),
      ),
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
      title: 'QR code',
      subtitle: 'Scan, read, and create QR codes',
      selectedIndex: 1,
      showBack: true,
      showProfile: false,
      referenceHeader: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FigmaSegmentControl<int>(
              options: const [
                FigmaSegmentOption(value: 0, label: 'Scan', icon: Icons.qr_code_scanner),
                FigmaSegmentOption(value: 1, label: 'Image', icon: Icons.image_search_outlined),
                FigmaSegmentOption(value: 2, label: 'Create', icon: Icons.qr_code_2),
              ],
              selected: _tab,
              onChanged: _selectTab,
            ),
            const SizedBox(height: 18),
            if (_tab == 0) _buildScanner(),
            if (_tab == 1) _buildImageUpload(),
            if (_tab == 2) _buildCreator(),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResult(),
            ],
            const SizedBox(height: 12),
            ReportProblemEntry(
              area: 'qr_code',
              contextInfo: {
                'action': _tab == 0 ? 'scan' : (_tab == 1 ? 'from image' : 'create'),
                'qr_type': _tab == 2 ? (_isLink ? 'link' : 'QR') : 'scanned QR',
              },
            ),
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
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 300,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: (capture) {
                        if (_handledScan) return;
                        for (final barcode in capture.barcodes) {
                          if (barcode.format == BarcodeFormat.qrCode && barcode.rawValue != null) {
                            _setResult(barcode.rawValue!);
                            break;
                          }
                        }
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.27),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _QrScannerFramePainter(
                          color: FigmaAppColors.primary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Text('Point your camera at a QR code.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
  Widget _buildImageUpload() => FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.image_search_outlined, size: 32, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          const Text('Read QR from image', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Choose an image with one clear QR code. Images without a QR code are rejected.'),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _isReadingImage ? null : _pickQrImage,
            icon: _isReadingImage ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload),
            label: const Text('Choose QR image'),
          ),
        ]),
      );

  Widget _buildCreator() => FigmaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create QR code', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Use a link or plain text. Anyone who scans the code can read it, so don’t use it for secrets.'),
          const SizedBox(height: 14),
          TextField(
            controller: _createController,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(hintText: 'Link or text', alignLabelWithHint: true),
            onChanged: (_) { if (_isGenerated || _isSaved) setState(() { _isSaved = false; _isGenerated = false; _result = null; }); },
          ),
          const SizedBox(height: 12),
          FigmaPrimaryButton(label: 'Create QR code', onPressed: _createQr),
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
                border: Border.all(color: FigmaAppColors.border(context)),
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
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving || _isSaved ? null : _saveGeneratedQr,
                style: ElevatedButton.styleFrom(
                  backgroundColor: FigmaAppColors.primary(context),
                  foregroundColor: FigmaAppColors.primaryText(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: FigmaAppColors.primaryText(context))),
                        const SizedBox(width: 10),
                        const Text('Saving...'),
                      ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_isSaved ? Icons.check_rounded : Icons.save_alt_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(_isSaved ? 'Saved' : 'Save'),
                      ]),
              ),
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

class _QrScannerFramePainter extends CustomPainter {
  final Color color;

  const _QrScannerFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: (size.width - 120).clamp(80.0, size.width - 24).toDouble(),
      height: (size.height - 120).clamp(80.0, size.height - 24).toDouble(),
    );
    const cornerLength = 44.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(frame.left, frame.top + cornerLength)
      ..lineTo(frame.left, frame.top)
      ..lineTo(frame.left + cornerLength, frame.top)
      ..moveTo(frame.right - cornerLength, frame.top)
      ..lineTo(frame.right, frame.top)
      ..lineTo(frame.right, frame.top + cornerLength)
      ..moveTo(frame.left, frame.bottom - cornerLength)
      ..lineTo(frame.left, frame.bottom)
      ..lineTo(frame.left + cornerLength, frame.bottom)
      ..moveTo(frame.right - cornerLength, frame.bottom)
      ..lineTo(frame.right, frame.bottom)
      ..lineTo(frame.right, frame.bottom - cornerLength);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QrScannerFramePainter oldDelegate) =>
      oldDelegate.color != color;
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
