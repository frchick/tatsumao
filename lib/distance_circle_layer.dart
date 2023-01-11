import 'dart:async';   // Stream使った再描画
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart'; // Colors

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/map/map.dart';
import 'package:latlong2/latlong.dart';

class DistanceCircleLayerOptions extends LayerOptions
{
  DistanceCircleLayerOptions({
    Key? key,
    required StreamController<void> stream,
    required this.mapController
  }) :
    _stream = stream,
    super(key: key, rebuild: stream.stream)
  {}

  final MapController mapController;
  
  // 表示/非表示
  bool show = true;

  //----------------------------------------------------------------------------
  // 再描画用の Stream
  late StreamController<void> _stream;
  // 再描画
  void redraw()
  {
    _stream.sink.add(null);
  }
}

// flutter_map のプラグインとしてレイヤーを実装
class DistanceCircleLayerPlugin implements MapPlugin
{
  @override
  bool supportsLayer(LayerOptions options) {
    return options is DistanceCircleLayerOptions;
  }

  @override
  Widget createLayer(LayerOptions options, MapState map, Stream<void> stream) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size, options as DistanceCircleLayerOptions, map, stream);
      },
    );
  }

  Widget _build(
    BuildContext context, Size size,
    DistanceCircleLayerOptions opts, MapState map, Stream<void> stream)
  {
    return StreamBuilder<void>(
      stream: stream, // a Stream<void> or null
      builder: (BuildContext context, _)
      {
        Widget painter = CustomPaint(
            painter: DistanceCirclePainter(opts:opts),
            size: size,
            willChange: true);

        return painter;
      },
    );
  }
}

class DistanceCirclePainter extends CustomPainter
{
  DistanceCirclePainter({ required this.opts });

  final DistanceCircleLayerOptions opts;

  @override
  void paint(Canvas canvas, Size size)
  {
    // 非表示なら何もしない
    if(!opts.show) return;

    // 表示しているマップの範囲(距離)を計算
    // (縦横の長い方+10%マージン基準)
    final double halfWidth = size.width / 2;
    final double halfHeight = size.height / 2;
    late double screenWidth;
    late LatLng? pos0, pos1;
    final bool heightFit = (size.width <= size.height);
    final MapController map = opts.mapController;
    const double margin = 1.1;
    if(heightFit){
      // 高さフィット
      screenWidth = margin * size.height;
      pos0 = map.pointToLatLng(CustomPoint(halfWidth, 0));
      pos1 = map.pointToLatLng(CustomPoint(halfWidth, screenWidth));
    }else{
      // 幅フィット
      screenWidth = margin * size.width;
      pos0 = map.pointToLatLng(CustomPoint(0, halfHeight));
      pos1 = map.pointToLatLng(CustomPoint(screenWidth, halfHeight));
    }
    final screenDist = calculateDistance(pos0, pos1);

    // 距離サークルの半径を計算
    final double R = selectCircleR(screenDist);

    // ドット数換算
    final double screenR = R * screenWidth / screenDist;

    // 十字と距離サークルを描画
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = Color(0x80000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, halfHeight), Offset(size.width, halfHeight), paint);
    canvas.drawLine(Offset(halfWidth, 0), Offset(halfWidth, size.height), paint);
    // R/2 毎の同心円
    int si = 1;
    final double maxR = sqrt(pow(size.width, 2) + pow(size.height, 2)) / 2;
    while(true){
      final double cr = (si / 2) * screenR;
      if(maxR < cr) break;
      canvas.drawCircle(Offset(size.width/2, size.height/2), cr, paint);

      // 距離数値
      if(((si % 2) == 0) || (si <= 3)){
        final double r = (si / 2) * R;
        late Offset p;
        drawDistanceNum(canvas, Offset(halfWidth, halfHeight+cr), r);
        drawDistanceNum(canvas, Offset(halfWidth-cr, halfHeight), r);
      }

      si += 1;
    }
  }

  // 距離数値の表示
  void drawDistanceNum(Canvas canvas, Offset pos, double D)
  {
    late String text;
    if(D < 1000){
      text = D.toString() + "m";
    }else{
      text = (D / 1000).toString() + "Km";
    }

    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xD0000000),
        fontSize: 14,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, pos + Offset(4, 2));
  }

  // 緯度経度で表される2地点間の距離を計算
  double calculateDistance(LatLng? pos1, LatLng? pos2)
  {
    if((pos1 == null) || (pos2 == null)) return 1.0;

    var a = (0.5 - _cos(pos2.latitude - pos1.latitude)/2) + 
          _cos(pos1.latitude) *
          _cos(pos2.latitude) * 
          (1 - _cos(pos2.longitude - pos1.longitude))/2;
    const R = 12742000;        // 地球の直径
    return R * asin(sqrt(a));  // [m]
  }

  double _cos(double deg)
  {
    var p = 0.017453292519943295; // π/180
    return cos(deg * p);
  }

  // 画面幅に応じた距離サークルの半径の選択
  double selectCircleR(double screenW)
  {
    // 半径の計算のために、画面幅を半分に
    final screenR = screenW / 2;
    
    // 数列の中から、画面幅に収まる最大の半径を選択
    // 最大100Km(100,000m)まで比較
    double selectR = 8.0;
    var numSeq = const [ 1.0, 2.0, 4.0, 8.0 ];
    for(int i=0; i<=(4*4); i++){
      int digit = 1 + (i ~/ 4);
      int num = (i % 4);
      double r = numSeq[num] * pow(10, digit);
      if(screenR < r) break;
      selectR = r;
    }
    return selectR;
  }

  //NOTE: これが true を返さないと、StreamBuilder が走っても再描画されないことがある。
  @override
  bool shouldRepaint(DistanceCirclePainter oldDelegate)
  {
    return true;
  }
}
