import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'mydrag_marker.dart';
import 'mydrag_marker_widget.dart';

class MyDragMarkers extends StatelessWidget {
  MyDragMarkers({
    super.key,
    this.markers = const [],
    this.draggable = true,
    this.visible = true,
    this.alignment = Alignment.center,
  });

  /// The markers that are to be displayed on the map.
  final List<MyDragMarker> markers;
  // ドラッグを許可するか
  bool draggable;
  // マーカー全体の表示/非表示
  bool visible;

  /// Alignment of each marker relative to its normal center at [MyDragMarker.point].
  ///
  /// For example, [Alignment.topCenter] will mean the entire marker widget is
  /// located above the [MyDragMarker.point].
  ///
  /// The center of rotation (anchor) will be opposite this.
  ///
  /// Defaults to [Alignment.center]. Overriden by [MyDragMarker.alignment] if set.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final mapController = MapController.maybeOf(context) ??
        (throw StateError(
            '`DragMarkers` is a map layer and should not be build outside '
            'a `FlutterMap` context.'));
    final mapCamera = MapCamera.maybeOf(context) ??
        (throw StateError(
            '`DragMarkers` is a map layer and should not be build outside '
            'a `FlutterMap` context.'));
    return Stack(
      children: markers
          // 非表示の物を除外
          .where(
            (marker) => marker.visible,
          )
          // 画面外のマーカーは除外
          .where(
            (marker) => marker.inMapBounds(
              mapCamera: mapController.camera,
              markerWidgetAlignment: alignment,
            ),
          )
          // 画面に見えるマーカーを作成
          // NOTE: 毎フレーム作成するのは無駄に感じるが、この中で表示座標の計算もしているのでキャッシュできない。
          .map((marker) => MyDragMarkerWidget(
                key: marker.key,
                marker: marker,
                mapCamera: mapCamera,
                mapController: mapController,
                alignment: alignment,
                draggable: draggable,
              ))
          .toList(growable: false),
    );
  }
}
