import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart'; // Colors

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/map/map.dart';
import 'package:latlong2/latlong.dart';

class MyPolylineLayerOptions extends LayerOptions {
  /// List of polylines to draw.
  final List<MyPolyline> polylines;

  final bool polylineCulling;

  /// {@macro newMyPolylinePainter.saveLayers}
  ///
  /// By default, this value is set to `false` to improve performance on
  /// layers containing a lot of polylines.
  ///
  /// You might want to set this to `true` if you get unwanted darker lines
  /// where they overlap but, keep in mind that this might reduce the
  /// performance of the layer.
  final bool saveLayers;

  MyPolylineLayerOptions({
    Key? key,
    this.polylines = const [],
    this.polylineCulling = false,
    Stream<void>? rebuild,
    this.saveLayers = false,
  }) : super(key: key, rebuild: rebuild) {
    if (polylineCulling) {
      for (final polyline in polylines) {
        polyline.boundingBox = LatLngBounds.fromPoints(polyline.points);
      }
    }
  }
}

class MyPolyline {
  final List<LatLng> points;
  final List<Offset> offsets = [];
  final double strokeWidth;
  /*final*/ Color color;    // 変更可能！！
  final double borderStrokeWidth;
  final Color? borderColor;
  final List<Color>? gradientColors;
  final List<double>? colorsStop;
  final bool isDotted;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final bool startCapMarker;
  final bool endCapMarker;
  late LatLngBounds boundingBox;
  final bool shouldRepaint;

  MyPolyline({
    required this.points,
    this.strokeWidth = 1.0,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.gradientColors,
    this.colorsStop,
    this.isDotted = false,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.startCapMarker = false,
    this.endCapMarker = false,
    this.shouldRepaint = false,
  });
}

// flutter_map のプラグインとしてレイヤーを実装
class MyPolylineLayerPlugin implements MapPlugin
{
  @override
  bool supportsLayer(LayerOptions options) {
    return options is MyPolylineLayerOptions;
  }

  @override
  Widget createLayer(LayerOptions options, MapState map, Stream<void> stream) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size, options as MyPolylineLayerOptions, map, stream);
      },
    );
  }

  Widget _build(
    BuildContext context, Size size,
    MyPolylineLayerOptions polylineOpts, MapState map, Stream<void> stream)
  {
    return StreamBuilder<void>(
      stream: stream, // a Stream<void> or null
      builder: (BuildContext context, _) {
        final polylines = <Widget>[];

        for (final polylineOpt in polylineOpts.polylines) {
          polylineOpt.offsets.clear();

          if (polylineOpts.polylineCulling &&
              !polylineOpt.boundingBox.isOverlapping(map.bounds)) {
            // skip this polyline as it's offscreen
            continue;
          }

          _fillOffsets(map, polylineOpt.offsets, polylineOpt.points);

          polylines.add(CustomPaint(
            painter: MyPolylinePainter(polylineOpt, polylineOpts.saveLayers),
            size: size,
            willChange: true,
          ));
        }

        return Stack(
          children: polylines,
        );
      },
    );
  }

  void _fillOffsets(MapState map, final List<Offset> offsets, final List<LatLng> points) {
    final len = points.length;
    for (var i = 0; i < len; ++i) {
      final point = points[i];
      final offset = map.getOffsetFromOrigin(point);
      offsets.add(offset);
    }
  }
}

class MyPolylinePainter extends CustomPainter {
  final MyPolyline polylineOpt;

  /// {@template newMyPolylinePainter.saveLayers}
  /// If `true`, the canvas will be updated on every frame by calling the
  /// methods [Canvas.saveLayer] and [Canvas.restore].
  /// {@endtemplate}
  final bool saveLayers;

  MyPolylinePainter(this.polylineOpt, this.saveLayers);

  @override
  void paint(Canvas canvas, Size size) {
    if (polylineOpt.offsets.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final paint = Paint()
      ..strokeWidth = polylineOpt.strokeWidth
      ..strokeCap = polylineOpt.strokeCap
      ..strokeJoin = polylineOpt.strokeJoin
      ..blendMode = BlendMode.srcOver;

    if (polylineOpt.gradientColors == null) {
      paint.color = polylineOpt.color;
    } else {
      polylineOpt.gradientColors!.isNotEmpty
          ? paint.shader = _paintGradient()
          : paint.color = polylineOpt.color;
    }

    Paint? filterPaint;
    if (polylineOpt.borderColor != null) {
      filterPaint = Paint()
        ..color = polylineOpt.borderColor!.withAlpha(255)
        ..strokeWidth = polylineOpt.strokeWidth
        ..strokeCap = polylineOpt.strokeCap
        ..strokeJoin = polylineOpt.strokeJoin
        ..blendMode = BlendMode.dstOut;
    }

    final borderPaint = polylineOpt.borderStrokeWidth > 0.0
        ? (Paint()
          ..color = polylineOpt.borderColor ?? const Color(0x00000000)
          ..strokeWidth =
              polylineOpt.strokeWidth + polylineOpt.borderStrokeWidth
          ..strokeCap = polylineOpt.strokeCap
          ..strokeJoin = polylineOpt.strokeJoin
          ..blendMode = BlendMode.srcOver)
        : null;
    final radius = paint.strokeWidth / 2;
    final borderRadius = (borderPaint?.strokeWidth ?? 0) / 2;
    if (polylineOpt.isDotted) {
      final spacing = polylineOpt.strokeWidth * 1.5;
      if (saveLayers) canvas.saveLayer(rect, Paint());
      if (borderPaint != null && filterPaint != null) {
        _paintDottedLine(
            canvas, polylineOpt.offsets, borderRadius, spacing, borderPaint);
        _paintDottedLine(
            canvas, polylineOpt.offsets, radius, spacing, filterPaint);
      }
      _paintDottedLine(canvas, polylineOpt.offsets, radius, spacing, paint);
      if (saveLayers) canvas.restore();
    } else {
      paint.style = PaintingStyle.stroke;
      if (saveLayers) canvas.saveLayer(rect, Paint());
      if (borderPaint != null && filterPaint != null) {
        borderPaint.style = PaintingStyle.stroke;
        _paintLine(canvas, polylineOpt.offsets, borderPaint);
        filterPaint.style = PaintingStyle.stroke;
        _paintLine(canvas, polylineOpt.offsets, filterPaint);
      }
      _paintLine(canvas, polylineOpt.offsets, paint);
      // スタート、ゴールの両端にマルマーカーを描画
      if(polylineOpt.startCapMarker){
        _paintCapCircle(canvas, paint, polylineOpt.offsets.first, "S");
      }
      if(polylineOpt.endCapMarker){
        _paintCapCircle(canvas, paint, polylineOpt.offsets.last, "E");
      }
      if (saveLayers) canvas.restore();
    }
  }

  void _paintDottedLine(Canvas canvas, List<Offset> offsets, double radius,
      double stepLength, Paint paint) {
    final path = ui.Path();
    var startDistance = 0.0;
    for (var i = 0; i < offsets.length - 1; i++) {
      final o0 = offsets[i];
      final o1 = offsets[i + 1];
      final totalDistance = _dist(o0, o1);
      var distance = startDistance;
      while (distance < totalDistance) {
        final f1 = distance / totalDistance;
        final f0 = 1.0 - f1;
        final offset = Offset(o0.dx * f0 + o1.dx * f1, o0.dy * f0 + o1.dy * f1);
        path.addOval(Rect.fromCircle(center: offset, radius: radius));
        distance += stepLength;
      }
      startDistance = distance < totalDistance
          ? stepLength - (totalDistance - distance)
          : distance - totalDistance;
    }
    path.addOval(
        Rect.fromCircle(center: polylineOpt.offsets.last, radius: radius));
    canvas.drawPath(path, paint);
  }

  void _paintLine(Canvas canvas, List<Offset> offsets, Paint paint) {
    if (offsets.isEmpty) {
      return;
    }
    final path = ui.Path()..addPolygon(offsets, false);
    canvas.drawPath(path, paint);
  }

  // マル背景に文字を描画
  void _paintCapCircle(Canvas canvas, Paint paint, Offset c, String text)
  {
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(c, 10, paint);
    paint.style = PaintingStyle.stroke;

    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(
      c.dx - textPainter.width / 2,
      c.dy - textPainter.height / 2));
  }

  ui.Gradient _paintGradient() => ui.Gradient.linear(polylineOpt.offsets.first,
      polylineOpt.offsets.last, polylineOpt.gradientColors!, _getColorsStop());

  List<double>? _getColorsStop() => (polylineOpt.colorsStop != null &&
          polylineOpt.colorsStop!.length == polylineOpt.gradientColors!.length)
      ? polylineOpt.colorsStop
      : _calculateColorsStop();

  List<double> _calculateColorsStop() {
    final colorsStopInterval = 1.0 / polylineOpt.gradientColors!.length;
    return polylineOpt.gradientColors!
        .map((gradientColor) =>
            polylineOpt.gradientColors!.indexOf(gradientColor) *
            colorsStopInterval)
        .toList();
  }

  //NOTE: これが true を返さないと、StreamBuilder が走っても再描画されないことがある。
  @override
  bool shouldRepaint(MyPolylinePainter oldDelegate)
  {
    // NOTE: 本来は this と oldDelegate を比較して変更あるかチェックする。
    // 面倒なので、MyPolyline のフラグに持たせた。
    return polylineOpt.shouldRepaint;
  }
}

double _dist(Offset v, Offset w) {
  return sqrt(_dist2(v, w));
}

double _dist2(Offset v, Offset w) {
  return _sqr(v.dx - w.dx) + _sqr(v.dy - w.dy);
}

double _sqr(double x) {
  return x * x;
}
