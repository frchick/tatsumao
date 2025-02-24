import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'mydrag_marker.dart';

class MyDragMarkerWidget extends StatefulWidget {
  MyDragMarkerWidget({
    super.key,
    required this.marker,
    required this.mapCamera,
    required this.mapController,
    this.draggable = false,
    this.alignment = Alignment.center,
  });

  /// The marker that is to be displayed on the map.
  final MyDragMarker marker;

  /// The controller of the map that is used to move the map on pan events.
  final MapController mapController;

  /// The camera of the map that provides the current map state.
  final MapCamera mapCamera;

  /// Alignment of each marker relative to its normal center at [MyDragMarker.point].
  ///
  /// For example, [Alignment.topCenter] will mean the entire marker widget is
  /// located above the [MyDragMarker.point].
  ///
  /// The center of rotation (anchor) will be opposite this.
  ///
  /// Defaults to [Alignment.center]. Overriden by [MyDragMarker.alignment] if set.
  final Alignment alignment;

  // 移動できるかどうか
  bool draggable;

  @override
  State<MyDragMarkerWidget> createState() => MyDragMarkerWidgetState();
}

class MyDragMarkerWidgetState extends State<MyDragMarkerWidget> {
  var pixelPosition = const Point<double>(0, 0);
  late LatLng _dragPosStart;
  late LatLng _markerPointStart;
  bool _isDragging = false;

  /// this marker scrolls the map if [marker.scrollMapNearEdge] is set to true
  /// and gets dragged near to an edge. It needs to be static because only one
  static Timer? _mapScrollTimer;

  LatLng get markerPoint => widget.marker.point;

  @override
  Widget build(BuildContext context) {
    final marker = widget.marker;
    _updatePixelPos(markerPoint);

    final displayMarker = marker.builder(context, marker.point, _isDragging);

    // ドラッグ移動の可否
    final bool draggable = widget.draggable;

    return MobileLayerTransformer(
      child: GestureDetector(
        // drag detectors
        onVerticalDragStart: marker.useLongPress ? null : ((draggable) ? _onPanStart : null),
        onVerticalDragUpdate: marker.useLongPress ? null : ((draggable) ? _onPanUpdate : null),
        onVerticalDragEnd: marker.useLongPress ? null : ((draggable) ? _onPanEnd : null),
        onHorizontalDragStart: marker.useLongPress ? null : ((draggable) ? _onPanStart : null),
        onHorizontalDragUpdate: marker.useLongPress ? null : ((draggable) ? _onPanUpdate : null),
        onHorizontalDragEnd: marker.useLongPress ? null : ((draggable) ? _onPanEnd : null),
        // long press detectors
        onLongPressStart: marker.useLongPress ? ((draggable) ? _onLongPanStart : null) : null,
        onLongPressMoveUpdate: marker.useLongPress ? ((draggable) ? _onLongPanUpdate : null) : null,
        onLongPressEnd: marker.useLongPress ? ((draggable) ? _onLongPanEnd : null) : null,
        // user callbacks
        onTap: () => marker.onTap?.call(markerPoint, marker.index),
        onLongPress: () => marker.onLongPress?.call(markerPoint, marker.index),
        // child widget
        /* using Stack while the layer widget MarkerWidgets already
            introduces a Stack to the widget tree, try to use decrease the amount
            of Stack widgets in the future. */
        child: Stack(
          children: [
            Positioned(
              width: marker.size.width,
              height: marker.size.height,
              left: pixelPosition.x,
              top: pixelPosition.y,
              child: marker.rotateMarker
                  ? Transform.rotate(
                      angle: -widget.mapCamera.rotationRad,
                      alignment: (marker.alignment ?? widget.alignment) * -1,
                      child: displayMarker,
                    )
                  : displayMarker,
            )
          ],
        ),
      ),
    );
  }

  void _updatePixelPos(point) {
    final marker = widget.marker;
    final map = widget.mapCamera;

    final pxPoint = map.project(point);

    final left = 0.5 *
        marker.size.width *
        ((marker.alignment ?? widget.alignment).x + 1);
    final top = 0.5 *
        marker.size.height *
        ((marker.alignment ?? widget.alignment).y + 1);
    final right = marker.size.width - left;
    final bottom = marker.size.height - top;

    final pos = Point(pxPoint.x - map.pixelOrigin.toDoublePoint().x, pxPoint.y - map.pixelOrigin.toDoublePoint().y);
    pixelPosition = Point(pos.x - right, pos.y - bottom);
  }

  void _start(Offset localPosition) {
    _isDragging = true;
    _dragPosStart = _offsetToCrs(localPosition);
    _markerPointStart = LatLng(markerPoint.latitude, markerPoint.longitude);
  }

  void _onPanStart(DragStartDetails details) {
    _start(details.localPosition);
    widget.marker.onDragStart?.call(details, markerPoint, widget.marker.index);
  }

  void _onLongPanStart(LongPressStartDetails details) {
    _start(details.localPosition);
    widget.marker.onLongDragStart?.call(details, markerPoint);
  }

  void _pan(Offset localPosition) {
    final dragPos = _offsetToCrs(localPosition);

    final deltaLat = dragPos.latitude - _dragPosStart.latitude;
    final deltaLon = dragPos.longitude - _dragPosStart.longitude;

    // If we're near an edge, move the map to compensate
    if (widget.marker.scrollMapNearEdge) {
      final scrollOffset = _getMapScrollOffset();
      // start the scroll timer if scrollOffset is not zero
      if (scrollOffset != Offset.zero) {
        _mapScrollTimer ??= Timer.periodic(
          const Duration(milliseconds: 20),
          _mapScrollTimerCallback,
        );
      }
    }

    setState(() {
      widget.marker.point = LatLng(
        _markerPointStart.latitude + deltaLat,
        _markerPointStart.longitude + deltaLon,
      );
      _updatePixelPos(markerPoint);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _pan(details.localPosition);
    widget.marker.onDragUpdate?.call(details, markerPoint, widget.marker.index);
  }

  void _onLongPanUpdate(LongPressMoveUpdateDetails details) {
    _pan(details.localPosition);
    widget.marker.onLongDragUpdate?.call(details, markerPoint);
  }

  void _onPanEnd(details) {
    _end();
    LatLng pos = widget.marker.onDragEnd?.call(details, markerPoint, widget.marker.index) ?? widget.marker.point;
    if(pos != widget.marker.point)
      setState(() {
        widget.marker.point = pos;
      });
  }

  void _onLongPanEnd(details) {
    _end();
    widget.marker.onLongDragEnd?.call(details, markerPoint);
  }

  void _end() {
    // setState is needed if using a different widget while dragging
    setState(() {
      _isDragging = false;
    });
  }

  /// If dragging near edge of the screen, adjust the map so we keep dragging
  void _mapScrollTimerCallback(Timer timer) {
    final mapState = widget.mapCamera;
    final scrollOffset = _getMapScrollOffset();

    // cancel conditions
    if (!_isDragging ||
        timer != _mapScrollTimer ||
        scrollOffset == Offset.zero ||
        !widget.marker.inMapBounds(
          mapCamera: mapState,
          markerWidgetAlignment: widget.alignment,
        )) {
      timer.cancel();
      _mapScrollTimer = null;
      return;
    }

    // update marker position
    final oldMarkerPoint = mapState.project(markerPoint);
    widget.marker.point = mapState.unproject(Point(
      oldMarkerPoint.x + scrollOffset.dx,
      oldMarkerPoint.y + scrollOffset.dy,
    ));

    // scroll map
    final oldMapPos = mapState.project(mapState.center);
    final newMapLatLng = mapState.unproject(Point(
      oldMapPos.x + scrollOffset.dx,
      oldMapPos.y + scrollOffset.dy,
    ));
    widget.mapController.move(newMapLatLng, mapState.zoom);
  }

  LatLng _offsetToCrs(Offset offset) {
    // Get the widget's offset
    final renderObject = context.findRenderObject() as RenderBox;
    final width = renderObject.size.width;
    final height = renderObject.size.height;
    final mapState = widget.mapCamera;

    // convert the point to global coordinates
    final localPoint = Point<double>(offset.dx, offset.dy);
    final localPointCenterDistance = Point<double>((width / 2) - localPoint.x, (height / 2) - localPoint.y);
    final mapCenter = mapState.project(mapState.center);
    final point = mapCenter - localPointCenterDistance;
    return mapState.unproject(point);
  }

  /// this method is used for [marker.scrollMapNearEdge]. It checks if the
  /// marker is near an edge and returns the offset that the map should get
  /// scrolled.
  Offset _getMapScrollOffset() {
    final marker = widget.marker;
    final mapState = widget.mapCamera;

    final pixelB = widget.mapCamera.pixelBounds;
    final pixelPoint = mapState.project(markerPoint);
    // How much we'll move the map by to compensate
    var scrollMapX = 0.0;
    if (pixelPoint.x + marker.size.width * marker.scrollNearEdgeRatio >= pixelB.topRight.x) {
      scrollMapX = marker.scrollNearEdgeSpeed;
    } else if (pixelPoint.x - marker.size.width * marker.scrollNearEdgeRatio <= pixelB.bottomLeft.x) {
      scrollMapX = -marker.scrollNearEdgeSpeed;
    }
    var scrollMapY = 0.0;
    if (pixelPoint.y - marker.size.height * marker.scrollNearEdgeRatio <= pixelB.topRight.y) {
      scrollMapY = -marker.scrollNearEdgeSpeed;
    } else if (pixelPoint.y + marker.size.height * marker.scrollNearEdgeRatio >= pixelB.bottomLeft.y) {
      scrollMapY = marker.scrollNearEdgeSpeed;
    }
    return Offset(scrollMapX, scrollMapY);
  }
}
