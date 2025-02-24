import 'dart:math';

import 'package:flutter/material.dart'; // Colors

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DistanceCircleLayer extends StatefulWidget
{
  // StatefulWidgetからステートの関数を実行するためのグローバルキー
  final GlobalKey<_DistanceCircleLayerState> key = GlobalKey<_DistanceCircleLayerState>();

  DistanceCircleLayer({ Key? key, required this.mapController }) : super(key: key);

  final MapController mapController;

  @override
  State<StatefulWidget> createState() => _DistanceCircleLayerState();
  
  // 表示/非表示
  bool show = true;

  //----------------------------------------------------------------------------
  // 再描画
  void redraw()
  {
    key.currentState?.redraw();
  }
}

// flutter_map のプラグインとしてレイヤーを実装
class _DistanceCircleLayerState extends State<DistanceCircleLayer>
{
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size);
      },
    );
  }

  void redraw(){
    setState(() { });
  }

  Widget _build(
    BuildContext context, Size size)
  {
    return  CustomPaint(
        painter: DistanceCirclePainter(opts:widget),
        size: size,
        willChange: true
    );
  }
}

class DistanceCirclePainter extends CustomPainter
{
  DistanceCirclePainter({ required this.opts });

  final DistanceCircleLayer opts;

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
      pos0 = map.camera.pointToLatLng(Point(halfWidth, 0));
      pos1 = map.camera.pointToLatLng(Point(halfWidth, screenWidth));
    }else{
      // 幅フィット
      screenWidth = margin * size.width;
      pos0 = map.camera.pointToLatLng(Point(0, halfHeight));
      pos1 = map.camera.pointToLatLng(Point(screenWidth, halfHeight));
    }
    if((pos0 == null) || (pos1 == null)) return;
    const distance = Distance();
    final screenDist = distance(pos0, pos1);

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

  //TODO: StatefulWidget化に伴い，下記が本当に必要か調査
  //NOTE: これが true を返さないと、StreamBuilder が走っても再描画されないことがある。
  @override
  bool shouldRepaint(DistanceCirclePainter oldDelegate)
  {
    return true;
  }
}
