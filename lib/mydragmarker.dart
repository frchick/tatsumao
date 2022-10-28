import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';

class MyDragMarkerPluginOptions extends LayerOptions {
  // マーカー一覧
  List<MyDragMarker> markers;
  // ドラッグを許可するか
  bool draggable;
  // マーカー全体の表示/非表示
  bool visible;

  MyDragMarkerPluginOptions({
    this.markers = const [],
    this.draggable = true,
    this.visible = true,
  });
}

class MyDragMarkerPlugin implements MapPlugin {
  @override
  Widget createLayer(LayerOptions options, MapState mapState, stream) {
    if (options is MyDragMarkerPluginOptions) {
      // 画面が移動やズームすると毎フレームこのビルドが実行される！！
      return StreamBuilder<void>(
        stream: stream,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot)
        {
          var dragMarkers = <Widget>[];
          if(options.visible){
            for (var marker in options.markers) {
              // 非表示のマーカーは除外
              if(!marker.visible) continue;

              // 画面外のマーカーは除外
              if (!_boundsContainsMarker(mapState, marker)) continue;

              // 画面に見えるマーカーを作成
              // NOTE: 毎フレーム作成するのは無駄に感じるが、この中で表示座標の計算もしているのでキャッシュできない。
              dragMarkers.add(MyDragMarkerWidget(
                mapState: mapState,
                marker: marker,
                stream: stream,
                options: options));
            }
          }
          return Stack(children: dragMarkers);
        }
      );
    }

    throw Exception('Unknown options type for MyCustom'
        'plugin: $options');
  }

  @override
  bool supportsLayer(LayerOptions options) {
    return options is MyDragMarkerPluginOptions;
  }

  static bool _boundsContainsMarker(MapState map, MyDragMarker marker) {
    var pixelPoint = map.project(marker.point);

    final width = marker.width - marker.anchor.left;
    final height = marker.height - marker.anchor.top;

    var sw = CustomPoint(pixelPoint.x + width, pixelPoint.y - height);
    var ne = CustomPoint(pixelPoint.x - width, pixelPoint.y + height);

    return map.pixelBounds.containsPartialBounds(Bounds(sw, ne));
  }
}

class MyDragMarkerWidget extends StatefulWidget
{
  const MyDragMarkerWidget(
      {Key? key,
      this.mapState,
      required this.marker,
      AnchorPos? anchorPos,
      this.stream,
      this.options})
      //: anchor = Anchor.forPos(anchorPos, marker.width, marker.height);
      : super(key: key);

  final MapState? mapState;
  //final Anchor anchor;
  final MyDragMarker marker;
  final Stream<void>? stream;
  final MyDragMarkerPluginOptions? options;

  @override
  State<MyDragMarkerWidget> createState() => _MyDragMarkerWidgetState();
}

class _MyDragMarkerWidgetState extends State<MyDragMarkerWidget>
{
  CustomPoint pixelPosition = const CustomPoint(0.0, 0.0);
  late LatLng dragPosStart;
  late LatLng markerPointStart;
  late LatLng oldDragPosition;
  bool isDragging = false;
  Offset lastLocalOffset = Offset(0.0, 0.0);

  static Timer? autoDragTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    MyDragMarker marker = widget.marker;
    updatePixelPos(widget.marker.point);

    bool feedBackEnabled = isDragging && marker.feedbackBuilder != null;
    Widget displayMarker = feedBackEnabled
        ? marker.feedbackBuilder!(context)
        : marker.builder!(context);

    final bool draggable = widget.options?.draggable ?? true;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onPanStart: (draggable? onPanStart: null),
      onPanUpdate: (draggable? onPanUpdate: null),
      onPanEnd: (draggable? onPanEnd: null),
      onTap: () {
        if (marker.onTap != null) {
          marker.onTap!(marker.point, marker.index);
        }
      },
      onLongPress: () {
        if (marker.onLongPress != null) {
          marker.onLongPress!(marker.point, marker.index);
        }
      },
      child: Stack(children: [
        Positioned(
            width: marker.width,
            height: marker.height,
            left: pixelPosition.x +
                ((isDragging) ? marker.feedbackOffset.dx : marker.offset.dx),
            top: pixelPosition.y +
                ((isDragging) ? marker.feedbackOffset.dy : marker.offset.dy),
            child: widget.marker.rotateMarker
                ? Transform.rotate(
                    angle: -widget.mapState!.rotationRad, child: displayMarker)
                : displayMarker)
      ]),
    );
  }

  void updatePixelPos(point) {
    MyDragMarker marker = widget.marker;
    MapState? mapState = widget.mapState;

    CustomPoint pos;
    if (mapState != null) {
      pos = mapState.project(point);
      pos =
          pos.multiplyBy(mapState.getZoomScale(mapState.zoom, mapState.zoom)) -
              mapState.getPixelOrigin();

      pixelPosition = CustomPoint(
          (pos.x - (marker.width - widget.marker.anchor.left)).toDouble(),
          (pos.y - (marker.height - widget.marker.anchor.top)).toDouble());
    }
  }

  void onPanStart(DragStartDetails details) {
    isDragging = true;
    dragPosStart = _offsetToCrs(details.localPosition);
    markerPointStart =
        LatLng(widget.marker.point.latitude, widget.marker.point.longitude);

    lastLocalOffset = details.localPosition;

    if (widget.marker.onDragStart != null) {
      widget.marker.onDragStart!(details, widget.marker.point, widget.marker.index);
    }
  }

  void onPanUpdate(DragUpdateDetails details) {
    bool isDragging = true;
    MyDragMarker marker = widget.marker;
    MapState? mapState = widget.mapState;

    var dragPos = _offsetToCrs(details.localPosition);

    var deltaLat = dragPos.latitude - dragPosStart.latitude;
    var deltaLon = dragPos.longitude - dragPosStart.longitude;

    var pixelB = mapState?.getLastPixelBounds();
    var pixelPoint = mapState?.project(widget.marker.point);

    /// If we're near an edge, move the map to compensate.

    if (marker.updateMapNearEdge) {
      /// How much we'll move the map by to compensate

      var autoOffsetX = 0.0;
      var autoOffsetY = 0.0;
      if (pixelB != null && pixelPoint != null) {
        if (pixelPoint.x + marker.width * marker.nearEdgeRatio >=
            pixelB.topRight.x) autoOffsetX = marker.nearEdgeSpeed;
        if (pixelPoint.x - marker.width * marker.nearEdgeRatio <=
            pixelB.bottomLeft.x) autoOffsetX = -marker.nearEdgeSpeed;
        if (pixelPoint.y - marker.height * marker.nearEdgeRatio <=
            pixelB.topRight.y) autoOffsetY = -marker.nearEdgeSpeed;
        if (pixelPoint.y + marker.height * marker.nearEdgeRatio >=
            pixelB.bottomLeft.y) autoOffsetY = marker.nearEdgeSpeed;
      }

      /// Sometimes when dragging the onDragEnd doesn't fire, so just stops dead.
      /// Here we allow a bit of time to keep dragging whilst user may move
      /// around a bit to keep it going.

      var lastTick = 0;
      if (autoDragTimer != null) lastTick = autoDragTimer!.tick;

      if ((autoOffsetY != 0.0) || (autoOffsetX != 0.0)) {
        adjustMapToMarker(widget, autoOffsetX, autoOffsetY);

        if ((autoDragTimer == null || autoDragTimer?.isActive == false) &&
            (isDragging == true)) {
          autoDragTimer =
              Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
            var tick = autoDragTimer?.tick;
            bool tickCheck = false;
            if (tick != null) {
              if (tick > lastTick + 15) {
                tickCheck = true;
              }
            }
            if (isDragging == false || tickCheck) {
              autoDragTimer?.cancel();
            } else {
              /// Note, we may have adjusted a few lines up in same drag,
              /// so could test for whether we've just done that
              /// this, but in reality it seems to work ok as is.

              adjustMapToMarker(widget, autoOffsetX, autoOffsetY);
            }
          });
        }
      }
    }

    setState(() {
      marker.point = LatLng(markerPointStart.latitude + deltaLat,
          markerPointStart.longitude + deltaLon);
      updatePixelPos(marker.point);
    });

    lastLocalOffset = details.localPosition;

    if (marker.onDragUpdate != null) {
      marker.onDragUpdate!(details, marker.point, widget.marker.index);
    }
  }

  /// If dragging near edge of the screen, adjust the map so we keep dragging
  void adjustMapToMarker(MyDragMarkerWidget widget, autoOffsetX, autoOffsetY) {
    MyDragMarker marker = widget.marker;
    MapState? mapState = widget.mapState;

    var oldMapPos = mapState?.project(mapState.center);
    LatLng? newMapLatLng;
    CustomPoint<num>? oldMarkerPoint;
    if (oldMapPos != null) {
      newMapLatLng = mapState?.unproject(
          CustomPoint(oldMapPos.x + autoOffsetX, oldMapPos.y + autoOffsetY));
      oldMarkerPoint = mapState?.project(marker.point);
    }
    if (mapState != null && newMapLatLng != null && oldMarkerPoint != null) {
      marker.point = mapState.unproject(CustomPoint(
          oldMarkerPoint.x + autoOffsetX, oldMarkerPoint.y + autoOffsetY));

      mapState.move(newMapLatLng, mapState.zoom, source: MapEventSource.onDrag);
    }
  }

  void onPanEnd(DragEndDetails details) {
    isDragging = false;
    if (autoDragTimer != null) autoDragTimer?.cancel();
    if (widget.marker.onDragEnd != null) {
      MapState? mapState = widget.mapState;
      int index = widget.marker.index;
      widget.marker.point = widget.marker.onDragEnd!(details, widget.marker.point, lastLocalOffset, index, mapState);
    }
    setState(() {}); // Needed if using a feedback widget
  }

  static CustomPoint _offsetToPoint(Offset offset) {
    return CustomPoint(offset.dx, offset.dy);
  }

  LatLng _offsetToCrs(Offset offset) {
    // Get the widget's offset
    var renderObject = context.findRenderObject() as RenderBox;
    var width = renderObject.size.width;
    var height = renderObject.size.height;
    var mapState = widget.mapState;

    // convert the point to global coordinates
    var localPoint = _offsetToPoint(offset);
    var localPointCenterDistance =
        CustomPoint((width / 2) - localPoint.x, (height / 2) - localPoint.y);
    if (mapState != null) {
      var mapCenter = mapState.project(mapState.center);
      var point = mapCenter - localPointCenterDistance;
      return mapState.unproject(point);
    }
    return LatLng(0, 0);
  }
}

class MyDragMarker {
  LatLng point;
  final WidgetBuilder? builder;
  final WidgetBuilder? feedbackBuilder;
  final double width;
  final double height;
  final Offset offset;
  final Offset feedbackOffset;
  // NOTE: 派生クラスでメンバー変数を代入するため、final を外した
  /*final*/ Function(DragStartDetails, LatLng, int)? onDragStart;
  /*final*/ Function(DragUpdateDetails, LatLng, int)? onDragUpdate;
  /*final*/ LatLng Function(DragEndDetails, LatLng, Offset, int, MapState?)? onDragEnd;
  /*final*/ Function(LatLng, int)? onTap;
  /*final*/ Function(LatLng, int)? onLongPress;
  final bool updateMapNearEdge;
  final double nearEdgeRatio;
  final double nearEdgeSpeed;
  final bool rotateMarker;
  late Anchor anchor;
  final int index;
  bool visible;

  MyDragMarker({
    required this.point,
    this.builder,
    this.feedbackBuilder,
    this.width = 30.0,
    this.height = 30.0,
    this.offset = const Offset(0.0, 0.0),
    this.feedbackOffset = const Offset(0.0, 0.0),
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
    this.onLongPress,
    this.updateMapNearEdge = false, // experimental
    this.nearEdgeRatio = 1.5,
    this.nearEdgeSpeed = 1.0,
    this.rotateMarker = true,
    AnchorPos? anchorPos,
    required this.index,
    this.visible = true,
  }) {
    anchor = Anchor.forPos(anchorPos, width, height);
  }
}
