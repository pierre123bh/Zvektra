import 'package:flutter/material.dart';

const navy = Color(0xFF090F1C);
const cyan = Color(0xFF5FF0DD);
const surface = Color(0xFF151E32);
const accent = Color(0xFFACAFFF);
const panelBorder = Color(0xFF344364);

ThemeData buildZvektraTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: cyan,
    brightness: Brightness.dark,
  ).copyWith(
    primary: cyan,
    onPrimary: const Color(0xFF042523),
    secondary: accent,
    surface: surface,
    onSurface: const Color(0xFFF1F5FF),
    onSurfaceVariant: const Color(0xFFB6C3DC),
    outline: panelBorder,
  );
  final theme = ThemeData(useMaterial3: true, colorScheme: colors, fontFamily: 'Roboto');
  return theme.copyWith(
    scaffoldBackgroundColor: navy,
    textTheme: theme.textTheme.copyWith(
      titleLarge: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: panelBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurface,
        side: const BorderSide(color: panelBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? cyan : colors.onSurfaceVariant,
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 12,
        letterSpacing: 0.15,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
      )),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: navy, centerTitle: false, elevation: 0),
  );
}

class ZvektraWordmark extends StatelessWidget {
  const ZvektraWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 720),
            curve: Curves.easeOutCubic,
            builder: (_, progress, __) => CustomPaint(
              size: const Size.square(34),
              painter: _LogoPainter(progress),
            ),
          ),
        ),
        const SizedBox(width: 11),
        const Text('ZVEKTRA', style: TextStyle(
          color: Color(0xFFF1F5FF),
          fontSize: 21,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.8,
        )),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final tile = RRect.fromRectAndRadius(bounds.deflate(0.5), const Radius.circular(10));
    canvas.drawRRect(tile, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF254466), Color(0xFF17283F), Color(0xFF29264C)],
    ).createShader(bounds));
    canvas.drawRRect(tile, Paint()
      ..color = const Color(0xFF577296)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    canvas.save();
    canvas.clipRRect(tile);
    if (progress < 1) {
      final x = -8 + 50 * progress;
      canvas.drawLine(Offset(x, 0), Offset(x - 9, 34),
          Paint()..color = cyan.withValues(alpha: (1 - progress) * 0.55)..strokeWidth = 2);
    }
    final mark = Path()
      ..moveTo(9, 10)
      ..lineTo(25, 10)
      ..lineTo(10, 24)
      ..lineTo(25, 24);
    canvas.drawPath(mark, Paint()
      ..shader = const LinearGradient(colors: [cyan, accent]).createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(const Offset(26, 7), 1.15, Paint()..color = cyan);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.progress != progress;
}
