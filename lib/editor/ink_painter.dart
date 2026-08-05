import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models.dart';

class _RenderPoint {
  const _RenderPoint(this.offset, this.pressure);

  final Offset offset;
  final double pressure;
}

class InkPainter extends CustomPainter {
  InkPainter({
    required this.strokes,
    this.activeStroke,
    this.lassoPath = const [],
    this.template = BackgroundTemplate.blank,
    this.contentScale = 1.0,
    this.eraserCursor,
    this.eraserDiameter = 0,
  });

  final List<InkObject> strokes;
  final InkObject? activeStroke;
  final List<InkPoint> lassoPath;
  final BackgroundTemplate template;

  /// Continuous-page zoom changes the page's laid-out size instead of applying
  /// a canvas transform. Scale paint widths and text with the page so ink keeps
  /// the same visual proportions while zooming.
  final double contentScale;
  final InkPoint? eraserCursor;
  final double eraserDiameter;

  double get _scale => contentScale.clamp(.25, 8.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    _drawTemplate(canvas, size);
    final currentActive = activeStroke;

    for (final stroke in strokes.whereType<InkStroke>()) {
      if (stroke.tool == InkTool.highlighter) {
        _paintStroke(canvas, size, stroke);
      }
    }
    if (currentActive is InkStroke &&
        currentActive.tool == InkTool.highlighter) {
      _paintStroke(canvas, size, currentActive);
    }

    for (final object in strokes) {
      if (object is InkStroke && object.tool != InkTool.highlighter) {
        _paintStroke(canvas, size, object);
      } else if (object is InkText) {
        _paintText(canvas, size, object);
      }
    }
    if (currentActive is InkStroke &&
        currentActive.tool != InkTool.highlighter) {
      _paintStroke(canvas, size, currentActive);
    } else if (currentActive is InkText) {
      _paintText(canvas, size, currentActive);
    }

    _drawLassoPath(canvas, size);
    _drawSelectionBox(canvas, size);
    _drawEraserCursor(canvas, size);
  }

  Offset _offsetFor(InkPoint point, Size size) => Offset(
        point.x * size.width,
        point.y * size.height,
      );

  Offset _midpoint(Offset a, Offset b) => Offset(
        (a.dx + b.dx) / 2,
        (a.dy + b.dy) / 2,
      );

  void _drawTemplate(Canvas canvas, Size size) {
    if (template == BackgroundTemplate.blank) return;

    final paint = Paint()
      ..isAntiAlias = true
      ..color = Colors.blueAccent.withValues(alpha: 0.2)
      ..strokeWidth = math.max(.75, _scale)
      ..style = PaintingStyle.stroke;

    if (template == BackgroundTemplate.ruled) {
      final spacing = size.height / 25;
      for (double y = spacing * 2; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      final marginPaint = Paint()
        ..isAntiAlias = true
        ..color = Colors.redAccent.withValues(alpha: 0.3)
        ..strokeWidth = math.max(.75, _scale);
      canvas.drawLine(
        Offset(size.width * 0.15, 0),
        Offset(size.width * 0.15, size.height),
        marginPaint,
      );
    } else if (template == BackgroundTemplate.grid) {
      final spacing = size.width / 20;
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    } else if (template == BackgroundTemplate.dotted) {
      final spacing = size.width / 20;
      final dotPaint = Paint()
        ..isAntiAlias = true
        ..color = Colors.grey.withValues(alpha: 0.5);
      for (double y = spacing; y < size.height; y += spacing) {
        for (double x = spacing; x < size.width; x += spacing) {
          canvas.drawCircle(Offset(x, y), 1.5 * _scale, dotPaint);
        }
      }
    }
  }

  void _drawLassoPath(Canvas canvas, Size size) {
    if (lassoPath.length < 2) return;
    final path = Path()
      ..moveTo(
        lassoPath.first.x * size.width,
        lassoPath.first.y * size.height,
      );
    for (final point in lassoPath.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2 * _scale;
    canvas.drawPath(path, paint);
  }

  void _drawSelectionBox(Canvas canvas, Size size) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var hasSelection = false;

    for (final object in strokes) {
      if (!object.isSelected) continue;
      hasSelection = true;
      if (object is InkStroke) {
        for (final point in object.points) {
          minX = math.min(minX, point.x);
          maxX = math.max(maxX, point.x);
          minY = math.min(minY, point.y);
          maxY = math.max(maxY, point.y);
        }
      } else if (object is InkText) {
        final textWidth =
            (object.text.length * object.fontSize * 0.6 * _scale) / size.width;
        final textHeight = object.fontSize * _scale / size.height;
        minX = math.min(minX, object.x);
        maxX = math.max(maxX, object.x + textWidth);
        minY = math.min(minY, object.y);
        maxY = math.max(maxY, object.y + textHeight);
      }
    }

    if (!hasSelection || minX == double.infinity) return;

    final padding = 10 * _scale;
    final rect = Rect.fromLTRB(
      minX * size.width - padding,
      minY * size.height - padding,
      maxX * size.width + padding,
      maxY * size.height + padding,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * _scale;
    canvas.drawRect(rect, paint);

    final handlePaint = Paint()
      ..isAntiAlias = true
      ..color = Colors.white;
    final handleBorder = Paint()
      ..isAntiAlias = true
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * _scale;
    final handleRadius = 6 * _scale;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, handleRadius, handlePaint);
      canvas.drawCircle(point, handleRadius, handleBorder);
    }
  }

  double _pressureWidth(
    InkStroke stroke,
    double pressure,
    double progress, {
    double speed = 0,
  }) {
    final rawPressure = pressure.clamp(.03, 1.0).toDouble();
    final sensitivity = stroke.pressureSensitivity.clamp(0.0, 1.0).toDouble();
    final pressureValue = ((1 - sensitivity) * .72 +
            sensitivity * math.sqrt(rawPressure))
        .clamp(.08, 1.0)
        .toDouble();
    final baseWidth = stroke.width * _scale;
    final speedReduction =
        1 - speed.clamp(0.0, 1.0).toDouble() * .12;

    switch (stroke.tool) {
      case InkTool.fountainPen:
        final endTaper = ((1 - progress) / .035).clamp(.48, 1.0).toDouble();
        return baseWidth * (.48 + pressureValue * 1.12) *
            speedReduction * endTaper;
      case InkTool.brushPen:
        final startTaper = (progress / .055).clamp(.18, 1.0).toDouble();
        final endTaper = ((1 - progress) / .12).clamp(.12, 1.0).toDouble();
        return baseWidth * (.28 + pressureValue * 1.55) *
            startTaper * endTaper * speedReduction;
      case InkTool.highlighter:
        return baseWidth;
      case InkTool.pen:
      default:
        // A ball pen stays nearly constant, while retaining a very small
        // amount of pressure response so Pencil input does not feel digital.
        return baseWidth * (.96 + pressureValue * .08);
    }
  }

  List<_RenderPoint> _filteredRenderPoints(
    InkStroke stroke,
    Size size,
  ) {
    final source = <_RenderPoint>[];
    for (final point in stroke.points) {
      final candidate = _RenderPoint(_offsetFor(point, size), point.pressure);
      if (source.isEmpty ||
          (candidate.offset - source.last.offset).distanceSquared >= .01) {
        source.add(candidate);
      }
    }
    if (source.length < 3) return source;

    // A short symmetric low-pass filter removes hand-sampling corners without
    // lagging the tip. Endpoints stay exact so letters still begin and finish
    // where the Pencil touched the page.
    var filtered = source;
    for (var pass = 0; pass < 2; pass++) {
      final next = <_RenderPoint>[filtered.first];
      for (var index = 1; index < filtered.length - 1; index++) {
        final previous = filtered[index - 1];
        final current = filtered[index];
        final following = filtered[index + 1];
        next.add(
          _RenderPoint(
            Offset(
              (previous.offset.dx + current.offset.dx * 4 +
                      following.offset.dx) /
                  6,
              (previous.offset.dy + current.offset.dy * 4 +
                      following.offset.dy) /
                  6,
            ),
            (previous.pressure + current.pressure * 4 +
                    following.pressure) /
                6,
          ),
        );
      }
      next.add(filtered.last);
      filtered = next;
    }
    return filtered;
  }

  Path _smoothCenterPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    // Midpoint quadratics form one continuously curved centerline. This avoids
    // the visible straight joins and Catmull-Rom overshoot that appeared when
    // handwriting was enlarged several times.
    for (var index = 1; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      final midpoint = _midpoint(current, next);
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
    final last = points.last;
    path.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);
    return path;
  }

  List<_RenderPoint> _interpolatedPoints(InkStroke stroke, Size size) {
    final source = _filteredRenderPoints(stroke, size);
    if (source.length < 2) return source;

    final output = <_RenderPoint>[];
    for (var index = 0; index < source.length - 1; index++) {
      final p0 = source[index == 0 ? 0 : index - 1];
      final p1 = source[index];
      final p2 = source[index + 1];
      final p3 = source[index + 2 < source.length
          ? index + 2
          : source.length - 1];
      final distance = (p2.offset - p1.offset).distance;
      final steps = (distance / .8).ceil().clamp(2, 40).toInt();

      for (var step = 0; step < steps; step++) {
        final t = step / steps;
        final t2 = t * t;
        final t3 = t2 * t;
        final x = .5 *
            ((2 * p1.offset.dx) +
                (-p0.offset.dx + p2.offset.dx) * t +
                (2 * p0.offset.dx -
                        5 * p1.offset.dx +
                        4 * p2.offset.dx -
                        p3.offset.dx) *
                    t2 +
                (-p0.offset.dx +
                        3 * p1.offset.dx -
                        3 * p2.offset.dx +
                        p3.offset.dx) *
                    t3);
        final y = .5 *
            ((2 * p1.offset.dy) +
                (-p0.offset.dy + p2.offset.dy) * t +
                (2 * p0.offset.dy -
                        5 * p1.offset.dy +
                        4 * p2.offset.dy -
                        p3.offset.dy) *
                    t2 +
                (-p0.offset.dy +
                        3 * p1.offset.dy -
                        3 * p2.offset.dy +
                        p3.offset.dy) *
                    t3);
        output.add(
          _RenderPoint(
            Offset(x, y),
            p1.pressure + (p2.pressure - p1.pressure) * t,
          ),
        );
      }
    }
    output.add(source.last);
    return output;
  }

  void _appendSmoothBoundary(
    Path path,
    List<Offset> points, {
    required bool moveToFirst,
  }) {
    if (points.isEmpty) return;
    if (moveToFirst) {
      path.moveTo(points.first.dx, points.first.dy);
    } else {
      path.lineTo(points.first.dx, points.first.dy);
    }
    if (points.length == 1) return;
    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return;
    }
    for (var index = 1; index < points.length - 1; index++) {
      final point = points[index];
      final midpoint = _midpoint(point, points[index + 1]);
      path.quadraticBezierTo(
        point.dx,
        point.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
  }

  void _drawVariableStroke(
    Canvas canvas,
    InkStroke stroke,
    List<_RenderPoint> points,
    Paint paint,
  ) {
    if (points.length < 2) return;
    final left = <Offset>[];
    final right = <Offset>[];
    final widths = <double>[];

    for (var index = 0; index < points.length; index++) {
      final previous = points[index == 0 ? 0 : index - 1].offset;
      final next = points[index + 1 < points.length
          ? index + 1
          : points.length - 1].offset;
      var tangent = next - previous;
      if (tangent.distanceSquared < .0001) {
        tangent = const Offset(1, 0);
      } else {
        tangent = tangent / tangent.distance;
      }
      final normal = Offset(-tangent.dy, tangent.dx);
      final progress = index / math.max(1, points.length - 1);
      final localSpeed = (next - previous).distance / 9;
      final width = _pressureWidth(
        stroke,
        points[index].pressure,
        progress,
        speed: localSpeed,
      );
      widths.add(width);
      left.add(points[index].offset + normal * (width / 2));
      right.add(points[index].offset - normal * (width / 2));
    }

    final outline = Path();
    _appendSmoothBoundary(outline, left, moveToFirst: true);
    _appendSmoothBoundary(
      outline,
      right.reversed.toList(),
      moveToFirst: false,
    );
    outline.close();

    final fill = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = paint.color;
    canvas.drawPath(outline, fill);
    canvas.drawCircle(points.first.offset, widths.first / 2, fill);
    canvas.drawCircle(points.last.offset, widths.last / 2, fill);
  }

  void _paintStroke(Canvas canvas, Size size, InkStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..color = stroke.isSelected
          ? Colors.blue.withValues(alpha: 0.5)
          : stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (stroke.tool == InkTool.highlighter) {
      paint
        ..color = paint.color.withValues(alpha: 0.28)
        ..strokeCap = StrokeCap.square
        ..blendMode = BlendMode.multiply;
    }

    if (stroke.tool == InkTool.shape && stroke.points.length > 1) {
      paint.strokeWidth = stroke.width * _scale;
      final start = _offsetFor(stroke.points.first, size);
      final end = _offsetFor(stroke.points.last, size);
      if (stroke.dashed) {
        _drawDashedSegment(canvas, start, end, paint);
      } else {
        canvas.drawLine(start, end, paint);
      }
      return;
    }

    if (stroke.points.length == 1) {
      final point = stroke.points.first;
      final radius = _pressureWidth(stroke, point.pressure, 0) / 2;
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(_offsetFor(point, size), math.max(.75, radius), paint);
      return;
    }

    final centerPoints = _filteredRenderPoints(stroke, size);
    final renderPoints = _interpolatedPoints(stroke, size);

    if (stroke.dashed) {
      var dashPhase = 0.0;
      for (var index = 0; index < renderPoints.length - 1; index++) {
        final first = renderPoints[index];
        final second = renderPoints[index + 1];
        final pressure = (first.pressure + second.pressure) / 2;
        paint.strokeWidth = _pressureWidth(
          stroke,
          pressure,
          index / math.max(1, renderPoints.length - 1),
        );
        dashPhase = _drawDashedSegment(
          canvas,
          first.offset,
          second.offset,
          paint,
          phase: dashPhase,
        );
      }
      return;
    }

    if (stroke.tool == InkTool.fountainPen ||
        stroke.tool == InkTool.brushPen) {
      _drawVariableStroke(canvas, stroke, renderPoints, paint);
      return;
    }

    final averagePressure = renderPoints
            .map((point) => point.pressure)
            .fold<double>(0, (sum, pressure) => sum + pressure) /
        renderPoints.length;
    paint.strokeWidth = _pressureWidth(stroke, averagePressure, .5);
    canvas.drawPath(
      _smoothCenterPath(
        centerPoints.map((point) => point.offset).toList(),
      ),
      paint,
    );
  }

  void _drawEraserCursor(Canvas canvas, Size size) {
    final cursor = eraserCursor;
    if (cursor == null || eraserDiameter <= 0) return;
    final center = _offsetFor(cursor, size);
    final radius = eraserDiameter / 2;
    final fill = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: .22);
    final border = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withValues(alpha: .46);
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, border);
  }

  double _drawDashedSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double phase = 0,
  }) {
    final delta = end - start;
    final distance = delta.distance;
    if (distance <= 0) return phase;
    final direction = delta / distance;
    final dashLength = 10.0 * _scale;
    final gapLength = 7.0 * _scale;
    final cycle = dashLength + gapLength;
    var traveled = 0.0;
    var currentPhase = phase % cycle;

    while (traveled < distance) {
      final inDash = currentPhase < dashLength;
      final remainingInPart =
          inDash ? dashLength - currentPhase : cycle - currentPhase;
      final step = math.min(remainingInPart, distance - traveled);
      if (inDash && step > 0) {
        canvas.drawLine(
          start + direction * traveled,
          start + direction * (traveled + step),
          paint,
        );
      }
      traveled += step;
      currentPhase = (currentPhase + step) % cycle;
    }
    return (phase + distance) % cycle;
  }

  void _paintText(Canvas canvas, Size size, InkText textObject) {
    final textSpan = TextSpan(
      text: textObject.text,
      style: TextStyle(
        color: textObject.isSelected ? Colors.blue : textObject.color,
        fontSize: textObject.fontSize * _scale,
        fontWeight: textObject.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: textObject.italic ? FontStyle.italic : FontStyle.normal,
        height: textObject.lineHeight,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: textObject.textAlign,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(textObject.x * size.width, textObject.y * size.height),
    );
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}
