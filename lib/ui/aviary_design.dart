import 'dart:math' as math;

import 'package:flutter/material.dart';


abstract final class AviaryLayout {
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 700;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 10;
    if (width >= 700) return 18;
    return 12;
  }

  static double contentMaxWidth(BuildContext context) =>
      isWide(context) ? 920 : double.infinity;
}

/// Keeps phone layouts fluid on small screens while preventing the main tabs
/// from becoming excessively stretched on tablets and large foldables.
class AviaryResponsivePane extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AviaryResponsivePane({
    super.key,
    required this.child,
    this.maxWidth = 920,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = math.min(constraints.maxWidth, maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: targetWidth,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}

abstract final class AviaryColors {
  static const Color dashboard = Color(0xFF4F7CFF);
  static const Color birds = Color(0xFF2E8B78);
  static const Color cages = Color(0xFF8A63D2);
  static const Color breeding = Color(0xFFE28A35);
  static const Color finance = Color(0xFF238A5A);
  static const Color history = Color(0xFF55708F);

  static const Color chick = Color(0xFFFFE4EE);
  static const Color paired = Color(0xFFFFE4E1);
  static const Color eggsNormal = Color(0xFFE8F2FF);
  static const Color hatchFiveDays = Color(0xFFFFF4C7);
  static const Color hatchThreeDays = Color(0xFFFFE2B6);
  static const Color hatchOneDay = Color(0xFFFFCFC8);
  static const Color hatching = Color(0xFFEADDFB);
  static const Color chicksHatched = Color(0xFFDDF5E8);
  static const Color income = Color(0xFFDDF5E8);
  static const Color expense = Color(0xFFFFE1D6);
  static const Color reserved = Color(0xFFE6E1FF);
}

Color? birdGenderTextColor(String? gender) {
  return switch (gender?.trim().toLowerCase()) {
    'male' => const Color(0xFF2878D4),
    'female' => const Color(0xFFD94F8A),
    _ => null,
  };
}

String aviaryCageLabel(dynamic identifier, {String emptyLabel = 'No cage'}) {
  final raw = identifier?.toString().trim() ?? '';
  if (raw.isEmpty) return emptyLabel;
  return raw.toLowerCase().startsWith('cage') ? raw : 'Cage $raw';
}

enum AviaryIconType {
  dashboard,
  bird,
  cage,
  breeding,
  finance,
  more,
  pair,
  egg,
  chick,
}

class AviaryIcon extends StatelessWidget {
  final AviaryIconType type;
  final double size;
  final Color? color;
  final bool filled;

  const AviaryIcon(
    this.type, {
    super.key,
    this.size = 24,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AviaryIconPainter(
        type: type,
        color: color ?? IconTheme.of(context).color ?? Colors.black,
        filled: filled,
      ),
    );
  }
}

class _AviaryIconPainter extends CustomPainter {
  final AviaryIconType type;
  final Color color;
  final bool filled;

  const _AviaryIconPainter({
    required this.type,
    required this.color,
    required this.filled,
  });

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.9
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    switch (type) {
      case AviaryIconType.dashboard:
        _dashboard(canvas, s);
        break;
      case AviaryIconType.bird:
        _bird(canvas, s);
        break;
      case AviaryIconType.cage:
        _cage(canvas, s);
        break;
      case AviaryIconType.breeding:
        _breeding(canvas, s);
        break;
      case AviaryIconType.finance:
        _finance(canvas, s);
        break;
      case AviaryIconType.more:
        _more(canvas, s);
        break;
      case AviaryIconType.pair:
        _pair(canvas, s);
        break;
      case AviaryIconType.egg:
        _egg(canvas, s);
        break;
      case AviaryIconType.chick:
        _chick(canvas, s);
        break;
    }
    canvas.restore();
  }

  void _dashboard(Canvas c, double s) {
    final p = _stroke;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * .12, s * .14, s * .32, s * .30),
      Radius.circular(s * .07),
    );
    final r2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * .56, s * .14, s * .32, s * .48),
      Radius.circular(s * .07),
    );
    final r3 = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * .12, s * .56, s * .32, s * .30),
      Radius.circular(s * .07),
    );
    final r4 = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * .56, s * .72, s * .32, s * .14),
      Radius.circular(s * .07),
    );
    if (filled) {
      c.drawRRect(r, _fill);
      c.drawRRect(r2, _fill);
      c.drawRRect(r3, _fill);
      c.drawRRect(r4, _fill);
    } else {
      c.drawRRect(r, p);
      c.drawRRect(r2, p);
      c.drawRRect(r3, p);
      c.drawRRect(r4, p);
    }
  }

  void _bird(Canvas c, double s) {
    final p = _stroke;
    final body = Path()
      ..moveTo(s * .18, s * .62)
      ..cubicTo(s * .34, s * .80, s * .69, s * .78, s * .77, s * .50)
      ..cubicTo(s * .68, s * .55, s * .59, s * .55, s * .52, s * .49)
      ..cubicTo(s * .42, s * .39, s * .32, s * .40, s * .18, s * .62)
      ..close();
    final wing = Path()
      ..moveTo(s * .29, s * .60)
      ..cubicTo(s * .38, s * .45, s * .55, s * .43, s * .66, s * .52)
      ..cubicTo(s * .53, s * .60, s * .43, s * .65, s * .29, s * .60);
    if (filled) {
      c.drawPath(body, _fill);
      c.drawPath(wing, Paint()..color = Colors.white.withValues(alpha: .72));
    } else {
      c.drawPath(body, p);
      c.drawPath(wing, p);
    }
    c.drawCircle(Offset(s * .68, s * .42), s * .12, filled ? _fill : p);
    c.drawPath(
      Path()
        ..moveTo(s * .79, s * .42)
        ..lineTo(s * .92, s * .47)
        ..lineTo(s * .79, s * .50),
      p,
    );
    c.drawCircle(
      Offset(s * .70, s * .39),
      s * .014,
      filled ? (Paint()..color = Colors.white) : _fill,
    );
    c.drawPath(
      Path()
        ..moveTo(s * .25, s * .68)
        ..lineTo(s * .11, s * .77)
        ..moveTo(s * .29, s * .71)
        ..lineTo(s * .17, s * .84),
      p,
    );
  }

  void _cage(Canvas c, double s) {
    final p = _stroke;
    final dome = Path()
      ..moveTo(s * .18, s * .38)
      ..cubicTo(s * .20, s * .12, s * .80, s * .12, s * .82, s * .38)
      ..lineTo(s * .82, s * .83)
      ..lineTo(s * .18, s * .83)
      ..close();
    c.drawPath(dome, p);
    c.drawLine(Offset(s * .12, s * .88), Offset(s * .88, s * .88), p);
    for (final x in [.31, .44, .56, .69]) {
      c.drawLine(Offset(s * x, s * .28), Offset(s * x, s * .82), p);
    }
    c.drawLine(Offset(s * .18, s * .52), Offset(s * .82, s * .52), p);
    c.drawCircle(Offset(s * .50, s * .09), s * .035, p);
  }

  void _breeding(Canvas c, double s) {
    final p = _stroke;
    _smallBird(c, s, Offset(s * .32, s * .42), false);
    _smallBird(c, s, Offset(s * .68, s * .42), true);
    final egg = Rect.fromCenter(
      center: Offset(s * .50, s * .72),
      width: s * .22,
      height: s * .28,
    );
    c.drawOval(egg, filled ? _fill : p);
  }

  void _smallBird(Canvas c, double s, Offset center, bool flip) {
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(flip ? -1 : 1, 1);
    final p = _stroke;
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * .28, height: s * .18),
      filled ? _fill : p,
    );
    c.drawCircle(Offset(s * .13, -s * .08), s * .07, filled ? _fill : p);
    c.drawLine(Offset(s * .18, -s * .08), Offset(s * .25, -s * .05), p);
    c.restore();
  }

  void _finance(Canvas c, double s) {
    final p = _stroke;
    c.drawOval(
      Rect.fromLTWH(s * .15, s * .18, s * .52, s * .26),
      filled ? _fill : p,
    );
    c.drawRect(
      Rect.fromLTWH(s * .15, s * .31, s * .52, s * .36),
      filled ? _fill : p,
    );
    c.drawOval(
      Rect.fromLTWH(s * .15, s * .54, s * .52, s * .26),
      filled ? _fill : p,
    );
    c.drawCircle(Offset(s * .72, s * .66), s * .18, filled ? _fill : p);
    c.drawLine(Offset(s * .72, s * .57), Offset(s * .72, s * .75), p);
    c.drawPath(
      Path()
        ..moveTo(s * .78, s * .59)
        ..cubicTo(s * .68, s * .54, s * .64, s * .61, s * .72, s * .65)
        ..cubicTo(s * .80, s * .69, s * .76, s * .77, s * .66, s * .72),
      p,
    );
  }

  void _more(Canvas c, double s) {
    for (final x in [.24, .50, .76]) {
      c.drawCircle(Offset(s * x, s * .50), s * .08, _fill);
    }
  }

  void _pair(Canvas c, double s) {
    final p = _stroke;
    final heart = Path()
      ..moveTo(s * .50, s * .82)
      ..cubicTo(s * .15, s * .58, s * .20, s * .25, s * .40, s * .23)
      ..cubicTo(s * .49, s * .22, s * .50, s * .32, s * .50, s * .32)
      ..cubicTo(s * .50, s * .32, s * .51, s * .22, s * .60, s * .23)
      ..cubicTo(s * .80, s * .25, s * .85, s * .58, s * .50, s * .82)
      ..close();
    c.drawPath(heart, filled ? _fill : p);
  }

  void _egg(Canvas c, double s) {
    final p = _stroke;
    final path = Path()
      ..moveTo(s * .50, s * .10)
      ..cubicTo(s * .30, s * .14, s * .19, s * .50, s * .22, s * .69)
      ..cubicTo(s * .25, s * .91, s * .75, s * .91, s * .78, s * .69)
      ..cubicTo(s * .81, s * .50, s * .70, s * .14, s * .50, s * .10)
      ..close();
    c.drawPath(path, filled ? _fill : p);
  }

  void _chick(Canvas c, double s) {
    final p = _stroke;
    c.drawCircle(Offset(s * .50, s * .53), s * .25, filled ? _fill : p);
    c.drawCircle(Offset(s * .58, s * .28), s * .15, filled ? _fill : p);
    c.drawPath(
      Path()
        ..moveTo(s * .72, s * .28)
        ..lineTo(s * .88, s * .34)
        ..lineTo(s * .72, s * .39),
      p,
    );
    c.drawCircle(
      Offset(s * .61, s * .24),
      s * .016,
      filled ? (Paint()..color = Colors.white) : _fill,
    );
    c.drawLine(Offset(s * .43, s * .76), Offset(s * .39, s * .88), p);
    c.drawLine(Offset(s * .57, s * .76), Offset(s * .61, s * .88), p);
  }

  @override
  bool shouldRepaint(covariant _AviaryIconPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.filled != filled;
  }
}

class AviarySegmentedControl<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color accent;

  const AviarySegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: items.map((item) {
            final active = item.$1 == selected;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: active ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active
                      ? const [
                          BoxShadow(
                            blurRadius: 5,
                            offset: Offset(0, 2),
                            color: Color(0x22000000),
                          ),
                        ]
                      : null,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(item.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AviaryLayout.isCompact(context) ? 13 : null,
                        color: active ? Colors.white : null,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

Color aviaryBreedingTint({
  required int activeEggs,
  required int chicksInNest,
  required int unresolvedEggs,
  DateTime? nextHatchDate,
}) {
  if (chicksInNest > 0 && unresolvedEggs > 0) return AviaryColors.hatching;
  if (chicksInNest > 0 && unresolvedEggs == 0) {
    return AviaryColors.chicksHatched;
  }
  if (activeEggs <= 0) return Colors.transparent;
  if (nextHatchDate == null) return AviaryColors.eggsNormal;

  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final hatch = DateTime(
    nextHatchDate.year,
    nextHatchDate.month,
    nextHatchDate.day,
  );
  final days = hatch.difference(start).inDays;
  if (days <= 1) return AviaryColors.hatchOneDay;
  if (days <= 3) return AviaryColors.hatchThreeDays;
  if (days <= 5) return AviaryColors.hatchFiveDays;
  return AviaryColors.eggsNormal;
}
