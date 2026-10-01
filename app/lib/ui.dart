import 'dart:math';

import 'package:flutter/material.dart';

/// Google brand colours.
const gBlue = Color(0xFF4285F4);
const gRed = Color(0xFFEA4335);
const gYellow = Color(0xFFFBBC04);
const gGreen = Color(0xFF34A853);
const gdgColors = [gBlue, gRed, gYellow, gGreen];

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: gBlue, brightness: b).copyWith(
    primary: gBlue,
    surface: dark ? const Color(0xFF0F1115) : const Color(0xFFF6F7F9),
    surfaceContainer: dark ? const Color(0xFF181B21) : Colors.white,
    surfaceContainerHigh: dark ? const Color(0xFF20242C) : const Color(0xFFEDEFF3),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
      ),
    ),
  );
}

const mono = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontFamily: 'monospace',
  fontFamilyFallback: ['Roboto Mono', 'Menlo', 'Courier'],
);

/// The four GDG dots — a nod to the Pokédex indicator lights.
class GdgDots extends StatelessWidget {
  final double size;
  const GdgDots({super.key, this.size = 10});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in gdgColors)
        Container(
          width: size,
          height: size,
          margin: EdgeInsets.only(right: size * .5),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
    ],
  );
}

class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GdgDots(size: size * .38),
      SizedBox(width: size * .2),
      Text(
        'GDGdex',
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -.5),
      ),
    ],
  );
}

Color colorFor(String key) => gdgColors[key.codeUnits.fold(0, (a, b) => a + b) % 4];

class Avatar extends StatelessWidget {
  final Map<String, dynamic> m;
  final double size;
  const Avatar(this.m, {super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final name = (m['name'] as String? ?? '?').trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    final c = colorFor(m['dexId'] ?? name);
    final url = m['avatarUrl'] as String?;
    final fallback = Container(
      color: c.withValues(alpha: .18),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: size * .38),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: max(2, size / 28)),
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ACTIVE' => ('LIVE', gGreen),
      'ENDED' => ('ENDED', gRed),
      _ => ('NOT STARTED', gYellow),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

/// Small entry card used in the collection grid.
class EntryCard extends StatelessWidget {
  final Map<String, dynamic> m;
  final VoidCallback? onTap;
  const EntryCard(this.m, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  '#${(m['dexId'] as String).replaceFirst('GDG-', '')}',
                  style: mono.copyWith(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              ),
              Avatar(m, size: 64),
              const SizedBox(height: 10),
              Text(
                m['name'],
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                m['role'] ?? '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: error ? gRed : null),
    );
}

/// Centered, width-capped content column so pages look right on phones and projectors alike.
class Narrow extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Narrow({super.key, required this.child, this.maxWidth = 560});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

class ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetry(this.error, this.onRetry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('RETRY')),
        ],
      ),
    ),
  );
}
