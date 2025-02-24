import 'dart:core';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/layer/shared/layer_interactivity/internal_hit_detectable.dart';
import 'package:flutter_map/src/layer/shared/layer_projection_simplification/state.dart';
import 'package:flutter_map/src/layer/shared/layer_projection_simplification/widget.dart';
import 'package:flutter_map/src/layer/shared/line_patterns/pixel_hiker.dart';
import 'package:flutter_map/src/misc/offsets.dart';
import 'package:flutter_map/src/misc/simplify.dart';
import 'package:latlong2/latlong.dart';

part 'mypainter.dart';
part 'mypolyline.dart';
part 'myprojected_polyline.dart';

/// A [MyPolyline] (aka. LineString) layer for [FlutterMap].
@immutable
base class MyPolylineLayer<R extends Object>
    extends ProjectionSimplificationManagementSupportedWidget {
  /// [MyPolyline]s to draw
  final List<MyPolyline<R>> polylines;

  /// Acceptable extent outside of viewport before culling polyline segments
  ///
  /// May need to be increased if the [MyPolyline.strokeWidth] +
  /// [MyPolyline.borderStrokeWidth] is large. See online documentation for more
  /// information.
  ///
  /// Defaults to 10. Set to `null` to disable culling.
  final double? cullingMargin;

  /// {@macro fm.lhn.layerHitNotifier.usage}
  final LayerHitNotifier<R>? hitNotifier;

  /// CapCircleを描画するか否か
  final bool showStartCapCircle;
  final bool showEndCapCircle;

  // 画面更新用のストリーム
  Stream<void>? rebuild;

  /// The minimum radius of the hittable area around each [MyPolyline] in logical
  /// pixels
  ///
  /// The entire visible area is always hittable, but if the visible area is
  /// smaller than this, then this will be the hittable area.
  ///
  /// Defaults to 10.
  final double minimumHitbox;

  /// Create a new [MyPolylineLayer] to use as child inside [FlutterMap.children].
  MyPolylineLayer({
    super.key,
    required this.polylines,
    this.cullingMargin = 10,
    this.hitNotifier,
    this.minimumHitbox = 10,
    this.showStartCapCircle = false,
    this.showEndCapCircle = false,
    this.rebuild,
    super.simplificationTolerance,
  }) : super();

  @override
  State<MyPolylineLayer<R>> createState() => _MyPolylineLayerState<R>();
}

class _MyPolylineLayerState<R extends Object> extends State<MyPolylineLayer<R>>
    with
        ProjectionSimplificationManagement<_MyProjectedPolyline<R>, MyPolyline<R>,
            MyPolylineLayer<R>> {
  @override
  _MyProjectedPolyline<R> projectElement({
    required Projection projection,
    required MyPolyline<R> element,
  }) =>
      _MyProjectedPolyline._fromPolyline(projection, element);

  @override
  _MyProjectedPolyline<R> simplifyProjectedElement({
    required _MyProjectedPolyline<R> projectedElement,
    required double tolerance,
  }) =>
      _MyProjectedPolyline._(
        polyline: projectedElement.polyline,
        points: simplifyPoints(
          points: projectedElement.points,
          tolerance: tolerance,
          highQuality: true,
        ),
      );

  @override
  Iterable<MyPolyline<R>> getElements(MyPolylineLayer<R> widget) =>
      widget.polylines;

  @override
  void initState() {
    // 画面再描画用にstreamを監視する
    widget.rebuild?.listen((value) => setState(() { }));
    
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final camera = MapCamera.of(context);

    final culled = widget.cullingMargin == null
        ? simplifiedElements.toList()
        : _aggressivelyCullPolylines(
            projection: camera.crs.projection,
            polylines: simplifiedElements,
            camera: camera,
            cullingMargin: widget.cullingMargin!,
          ).toList();

    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _MyPolylinePainter(
          polylines: culled,
          camera: camera,
          hitNotifier: widget.hitNotifier,
          minimumHitbox: widget.minimumHitbox,
          showStartCapCircle: widget.showStartCapCircle,
          showEndCapCircle: widget.showEndCapCircle,
        ),
        size: Size(camera.size.x, camera.size.y),
      ),
    );
  }

  Iterable<_MyProjectedPolyline<R>> _aggressivelyCullPolylines({
    required Projection projection,
    required Iterable<_MyProjectedPolyline<R>> polylines,
    required MapCamera camera,
    required double cullingMargin,
  }) sync* {
    final bounds = camera.visibleBounds;
    final margin = cullingMargin / math.pow(2, camera.zoom);

    // The min(-90), max(180), ... are used to get around the limits of LatLng
    // the value cannot be greater or smaller than that
    final boundsAdjusted = LatLngBounds.unsafe(
      west: math.max(LatLngBounds.minLongitude, bounds.west - margin),
      east: math.min(LatLngBounds.maxLongitude, bounds.east + margin),
      south: math.max(LatLngBounds.minLatitude, bounds.south - margin),
      north: math.min(LatLngBounds.maxLatitude, bounds.north + margin),
    );

    // segment is visible
    final projBounds = Bounds(
      projection.project(boundsAdjusted.southWest),
      projection.project(boundsAdjusted.northEast),
    );

    for (final projectedPolyline in polylines) {
      final polyline = projectedPolyline.polyline;

      // Gradient poylines cannot be easily segmented
      if (polyline.gradientColors != null) {
        yield projectedPolyline;
        continue;
      }

      // pointer that indicates the start of the visible polyline segment
      int start = -1;
      bool containsSegment = false;
      for (int i = 0; i < projectedPolyline.points.length - 1; i++) {
        // Current segment (p1, p2).
        final p1 = projectedPolyline.points[i];
        final p2 = projectedPolyline.points[i + 1];

        containsSegment = projBounds.aabbContainsLine(p1.x, p1.y, p2.x, p2.y);
        if (containsSegment) {
          if (start == -1) {
            start = i;
          }
        } else {
          // If we cannot see this segment but have seen previous ones, flush the last polyline fragment.
          if (start != -1) {
            yield _MyProjectedPolyline._(
              polyline: polyline,
              points: projectedPolyline.points.sublist(start, i + 1),
            );

            // Reset start.
            start = -1;
          }
        }
      }

      // If the last segment was visible push that last visible polyline
      // fragment, which may also be the entire polyline if `start == 0`.
      if (containsSegment) {
        yield start == 0
            ? projectedPolyline
            : _MyProjectedPolyline._(
                polyline: polyline,
                // Special case: the entire polyline is visible
                points: projectedPolyline.points.sublist(start),
              );
      }
    }
  }
}
