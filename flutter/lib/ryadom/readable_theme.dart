import 'package:flutter/material.dart';

ThemeData ryadomReadableTheme(ThemeData base) {
  final ink = base.brightness == Brightness.dark
      ? const Color(0xffedf2f8)
      : const Color(0xff25354b);
  TextStyle body(TextStyle? style, double size) =>
      (style ?? const TextStyle()).copyWith(
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const ['NotoSans', 'Arial'],
          fontSize: size,
          fontWeight: FontWeight.w500,
          color: ink);
  final text = base.textTheme
      .apply(fontFamily: 'Segoe UI', bodyColor: ink, displayColor: ink);
  return base.copyWith(
      textTheme: text.copyWith(
          bodySmall: body(text.bodySmall, 14),
          bodyMedium: body(text.bodyMedium, 15),
          bodyLarge: body(text.bodyLarge, 16),
          labelSmall: body(text.labelSmall, 13),
          labelMedium: body(text.labelMedium, 14),
          labelLarge: body(text.labelLarge, 14)),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
          hintStyle: body(text.bodyMedium, 15).copyWith(
              color: base.brightness == Brightness.dark
                  ? const Color(0xffb9c5d4)
                  : const Color(0xff526176))));
}
