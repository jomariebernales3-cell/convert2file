import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class PdfDetectedTable {
  final double left, top, right, bottom;
  final List<double> columns, rows;
  final List<List<String?>> fills;
  final List<List<bool>> verticalEdges, horizontalEdges;

  const PdfDetectedTable({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.columns,
    required this.rows,
    required this.fills,
    required this.verticalEdges,
    required this.horizontalEdges,
  });

  Map<String, Object?> toMap() => <String, Object?>{
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'columns': columns,
        'rows': rows,
        'fills': fills,
        'verticalEdges': verticalEdges,
        'horizontalEdges': horizontalEdges,
      };

  factory PdfDetectedTable.fromMap(Map map) => PdfDetectedTable(
        left: map['left'] as double,
        top: map['top'] as double,
        right: map['right'] as double,
        bottom: map['bottom'] as double,
        columns: (map['columns'] as List).cast<double>(),
        rows: (map['rows'] as List).cast<double>(),
        fills: (map['fills'] as List)
            .map((row) => (row as List).cast<String?>())
            .toList(),
        verticalEdges: (map['verticalEdges'] as List)
            .map((row) => (row as List).cast<bool>())
            .toList(),
        horizontalEdges: (map['horizontalEdges'] as List)
            .map((row) => (row as List).cast<bool>())
            .toList(),
      );
}

class PdfTableDetector {
  static Future<List<PdfDetectedTable>> detect({
    required Uint8List pagePng,
    required double pageWidth,
    required double pageHeight,
  }) async {
    final result = await compute<Map<String, Object?>, List<Map>>(
      _detect,
      <String, Object?>{
        'png': pagePng,
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
      },
    );
    return result.map(PdfDetectedTable.fromMap).toList();
  }
}

List<Map> _detect(Map<String, Object?> input) {
  final decoded = img.decodePng(input['png']! as Uint8List);
  if (decoded == null) return <Map>[];
  final pageWidth = input['pageWidth']! as double;
  final pageHeight = input['pageHeight']! as double;
  final analysis = img.copyResize(
    decoded,
    width: math.max(1, (pageWidth * 100 / 72).round()).toInt(),
    height: math.max(1, (pageHeight * 100 / 72).round()).toInt(),
    interpolation: img.Interpolation.average,
  );
  final sx = analysis.width / pageWidth;
  final sy = analysis.height / pageHeight;
  final minLength = math.max(20.0, 20.0 * math.min(sx, sy)).round();
  bool dark(int x, int y) {
    final p = analysis.getPixel(x, y);
    return (p.r * 0.299 + p.g * 0.587 + p.b * 0.114) < 205;
  }

  List<_Segment> scan({required bool horizontal}) {
    final outer = horizontal ? analysis.height : analysis.width;
    final inner = horizontal ? analysis.width : analysis.height;
    final segments = <_Segment>[];
    for (var fixed = 0; fixed < outer; fixed++) {
      var start = -1;
      for (var moving = 0; moving <= inner; moving++) {
        final ink = moving < inner &&
            (horizontal ? dark(moving, fixed) : dark(fixed, moving));
        if (ink && start < 0) start = moving;
        if (!ink && start >= 0) {
          if (moving - start >= minLength) {
            segments.add(horizontal
                ? _Segment(fixed.toDouble(), start.toDouble(), moving.toDouble())
                : _Segment(fixed.toDouble(), start.toDouble(), moving.toDouble()));
          }
          start = -1;
        }
      }
    }
    return segments;
  }

  List<_Segment> mergeRows(List<_Segment> source) {
    source.sort((a, b) => a.position.compareTo(b.position));
    final merged = <_Segment>[];
    for (final segment in source) {
      if (merged.isNotEmpty && (segment.position - merged.last.position).abs() <= 2) {
        final old = merged.removeLast();
        merged.add(_Segment(
          (old.position + segment.position) / 2,
          math.min(old.start, segment.start).toDouble(),
          math.max(old.end, segment.end).toDouble(),
        ));
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }

  final horizontals = mergeRows(scan(horizontal: true));
  final verticals = mergeRows(scan(horizontal: false));
  final hCount = horizontals.length;
  final vCount = verticals.length;
  final parent = List<int>.generate(hCount + vCount, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }
  void join(int a, int b) {
    final ra = root(a), rb = root(b);
    if (ra != rb) parent[rb] = ra;
  }

  for (var hi = 0; hi < hCount; hi++) {
    final h = horizontals[hi];
    for (var vi = 0; vi < vCount; vi++) {
      final v = verticals[vi];
      if (v.position >= h.start - 2 && v.position <= h.end + 2 &&
          h.position >= v.start - 2 && h.position <= v.end + 2) {
        join(hi, hCount + vi);
      }
    }
  }
  final components = <int, List<int>>{};
  for (var i = 0; i < parent.length; i++) {
    components.putIfAbsent(root(i), () => <int>[]).add(i);
  }
  final tables = <Map>[];
  String? cellFill(double left, double top, double right, double bottom) {
    final insetX = math.max(2.0, (right - left) * 0.06);
    final insetY = math.max(2.0, (bottom - top) * 0.12);
    final points = <(double, double)>[
      (left + insetX, top + insetY),
      (right - insetX, top + insetY),
      (left + insetX, bottom - insetY),
      (right - insetX, bottom - insetY),
    ];
    var r = 0.0, g = 0.0, b = 0.0, count = 0;
    for (final (x, y) in points) {
      final px = (x / pageWidth * decoded.width).round().clamp(0, decoded.width - 1);
      final py = (y / pageHeight * decoded.height).round().clamp(0, decoded.height - 1);
      final color = decoded.getPixel(px, py);
      r += color.r;
      g += color.g;
      b += color.b;
      count++;
    }
    r /= count; g /= count; b /= count;
    if (r > 248 && g > 248 && b > 248) return null;
    String hex(double value) => value.round().toRadixString(16).padLeft(2, '0');
    return '${hex(r)}${hex(g)}${hex(b)}'.toUpperCase();
  }
  bool edgePresent(double x, double y, {required bool vertical}) {
    final centerX = (x / pageWidth * analysis.width).round();
    final centerY = (y / pageHeight * analysis.height).round();
    var hits = 0;
    for (var step = -2; step <= 2; step++) {
      final px = (centerX + (vertical ? step : 0)).clamp(0, analysis.width - 1).toInt();
      final py = (centerY + (vertical ? 0 : step)).clamp(0, analysis.height - 1).toInt();
      final pixel = analysis.getPixel(px, py);
      if (pixel.r < 235 || pixel.g < 235 || pixel.b < 235) hits++;
    }
    return hits >= 2;
  }
  for (final component in components.values) {
    final hs = component.where((i) => i < hCount).map((i) => horizontals[i]).toList();
    final vs = component.where((i) => i >= hCount).map((i) => verticals[i - hCount]).toList();
    final ys = hs.map((line) => line.position).toList()..sort();
    final xs = vs.map((line) => line.position).toList()..sort();
    if (ys.length < 3 || xs.length < 3) continue;
    final left = xs.first / sx, right = xs.last / sx;
    final top = ys.first / sy, bottom = ys.last / sy;
    if (right - left < 40 || bottom - top < 30) continue;
    final fills = <List<String?>>[];
    for (var row = 0; row + 1 < ys.length; row++) {
      final rowFills = <String?>[];
      for (var col = 0; col + 1 < xs.length; col++) {
        rowFills.add(cellFill(xs[col] / sx, ys[row] / sy,
            xs[col + 1] / sx, ys[row + 1] / sy));
      }
      fills.add(rowFills);
    }
    final verticalEdges = <List<bool>>[];
    final horizontalEdges = <List<bool>>[];
    for (var row = 0; row + 1 < ys.length; row++) {
      final y = (ys[row] + ys[row + 1]) / 2 / sy;
      verticalEdges.add(List<bool>.generate(xs.length, (boundary) =>
          edgePresent(xs[boundary] / sx, y, vertical: true)));
    }
    for (var boundary = 0; boundary < ys.length; boundary++) {
      final rowEdges = <bool>[];
      for (var col = 0; col + 1 < xs.length; col++) {
        final x = (xs[col] + xs[col + 1]) / 2 / sx;
        rowEdges.add(edgePresent(x, ys[boundary] / sy, vertical: false));
      }
      horizontalEdges.add(rowEdges);
    }
    tables.add(<String, Object?>{
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'columns': xs.map((x) => x / sx).toList(),
      'rows': ys.map((y) => y / sy).toList(),
      'fills': fills,
      'verticalEdges': verticalEdges,
      'horizontalEdges': horizontalEdges,
    });
  }
  tables.sort((a, b) => (a['top'] as double).compareTo(b['top'] as double));
  return tables;
}

class _Segment {
  final double position, start, end;
  const _Segment(this.position, this.start, this.end);
}
