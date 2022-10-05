import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:xml/xml.dart';
import 'firebase_options.dart';
import 'mydragmarker.dart';
import 'mydrag_target.dart';
import 'dart:async';
import 'package:flutter/services.dart';

//----------------------------------------------------------------------------
// グローバル変数

// アイコンボタン共通のスタイル
final ButtonStyle _appIconButtonStyle = ElevatedButton.styleFrom(
  foregroundColor: Colors.orange.shade900,
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  fixedSize: Size(80,80),
);

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマデータ
class TatsumaData {
  TatsumaData(
    this.pos,
    this.name,
    this.visible,
  );

  // 座標
  LatLng pos;
  // 名前
  String name;
  // 表示/非表示
  bool visible;
}

// タツマの適当な初期データ。
List<TatsumaData> tatsumas = [
  TatsumaData(LatLng(35.306227, 139.049396), "岩清水索道", true),
  TatsumaData(LatLng(35.307217, 139.051598), "岩清水中", true),
  TatsumaData(LatLng(35.306809, 139.052676), "岩清水下", true),
  TatsumaData(LatLng(35.306282, 139.047802), "岩清水", true),
  TatsumaData(LatLng(35.305798, 139.054232), "赤エル", true),
  TatsumaData(LatLng(35.30636, 139.05427), "裏赤エル", true),
  TatsumaData(LatLng(35.305804, 139.055972), "ストッパー", true),
  TatsumaData(LatLng(35.304213, 139.046478), "新トナカイ", true),
  TatsumaData(LatLng(35.305561, 139.045259), "トナカイ", true),
  TatsumaData(LatLng(35.302601, 139.04473), "ムロ岩の先", true),
  TatsumaData(LatLng(35.302488, 139.044131), "ムロ岩", true),
  TatsumaData(LatLng(35.301932, 139.043382), "スター", true),
  TatsumaData(LatLng(35.301166, 139.043601), "アメリカ", true),
  TatsumaData(LatLng(35.300012, 139.044023), "太平洋", true),
  TatsumaData(LatLng(35.30026, 139.046538), "メキシコ", true),
  TatsumaData(LatLng(35.29942, 139.04639), "沢の上", true),
];

// マップ上のタツマのマーカー配列
List<Marker> tatsumaMarkers = [];

// タツマデータの保存と読み込みデータベース
FirebaseDatabase database = FirebaseDatabase.instance;

//----------------------------------------------------------------------------
// 座標からタツマデータを参照
TatsumaData? searchTatsumaByPoint(LatLng point)
{
  // 同じ座標のタツマを探して返す。
  // 誤差0.0001度(約1[m])での一致判定。
  const double th = (0.0001 * 0.0001) + (0.0001 * 0.0001);
  TatsumaData? res = null;
  tatsumas.forEach((tatsuma){
    final double dx = point.latitude - tatsuma.pos.latitude;
    final double dy = point.longitude - tatsuma.pos.longitude;
    final double d = (dx * dx) + (dy * dy);
    if(d < th){
      res = tatsuma;
      return;
    }
  });

  return res;
}

//----------------------------------------------------------------------------
// タツマをデータベースへ保存
void saveTatsumaToDB()
{
  // タツマデータをJSONの配列に変換
  List<Map<String, dynamic>> data = [];
  tatsumas.forEach((tatsuma){
    data.add({
      "name": tatsuma.name,
      "latitude": tatsuma.pos.latitude,
      "longitude": tatsuma.pos.longitude,
      "visible": tatsuma.visible,
    });
  });

  // データベースに上書き保存
  final DatabaseReference ref = database.ref("tatsumas");
  try { ref.set(data); } catch(e) {}
}

//----------------------------------------------------------------------------
// データベースからタツマを読み込み
Future loadTatsumaFromDB() async
{
  // データベースから読み込み
  // List<TatsumaData> を配列として記録してある。
  final DatabaseReference ref = database.ref("tatsumas");
  final DataSnapshot snapshot = await ref.get();
  if(!snapshot.exists) return;
  List<dynamic> data;
  try {
    data = snapshot.value as List<dynamic>;
  }catch(e){
    return;
  }

  // タツマデータを更新
  tatsumas.clear();
  data.forEach((d){
    Map<String, dynamic> t;
    try {
      t = d as Map<String, dynamic>;
    }catch(e){
      return;
    }
    tatsumas.add(TatsumaData(
      /*pos:*/     LatLng(t["latitude"] as double, t["longitude"] as double),
      /*name:*/    t["name"] as String,
      /*visible:*/ t["visible"] as bool));
  });
}

//----------------------------------------------------------------------------
// GPXファイルからタツマを読み込む
Future readTatsumaFromGPX() async
{
  // .pgx ファイルを選択して開く
  final XTypeGroup typeGroup = XTypeGroup(
	  label: 'gpx',
	  extensions: ['gpx'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return;

  // XMLパース
  final String fileContent = await file.readAsString();
  final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

  final XmlElement? gpx = gpxDoc.getElement("gpx");
  if(gpx == null) return;

  // タツマを読み取り
  List<TatsumaData> newTatsumas = [];
  final Iterable<XmlElement> wpts = gpx.findAllElements("wpt");
  wpts.forEach((wpt){
    final String? lat = wpt.getAttribute("lat");
    final String? lon = wpt.getAttribute("lon");
    final XmlElement? name = wpt.getElement("name");
    if((lat != null) && (lon != null) && (name != null)){
      newTatsumas.add(TatsumaData(
        LatLng(double.parse(lat), double.parse(lon)),
        name.text,
        true));
    }
  });

  // タツマデータをマージ
  mergeTatsumas(newTatsumas);

  // タツマをデータベースへ保存
  saveTatsumaToDB();
}

//----------------------------------------------------------------------------
// タツマデータをマージ
void mergeTatsumas(List<TatsumaData> newTatsumas)
{
  // 同じ座標のタツマは上書きしない。
  // 新しい座標のタツマのみを取り込む。
  // 結果として、本ツール上で変更した名前と表示/非表示フラグは維持される。
  final int numTatsumas = tatsumas.length;
  newTatsumas.forEach((newTatsuma){
    bool existed = false;
    for(int i = 0; i < numTatsumas; i++){
      if(newTatsuma.pos == tatsumas[i].pos){
        existed = true;
        break;
      }
    }
    if(!existed){
      tatsumas.add(newTatsuma);
    }
  });
}

//----------------------------------------------------------------------------
// タツママーカーを更新
void updateTatsumaMarkers()
{
  // タツマデータからマーカー配列を作成
  tatsumaMarkers.clear();
  tatsumas.forEach((element) {
    if(element.visible){
      tatsumaMarkers.add(Marker(
        point: element.pos,
        width: 100.0,
        height: 96.0,
        builder: (ctx) => Column(
          children: [
            Text(""),
            Image.asset("assets/misc/tatsu_pos_icon.png", width: 32, height: 32),
            Text(element.name, style:TextStyle(fontWeight: FontWeight.bold))
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        )
      ));
    }
  });
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマ一覧画面
class TatsumasPage extends StatefulWidget
{
  TatsumasPage({
    super.key
  }){}

  @override
  TatsumasPageState createState() => TatsumasPageState();
}

class TatsumasPageState extends State<TatsumasPage>
{
  Border _borderStyle = const Border(
    bottom: BorderSide(width:1.0, color:Colors.grey)
  );

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("タツマ一覧"),
      ),
      body: Stack(children: [
        ListView.builder(
          itemCount: tatsumas.length,
          itemBuilder: (context, index){
            return _menuItem(context, index);
          }
        ),
      ]),
    );
  }

  // ファイル一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index) {
    final TatsumaData tatsuma = tatsumas[index];
    final Icon icon =
      (tatsuma.visible?
        const Icon(Icons.visibility):
        const Icon(Icons.visibility_off));

    return Container(
      // ファイル間の境界線
      decoration: BoxDecoration(border:_borderStyle),
      // アイコンとファイル名
      child:ListTile(
        leading: icon,
        title: Text(tatsuma.name),
        onTap: () {
        },
        onLongPress: () {
        }
      ),
    );
  }
}
