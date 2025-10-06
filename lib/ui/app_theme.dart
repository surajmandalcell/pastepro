import 'package:flutter/material.dart';

// Design tokens — common constants (tweak here to restyle app)

// Radii
const double kOverlayRadius = 12.0; // overlay shell corner radius
const double kCardRadius = 14.0; // clipboard card radius

// Blur and shadow
const double kBackdropBlurSigma = 12.0; // gaussian blur for overlay backdrop
const double kShadowBlur = 24.0; // overlay shadow blur
const double kShadowYOffset = -8.0; // overlay shadow vertical offset
const double kShadowOpacity = 0.30; // overlay shadow opacity

// Layout spacing
const double kOverlayTopPadding = 12.0; // top padding inside the overlay
const double kOverlaySidePadding = 24.0; // side paddings

// Accent palette (base hues used across both themes)
const Color kAccentBlue = Color(0xFF5AA7F8);
const Color kAccentTeal = Color(0xFF69D494);
const Color kAccentOrange = Color(0xFFF4C34A);
const Color kAccentRed = Color(0xFFF16B5F);
const Color kAccentLavender = Color(0xFFB48EDE);

// Category seed defaults (exported so DB seeds can use them in one place)
const List<Map<String, dynamic>> kDefaultCategories = [
  {'name': 'Clipboard History', 'color': 0xFFD7C6A5},
  {'name': 'Useful Links', 'color': 0xFFF16B5F},
  {'name': 'Important Notes', 'color': 0xFFF4C34A},
  {'name': 'Email Templates', 'color': 0xFF69D494},
  {'name': 'Code Snippets', 'color': 0xFF5AA7F8},
];

// Theme color maps
class _Light {
  // Shell
  static const overlayTint = Color(0xFFF0E6D8); // warm sheet tint (light)
  static const scrim = Color(0x14000000); // 8% black scrim above blurred bg
  static const overlayBorder = Color(0x1A000000); // 10% black
  static const overlayShadow = Colors.black; // tinted by opacity

  // Text
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0x99000000); // 60% black
  static const textTertiary = Color(0x66000000); // 40% black

  // Search
  static const searchBg = Color(0x0D000000); // 5% black
  static const searchBorder = Color(0x14000000); // 8% black

  // Cards
  static const cardBg = Color(0x0D000000); // 5% black
  static const cardHoverBg = Color(0x14000000); // 8% black
  static const cardBorder = Color(0x1A000000); // 10% black
}

class _Dark {
  // Shell
  static const overlayTint = Color(0xFF1F232A); // dark sheet tint
  static const scrim = Color(0x33000000); // 20% black
  static const overlayBorder = Color(0x33FFFFFF); // 20% white
  static const overlayShadow = Colors.black;

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x99FFFFFF); // 60% white
  static const textTertiary = Color(0x66FFFFFF); // 40% white

  // Search
  static const searchBg = Color(0x1AFFFFFF); // 10% white
  static const searchBorder = Color(0x14FFFFFF); // 8% white

  // Cards
  static const cardBg = Color(0x14FFFFFF); // 8% white
  static const cardHoverBg = Color(0x1FFFFFFF); // ~12% white
  static const cardBorder = Color(0x1AFFFFFF); // 10% white
}

// Quick selector helpers
bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

class AppTheme {
  // Shell
  static Color overlayTint(BuildContext c) => _isDark(c) ? _Dark.overlayTint : _Light.overlayTint;
  static Color overlayScrim(BuildContext c) => _isDark(c) ? _Dark.scrim : _Light.scrim;
  static Color overlayBorder(BuildContext c) => _isDark(c) ? _Dark.overlayBorder : _Light.overlayBorder;
  static Color overlayShadow(BuildContext c) => _isDark(c) ? _Dark.overlayShadow : _Light.overlayShadow;

  // Text
  static Color textPrimary(BuildContext c) => _isDark(c) ? _Dark.textPrimary : _Light.textPrimary;
  static Color textSecondary(BuildContext c) => _isDark(c) ? _Dark.textSecondary : _Light.textSecondary;
  static Color textTertiary(BuildContext c) => _isDark(c) ? _Dark.textTertiary : _Light.textTertiary;

  // Search
  static Color searchBg(BuildContext c) => _isDark(c) ? _Dark.searchBg : _Light.searchBg;
  static Color searchBorder(BuildContext c) => _isDark(c) ? _Dark.searchBorder : _Light.searchBorder;

  // Cards
  static Color cardBg(BuildContext c) => _isDark(c) ? _Dark.cardBg : _Light.cardBg;
  static Color cardHoverBg(BuildContext c) => _isDark(c) ? _Dark.cardHoverBg : _Light.cardHoverBg;
  static Color cardBorder(BuildContext c) => _isDark(c) ? _Dark.cardBorder : _Light.cardBorder;
}

