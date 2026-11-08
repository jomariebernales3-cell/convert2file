import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'pdf_text_reader.dart';

class PdfGraphicRegion {
  final Uint8List png;
  final double left, top, width, height;
  final String kind;
  final String color;

  const PdfGraphicRegion({
    required this.png,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.kind,
    this.color = '404040',
  });
}

class PdfGraphicsExtractor {
  static Future<List<PdfGraphicRegion>> extract({
    required Uint8List pagePng,
    required double pageWidth,
    required double pageHeight,
    required List<PdfTextWordData> words,
    bool includeImages = true,
    bool includeRules = true,
    bool includeUnderline = true,
  }) async {
    final result = await compute<Map<String, Object?>, Map<String, Object?>>(
      _findGraphics,
      <String, Object?>{
        'png': pagePng,
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
        'includeImages': includeImages,
        'includeRules': includeRules,
        'includeUnderline': includeUnderline,
        'words': words.map((word) => <String, Object?>{
          'left': word.left, 'top': word.top, 'width': word.width,
          'height': word.height, 'fontSize': word.fontSize,
          'fontName': word.fontName, 'bold': word.bold, 'italic': word.italic,
          'underline': word.underline,
        }).toList(),
      },
    );
    final styles = (result['styles']! as List).cast<Map>();
    for (var i = 0; i < words.length && i < styles.length; i++) {
      words[i].underline = words[i].underline || styles[i]['underline'] == true;
    }
    return (result['regions']! as List).cast<Map>().map((item) => PdfGraphicRegion(
      png: item['png'] as Uint8List? ?? Uint8List(0),
      left: item['left'] as double,
      top: item['top'] as double,
      width: item['width'] as double,
      height: item['height'] as double,
      kind: item['kind'] as String,
      color: item['color'] as String? ?? '404040',
    )).toList();
  }
}

Map<String, Object?> _findGraphics(Map<String, Object?> input) {
  final pageWidth = input['pageWidth']! as double;
  final pageHeight = input['pageHeight']! as double;
  final words = (input['words']! as List).cast<Map>();
  final includeImages = input['includeImages'] != false;
  final includeRules = input['includeRules'] != false;
  final includeUnderline = input['includeUnderline'] != false;
  final decoded = img.decodePng(input['png']! as Uint8List);
  if (decoded == null || pageWidth <= 0 || pageHeight <= 0) {
    return <String, Object?>{'regions': <Map<String, Object?>>[], 'styles': <Map<String, bool>>[]};
  }

  // Flatten alpha onto white before analysis or cropping. All coordinates use the
  // actual rendered bitmap dimensions, which may differ from nominal DPI.
  final source = img.Image(width: decoded.width, height: decoded.height, numChannels: 3);
  img.fill(source, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(source, decoded);
  final analysis = img.copyResize(source, width: math.max(1, (source.width / 2).round()).toInt());
  final sx = analysis.width / pageWidth;
  final sy = analysis.height / pageHeight;
  final cropSx = source.width / pageWidth;
  final cropSy = source.height / pageHeight;
  final textMask = Uint8List(analysis.width * analysis.height);
  int px(double x, double scale, int limit) => (x * scale).round().clamp(0, limit).toInt();
  for (final word in words) {
    final l = px((word['left'] as double) - 2, sx, analysis.width - 1);
    final t = px((word['top'] as double) - 2, sy, analysis.height - 1);
    final r = px((word['left'] as double) + (word['width'] as double) + 2, sx, analysis.width);
    final b = px((word['top'] as double) + (word['height'] as double) + 2, sy, analysis.height);
    for (var y = t; y < b; y++) {
      textMask.fillRange(y * analysis.width + l, y * analysis.width + r, 1);
    }
  }

  Uint8List cropPng(double left, double top, double width, double height, {bool maskText = false}) {
    final x = px(left, cropSx, source.width - 1);
    final y = px(top, cropSy, source.height - 1);
    final r = px(left + width, cropSx, source.width).clamp(x + 1, source.width).toInt();
    final b = px(top + height, cropSy, source.height).clamp(y + 1, source.height).toInt();
    final crop = img.copyCrop(source, x: x, y: y, width: r - x, height: b - y);
    if (maskText) {
      for (final word in words) {
        final wl = px((word['left'] as double) - left - 3, cropSx, crop.width);
        final wt = px((word['top'] as double) - top - 3, cropSy, crop.height);
        final wr = px((word['left'] as double) + (word['width'] as double) - left + 3, cropSx, crop.width);
        final wb = px((word['top'] as double) + (word['height'] as double) - top + 3, cropSy, crop.height);
        if (wr > wl && wb > wt) {
          var colored = 0;
          for (var y = wt; y < wb; y++) {
            for (var x = wl; x < wr; x++) {
              final c = crop.getPixel(x, y);
              if ((math.max(c.r, math.max(c.g, c.b)) - math.min(c.r, math.min(c.g, c.b))) > 35) colored++;
            }
          }
          // Preserve colored logo artwork that overlaps an extracted word box.
          if (colored > (wr - wl) * (wb - wt) * 0.015) continue;
          img.fillRect(crop, x1: wl, y1: wt, x2: wr - 1, y2: wb - 1,
              color: img.ColorRgb8(255, 255, 255));
        }
      }
      final speckMask = Uint8List(crop.width * crop.height);
      final components = <({List<int> pixels, int left, int top, int right, int bottom})>[];
      for (var start = 0; start < speckMask.length; start++) {
        if (speckMask[start] != 0) continue;
        final c = crop.getPixel(start % crop.width, start ~/ crop.width);
        if (c.r >= 215 && c.g >= 215 && c.b >= 215) { speckMask[start] = 1; continue; }
        final queue = <int>[start];
        speckMask[start] = 1;
        var cursor = 0, minX = crop.width, minY = crop.height, maxX = 0, maxY = 0;
        while (cursor < queue.length && queue.length < 12000) {
          final p = queue[cursor++], x = p % crop.width, y = p ~/ crop.width;
          minX = math.min(minX, x); minY = math.min(minY, y);
          maxX = math.max(maxX, x); maxY = math.max(maxY, y);
          for (var dy = -1; dy <= 1; dy++) { for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= crop.width || ny >= crop.height) continue;
            final next = ny * crop.width + nx;
            if (speckMask[next] != 0) continue;
            speckMask[next] = 1;
            final pixel = crop.getPixel(nx, ny);
            if (pixel.r < 215 || pixel.g < 215 || pixel.b < 215) queue.add(next);
          }}
        }
        components.add((pixels: queue, left: minX, top: minY, right: maxX, bottom: maxY));
      }
      final speckW = 3 * cropSx, speckH = 3 * cropSy, near = 5 * math.max(cropSx, cropSy);
      for (final component in components) {
        if (component.right - component.left >= speckW || component.bottom - component.top >= speckH) continue;
        final nearbyGraphic = components.any((other) {
          if (identical(component, other)) return false;
          final dx = math.max(0, math.max(other.left - component.right, component.left - other.right));
          final dy = math.max(0, math.max(other.top - component.bottom, component.top - other.bottom));
          final groupWidth = math.max(other.right, component.right) - math.min(other.left, component.left);
          final groupHeight = math.max(other.bottom, component.bottom) - math.min(other.top, component.top);
          return math.sqrt(dx * dx + dy * dy) <= near &&
              (groupWidth >= speckW || groupHeight >= speckH);
        });
        if (!nearbyGraphic) {
          for (final p in component.pixels) {
            crop.setPixel(p % crop.width, p ~/ crop.width, img.ColorRgb8(255, 255, 255));
          }
        }
      }
    }
    return Uint8List.fromList(img.encodePng(crop));
  }
  bool hasInk(Uint8List png) {
    final image = img.decodePng(png);
    if (image == null) return false;
    final first = image.getPixel(0, 0);
    var varied = false, ink = false;
    for (final pixel in image) {
      if ((pixel.r - first.r).abs() > 2 || (pixel.g - first.g).abs() > 2 ||
          (pixel.b - first.b).abs() > 2) varied = true;
      if (pixel.r < 245 || pixel.g < 245 || pixel.b < 245) ink = true;
      if (varied && ink) return true;
    }
    return false;
  }
  String colorAt(int x, int y) {
    final c = source.getPixel(x.clamp(0, source.width - 1).toInt(), y.clamp(0, source.height - 1).toInt());
    String hex(num n) => n.round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '${hex(c.r)}${hex(c.g)}${hex(c.b)}'.toUpperCase();
  }

  final regions = <Map<String, Object?>>[];
  final bandHeight = pageHeight * 0.2;
  void addBand(String kind, double top) {
    final png = cropPng(0, top, pageWidth, bandHeight, maskText: true);
    if (hasInk(png)) {
      regions.add(<String, Object?>{
        'png': png, 'left': 0.0, 'top': top, 'width': pageWidth,
        'height': bandHeight, 'kind': kind, 'color': 'FFFFFF',
      });
    }
  }
  if (includeImages) {
    addBand('headerBand', 0);
    addBand('footerBand', pageHeight - bandHeight);
  }

  final styles = <Map<String, bool>>[];
  for (final word in words) {
    var underline = false;
    if (includeUnderline) {
      final left = word['left'] as double, top = word['top'] as double;
      final wordWidth = word['width'] as double, wordHeight = word['height'] as double;
      final lineY = px(top + wordHeight, sy, analysis.height - 1);
      final x1 = px(left, sx, analysis.width - 1), x2 = px(left + wordWidth, sx, analysis.width);
      for (var y = lineY; y <= px(top + wordHeight + 2.5, sy, analysis.height - 1); y++) {
        var run = 0;
        for (var x = x1; x < x2; x++) {
          final c = analysis.getPixel(x, y);
          if ((c.r + c.g + c.b) / 3 < 130) {
            run++;
          } else if (run >= (x2 - x1) * 0.55) {
            underline = true;
            run = 0;
          } else {
            run = 0;
          }
        }
        if (run >= (x2 - x1) * 0.55) underline = true;
      }
    }
    styles.add(<String, bool>{
      'bold': false,
      'italic': false,
      'underline': word['underline'] == true || underline,
    });
  }
  final visited = Uint8List(analysis.width * analysis.height);
  final textLeft = words.isEmpty ? 0.0 : words.map((w) => w['left'] as double).reduce((a, b) => math.min(a, b).toDouble());
  final textRight = words.isEmpty ? pageWidth : words.map((w) => (w['left'] as double) + (w['width'] as double)).reduce((a, b) => math.max(a, b).toDouble());
  for (var start = 0; start < visited.length; start++) {
    if (visited[start] != 0 || textMask[start] != 0) continue;
    final startY = start ~/ analysis.width;
    final startPtY = startY / sy;
    final p = analysis.getPixel(start % analysis.width, startY);
    if (p.r >= 242 && p.g >= 242 && p.b >= 242) { visited[start] = 1; continue; }
    final queue = <int>[start];
    visited[start] = 1;
    var cursor = 0, minX = analysis.width, minY = analysis.height, maxX = 0, maxY = 0;
    while (cursor < queue.length && cursor < 180000) {
      final current = queue[cursor++], x = current % analysis.width, y = current ~/ analysis.width;
      minX = math.min(minX, x); minY = math.min(minY, y); maxX = math.max(maxX, x); maxY = math.max(maxY, y);
      for (var dy = -1; dy <= 1; dy++) { for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= analysis.width || ny >= analysis.height) continue;
        final next = ny * analysis.width + nx;
        if (visited[next] != 0 || textMask[next] != 0) continue;
        visited[next] = 1;
        final c = analysis.getPixel(nx, ny);
        if (c.r < 242 || c.g < 242 || c.b < 242) queue.add(next);
      }}
    }
    if (maxX <= minX || maxY <= minY) continue;
    final left = minX / sx, top = minY / sy;
    final w = (maxX - minX + 1) / sx, h = (maxY - minY + 1) / sy;
    final thin = h <= 2.5;
    final aboveWords = words.where((word) {
      final wordBottom = (word['top'] as double) + (word['height'] as double);
      return wordBottom <= top + 2 && top - wordBottom <=
          math.max(14.0, (word['fontSize'] as double) * 1.5);
    }).toList();
    final aboveLeft = aboveWords.isEmpty
        ? left
        : aboveWords.map((word) => word['left'] as double).reduce((a, b) => math.min(a, b).toDouble());
    final aboveRight = aboveWords.isEmpty
        ? left + w
        : aboveWords.map((word) => (word['left'] as double) + (word['width'] as double)).reduce((a, b) => math.max(a, b).toDouble());
    final covered = math.max(0.0, math.min(left + w, aboveRight) - math.max(left, aboveLeft));
    final extendsBeyondText = w > 0 && (w - covered) / w > 0.30;
    final reachesMargin = left <= textLeft + 3 || left + w >= textRight - 3;
    final rule = thin && (extendsBeyondText || reachesMargin);
    if (rule && includeRules) {
      for (var wordIndex = 0; wordIndex < words.length && wordIndex < styles.length; wordIndex++) {
        final word = words[wordIndex];
        final wordBottom = (word['top'] as double) + (word['height'] as double);
        final overlaps = math.min(left + w, (word['left'] as double) + (word['width'] as double)) -
            math.max(left, word['left'] as double);
        if (wordBottom <= top + 2 && top - wordBottom <= math.max(14.0, (word['fontSize'] as double) * 1.5) && overlaps > 0) {
          styles[wordIndex]['underline'] = false;
        }
      }
      regions.add(<String, Object?>{
        'left': left, 'top': top, 'width': w, 'height': h, 'kind': 'rule',
        'png': Uint8List(0), 'color': colorAt((minX * source.width / analysis.width).round(),
            (minY * source.height / analysis.height).round()),
      });
      continue;
    }
    if (!includeImages || top < bandHeight || top >= pageHeight - bandHeight) continue;
    if (w * h > pageWidth * pageHeight * 0.25) continue;
    final overlaps = words.where((word) {
      final ox = math.min(left + w, (word['left'] as double) + (word['width'] as double)) - math.max(left, word['left'] as double);
      final oy = math.min(top + h, (word['top'] as double) + (word['height'] as double)) - math.max(top, word['top'] as double);
      return ox > 0 && oy > 0;
    }).length;
    if (overlaps > 1) continue;
    regions.add(<String, Object?>{
      'left': left, 'top': top, 'width': w, 'height': h, 'kind': 'image',
      'png': cropPng(left, top, w, h), 'color': 'FFFFFF',
    });
  }

  final images = regions.where((r) => r['kind'] == 'image').toList();
  final merged = <Map<String, Object?>>[];
  for (final region in images) {
    var candidate = region;
    for (var i = 0; i < merged.length;) {
      final old = merged[i];
      final l = candidate['left'] as double, t = candidate['top'] as double;
      final r = l + (candidate['width'] as double), b = t + (candidate['height'] as double);
      final ol = old['left'] as double, ot = old['top'] as double;
      final or = ol + (old['width'] as double), ob = ot + (old['height'] as double);
      final gapX = math.max(0.0, math.max(ol - r, l - or));
      final gapY = math.max(0.0, math.max(ot - b, t - ob));
      if (gapX <= 8 && gapY <= 8) {
        final nl = math.min(l, ol).toDouble(), nt = math.min(t, ot).toDouble();
        final nr = math.max(r, or).toDouble(), nb = math.max(b, ob).toDouble();
        candidate = <String, Object?>{'left': nl, 'top': nt, 'width': nr - nl,
          'height': nb - nt, 'kind': 'image', 'png': cropPng(nl, nt, nr - nl, nb - nt), 'color': 'FFFFFF'};
        merged.removeAt(i);
        i = 0;
      } else { i++; }
    }
    merged.add(candidate);
  }
  while (merged.length > 15) {
    merged.sort((a, b) => ((a['width'] as double) * (a['height'] as double))
        .compareTo((b['width'] as double) * (b['height'] as double)));
    final small = merged.removeAt(0);
    var nearest = 0, best = double.infinity;
    for (var i = 0; i < merged.length; i++) {
      final d = ((small['left'] as double) - (merged[i]['left'] as double)).abs() +
          ((small['top'] as double) - (merged[i]['top'] as double)).abs();
      if (d < best) { best = d; nearest = i; }
    }
    final other = merged.removeAt(nearest);
    final l = math.min(small['left'] as double, other['left'] as double).toDouble();
    final t = math.min(small['top'] as double, other['top'] as double).toDouble();
    final r = math.max((small['left'] as double) + (small['width'] as double), (other['left'] as double) + (other['width'] as double)).toDouble();
    final b = math.max((small['top'] as double) + (small['height'] as double), (other['top'] as double) + (other['height'] as double)).toDouble();
    merged.add(<String, Object?>{'left': l, 'top': t, 'width': r-l, 'height': b-t,
      'kind': 'image', 'png': cropPng(l, t, r-l, b-t), 'color': 'FFFFFF'});
  }
  regions.removeWhere((r) => r['kind'] == 'image');
  regions.addAll(merged.where((r) {
    final left = r['left'] as double, top = r['top'] as double;
    final right = left + (r['width'] as double), bottom = top + (r['height'] as double);
    if ((r['width'] as double) < 3 || (r['height'] as double) < 3 ||
        !hasInk(r['png'] as Uint8List)) return false;
    var wordArea = 0.0;
    for (final word in words) {
      final overlapX = math.max(0.0, math.min(right, (word['left'] as double) + (word['width'] as double)) - math.max(left, word['left'] as double));
      final overlapY = math.max(0.0, math.min(bottom, (word['top'] as double) + (word['height'] as double)) - math.max(top, word['top'] as double));
      wordArea += (overlapX * overlapY).toDouble();
    }
    return wordArea / math.max(1.0, (right - left) * (bottom - top)) <= 0.25;
  }));
  return <String, Object?>{'regions': regions, 'styles': styles};
}
