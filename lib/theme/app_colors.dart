import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentInk;
  final Color highlight;
  final Color highlightInk;
  final Color highlightGlow;
  final Color danger;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentInk,
    required this.highlight,
    required this.highlightInk,
    required this.highlightGlow,
    required this.danger,
  });

  static const day = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F6FA),
    surface2: Color(0xFFEAEEF5),
    line: Color(0xFFDDE2EC),
    text: Color(0xFF0B1020),
    muted: Color(0xFF5B667D),
    accent: Color(0xFF0B1020),
    accentInk: Color(0xFFFFFFFF),
    highlight: Color(0xFF0B1020),
    highlightInk: Color(0xFFFFFFFF),
    highlightGlow: Color.fromARGB(46, 0, 0, 0),
    danger: Color(0xFFDC2626),
  );

  static const night = AppColors(
    background: Color(0xFF000000),
    surface: Color(0xFF0B0B0F),
    surface2: Color(0xFF15151B),
    line: Color(0xFF262630),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFA0A6B5),
    accent: Color(0xFFFFFFFF),
    accentInk: Color(0xFF000000),
    highlight: Color(0xFFFFFFFF),
    highlightInk: Color(0xFF000000),
    highlightGlow: Color.fromARGB(46, 255, 255, 255),
    danger: Color(0xFFFCA5A5),
  );

  static const dbz = AppColors(
    background: Color(0xFF060913),
    surface: Color(0xFF0E1322),
    surface2: Color(0xFF151B30),
    line: Color(0xFF232A47),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFF97A3BB),
    accent: Color(0xFF67E8F9),
    accentInk: Color(0xFF04222A),
    highlight: Color(0xFF67E8F9),
    highlightInk: Color(0xFF04222A),
    highlightGlow: Color.fromARGB(71, 103, 232, 249),
    danger: Color(0xFFFCA5A5),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentInk,
    Color? highlight,
    Color? highlightInk,
    Color? highlightGlow,
    Color? danger,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        line: line ?? this.line,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        accentInk: accentInk ?? this.accentInk,
        highlight: highlight ?? this.highlight,
        highlightInk: highlightInk ?? this.highlightInk,
        highlightGlow: highlightGlow ?? this.highlightGlow,
        danger: danger ?? this.danger,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      highlightInk: Color.lerp(highlightInk, other.highlightInk, t)!,
      highlightGlow: Color.lerp(highlightGlow, other.highlightGlow, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
