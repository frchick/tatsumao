part of 'mypolyline_layer.dart';

/// [CustomPainter] for [MyPolyline]s.
base class _MyPolylinePainter<R extends Object>
    extends HitDetectablePainter<R, _MyProjectedPolyline<R>>
    with HitTestRequiresCameraOrigin {
  /// Reference to the list of [MyPolyline]s.
  final List<_MyProjectedPolyline<R>> polylines;

  final double minimumHitbox;

  /// CapCircleを描画するか否か
  final bool showStartCapCircle;
  final bool showEndCapCircle;

  /// Create a new [_MyPolylinePainter] instance
  _MyPolylinePainter({
    required this.polylines,
    required this.minimumHitbox,
    required super.camera,
    required super.hitNotifier,
    this.showStartCapCircle = false,
    this.showEndCapCircle = false,
  });

  @override
  bool elementHitTest(
    _MyProjectedPolyline<R> projectedPolyline, {
    required math.Point<double> point,
    required LatLng coordinate,
  }) {
    final polyline = projectedPolyline.polyline;

    // TODO: For efficiency we'd ideally filter by bounding box here. However
    // we'd need to compute an extended bounding box that accounts account for
    // the `borderStrokeWidth` & the `minimumHitbox`
    // if (!polyline.boundingBox.contains(touch)) {
    //   continue;
    // }

    final offsets = getOffsetsXY(
      camera: camera,
      origin: hitTestCameraOrigin,
      points: projectedPolyline.points,
    );
    final strokeWidth = polyline.useStrokeWidthInMeter
        ? _metersToStrokeWidth(
            hitTestCameraOrigin,
            _unproject(projectedPolyline.points.first),
            offsets.first,
            polyline.strokeWidth,
          )
        : polyline.strokeWidth;
    final hittableDistance = math.max(
      strokeWidth / 2 + polyline.borderStrokeWidth / 2,
      minimumHitbox,
    );

    for (int i = 0; i < offsets.length - 1; i++) {
      final o1 = offsets[i];
      final o2 = offsets[i + 1];

      final distanceSq =
          getSqSegDist(point.x, point.y, o1.dx, o1.dy, o2.dx, o2.dy);

      if (distanceSq <= hittableDistance * hittableDistance) return true;
    }

    return false;
  }

  @override
  Iterable<_MyProjectedPolyline<R>> get elements => polylines;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    var path = ui.Path();
    var borderPath = ui.Path();
    var filterPath = ui.Path();
    var paint = Paint();
    var needsLayerSaving = false;

    // スタート・ゴールの地点を記録
    List<Offset> startOffsets = [];
    List<Offset> endOffsets = [];

    Paint? borderPaint;
    Paint? filterPaint;
    int? lastHash;

    void drawPaths() {
      final hasBorder = borderPaint != null && filterPaint != null;
      if (hasBorder) {
        if (needsLayerSaving) {
          canvas.saveLayer(rect, Paint());
        }

        canvas.drawPath(borderPath, borderPaint!);
        borderPath = ui.Path();
        borderPaint = null;

        if (needsLayerSaving) {
          canvas.drawPath(filterPath, filterPaint!);
          filterPath = ui.Path();
          filterPaint = null;

          canvas.restore();
        }
      }

      canvas.drawPath(path, paint);
    }

    // マル背景に文字を描画
    void drawCapCircle()
    {
      paint.style = PaintingStyle.fill;

      if(showStartCapCircle){
        // スタートの点を描く
        const startTextSpan = TextSpan(
          text: "S",
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        );
        final startTextPainter = TextPainter(
          text: startTextSpan,
          textDirection: TextDirection.ltr,
        );
        startTextPainter.layout();
        
        for(final offset in startOffsets){
          canvas.drawCircle(offset, 10, paint);
          startTextPainter.paint(canvas, Offset(
            offset.dx - startTextPainter.width / 2,
            offset.dy - startTextPainter.height / 2));
        }
      }

      if(showEndCapCircle){// エンドの点を描く
        const endTextSpan = TextSpan(
          text: "E",
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        );
        final endTextPainter = TextPainter(
          text: endTextSpan,
          textDirection: TextDirection.ltr,
        );
        endTextPainter.layout();
      
        for(final offset in endOffsets){
          canvas.drawCircle(offset, 10, paint);
          endTextPainter.paint(canvas, Offset(
            offset.dx - endTextPainter.width / 2,
            offset.dy - endTextPainter.height / 2));
        }
      }
      paint.style = PaintingStyle.stroke;
    }

    final origin =
        camera.project(camera.center).toOffset() - camera.size.toOffset() / 2;

    for (final projectedPolyline in polylines) {
      final polyline = projectedPolyline.polyline;
      final offsets = getOffsetsXY(
        camera: camera,
        origin: origin,
        points: projectedPolyline.points,
      );
      if (offsets.isEmpty) {
        continue;
      }

      final hash = polyline.renderHashCode;
      if (needsLayerSaving || (lastHash != null && lastHash != hash)) {
        drawPaths();
      }
      lastHash = hash;
      needsLayerSaving = polyline.color.a < 1.0 ||
          (polyline.gradientColors?.any((c) => c.a < 1.0) ?? false);

      // strokeWidth, or strokeWidth + borderWidth if relevant.
      late double largestStrokeWidth;

      late final double strokeWidth;
      if (polyline.useStrokeWidthInMeter) {
        strokeWidth = _metersToStrokeWidth(
          origin,
          _unproject(projectedPolyline.points.first),
          offsets.first,
          polyline.strokeWidth,
        );
      } else {
        strokeWidth = polyline.strokeWidth;
      }
      largestStrokeWidth = strokeWidth;

      final isSolid = polyline.pattern == const StrokePattern.solid();
      final isDashed = polyline.pattern.segments != null;
      final isDotted = polyline.pattern.spacingFactor != null;

      paint = Paint()
        ..strokeWidth = strokeWidth
        ..strokeCap = polyline.strokeCap
        ..strokeJoin = polyline.strokeJoin
        ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
        ..blendMode = BlendMode.srcOver;

      if (polyline.gradientColors == null) {
        paint.color = polyline.color;
      } else {
        polyline.gradientColors!.isNotEmpty
            ? paint.shader = _paintGradient(polyline, offsets)
            : paint.color = polyline.color;
      }

      if (polyline.borderStrokeWidth > 0.0) {
        // Outlined lines are drawn by drawing a thicker path underneath, then
        // stenciling the middle (in case the line fill is transparent), and
        // finally drawing the line fill.
        largestStrokeWidth = strokeWidth + polyline.borderStrokeWidth;
        borderPaint = Paint()
          ..color = polyline.borderColor
          ..strokeWidth = strokeWidth + polyline.borderStrokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.srcOver;

        filterPaint = Paint()
          ..color = polyline.borderColor.withAlpha(255)
          ..strokeWidth = strokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.dstOut;
      }

      final radius = paint.strokeWidth / 2;
      final borderRadius = (borderPaint?.strokeWidth ?? 0) / 2;

      final List<ui.Path> paths = [];
      if (borderPaint != null && filterPaint != null) {
        paths.add(borderPath);
        paths.add(filterPath);
      }
      paths.add(path);
      if (isSolid) {
        final SolidPixelHiker hiker = SolidPixelHiker(
          offsets: offsets,
          closePath: false,
          canvasSize: size,
          strokeWidth: largestStrokeWidth,
        );
        hiker.addAllVisibleSegments(paths);
      } else if (isDotted) {
        final DottedPixelHiker hiker = DottedPixelHiker(
          offsets: offsets,
          stepLength: strokeWidth * polyline.pattern.spacingFactor!,
          patternFit: polyline.pattern.patternFit!,
          closePath: false,
          canvasSize: size,
          strokeWidth: largestStrokeWidth,
        );

        final List<double> radii = [];
        if (borderPaint != null && filterPaint != null) {
          radii.add(borderRadius);
          radii.add(radius);
        }
        radii.add(radius);

        for (final visibleDot in hiker.getAllVisibleDots()) {
          for (int i = 0; i < paths.length; i++) {
            paths[i]
                .addOval(Rect.fromCircle(center: visibleDot, radius: radii[i]));
          }
        }
      } else if (isDashed) {
        final DashedPixelHiker hiker = DashedPixelHiker(
          offsets: offsets,
          segmentValues: polyline.pattern.segments!,
          patternFit: polyline.pattern.patternFit!,
          closePath: false,
          canvasSize: size,
          strokeWidth: largestStrokeWidth,
        );

        for (final visibleSegment in hiker.getAllVisibleSegments()) {
          for (final path in paths) {
            path.moveTo(visibleSegment.begin.dx, visibleSegment.begin.dy);
            path.lineTo(visibleSegment.end.dx, visibleSegment.end.dy);
          }
        }
      }
      // スタート，ゴールの両端を記録
      startOffsets.add(offsets.first);
      endOffsets.add(offsets.last);

      // 描画
      drawPaths();
      drawCapCircle();

      // pathとpaintをリセット
      path = ui.Path();
      paint = Paint();
    }
  }

  ui.Gradient _paintGradient(MyPolyline polyline, List<Offset> offsets) =>
      ui.Gradient.linear(offsets.first, offsets.last, polyline.gradientColors!,
          _getColorsStop(polyline));

  List<double>? _getColorsStop(MyPolyline polyline) =>
      (polyline.colorsStop != null &&
              polyline.colorsStop!.length == polyline.gradientColors!.length)
          ? polyline.colorsStop
          : _calculateColorsStop(polyline);

  List<double> _calculateColorsStop(MyPolyline polyline) {
    final colorsStopInterval = 1.0 / polyline.gradientColors!.length;
    return polyline.gradientColors!
        .map((gradientColor) =>
            polyline.gradientColors!.indexOf(gradientColor) *
            colorsStopInterval)
        .toList();
  }

  double _metersToStrokeWidth(
    Offset origin,
    LatLng p0,
    Offset o0,
    double strokeWidthInMeters,
  ) {
    final r = _distance.offset(p0, strokeWidthInMeters, 180);
    final delta = o0 - getOffset(camera, origin, r);
    return delta.distance;
  }

  LatLng _unproject(DoublePoint p0) =>
      camera.crs.projection.unprojectXY(p0.x, p0.y);

  //NOTE: これが true を返さないと、StreamBuilder が走っても再描画されないことがある。
  @override
  bool shouldRepaint(_MyPolylinePainter<R> oldDelegate){
    // NOTE: 本来は this と oldDelegate を比較して変更あるかチェックする。
    // 面倒なので、MyPolyline のフラグに持たせた。
    //NOTE: List<MyPoliline>のひとつでもshuldRepaintがtrueのものがあった場合，必ずtrueをかえす．
    return polylines.any((elements) => elements.polyline.shouldRepaint);
  }
}

const _distance = Distance();
