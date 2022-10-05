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
import 'text_edit_dialog.dart';

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
Map<String,int>? readTatsumaFromGPX(String fileContent)
{
  // XMLパース
  final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

  final XmlElement? gpx = gpxDoc.getElement("gpx");
  if(gpx == null) return null;

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
  final int mergeCount = mergeTatsumas(newTatsumas);

  // 読みこんだ数と、マージで取り込んだ数を返す
  return {
    "readCount": newTatsumas.length,
    "mergeCount": mergeCount,
  };
}

//----------------------------------------------------------------------------
// タツマデータをマージ
int mergeTatsumas(List<TatsumaData> newTatsumas)
{
  // 同じ座標のタツマは上書きしない。
  // 新しい座標のタツマのみを取り込む。
  // 結果として、本ツール上で変更した名前と表示/非表示フラグは維持される。
  int addCount = 0;
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
      addCount++;
    }
  });

  // マージで追加したタツマ数を返す
  return addCount;
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

  // タツマデータに変更があったかのフラグ
  bool changeFlag = false;

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // ページの戻り値
      onWillPop: (){
        Navigator.of(context).pop(changeFlag);
        return Future.value(false);
      },
      child: Scaffold(
        // ヘッダー部
        appBar: AppBar(
          title: const Text("タツマ一覧"),
          actions: [
            // GPXファイル読み込み
            IconButton(
              icon: Icon(Icons.file_open),
              onPressed:() async {
                readTatsumaFromGPXSub(context);
              },
            ),
          ],
        ),

        body: ListView.builder(
          itemCount: tatsumas.length,
          itemBuilder: (context, index){
            return _menuItem(context, index);
          }
        ),
      )
    );
  }

  // タツマ一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index) {
    final TatsumaData tatsuma = tatsumas[index];

    return Container(
      // 境界線
      decoration: BoxDecoration(border:_borderStyle),
      // 表示/非表示アイコンとタツマ名
      child:ListTile(
        title: Text(tatsuma.name),

        // (左側)表示非表示アイコンボタン
        leading: IconButton(
          icon: Icon(tatsuma.visible? Icons.visibility: Icons.visibility_off),
          onPressed:() {
            // 表示非表示の切り替え
            setState((){
              changeFlag = true;
              tatsuma.visible = !tatsuma.visible;
            });
          },
        ),

        // (右側)編集ボタン
        trailing: IconButton(
          icon: Icon(Icons.more_horiz),
          onPressed:() {
            // タツマ名の変更ダイアログ
            showChangeTatsumaDialog(context, index).then((name){
              if(name != null){
                setState((){
                  changeFlag = true;
                  tatsuma.name = name;
                });
              }
            });
          },
        ),

        onTap: (){
        },

        onLongPress: (){
        },
      ),
    );
  }

  //----------------------------------------------------------------------------
  // タツマ名変更ダイアログ
  Future<String?> showChangeTatsumaDialog(BuildContext context, int index)
  {
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return TextEditDialog(
          titleText: "タツマ名の変更",
          defaultText: tatsumas[index].name);
      },
    );
  }

  //----------------------------------------------------------------------------
  // GPXからのタツマ読み込み処理
  Future<bool> readTatsumaFromGPXSub(BuildContext context) async
  {
    // .pgx ファイルを選択して開く
    final XTypeGroup typeGroup = XTypeGroup(
      label: 'gpx',
      extensions: ['gpx'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return false;

    // ファイル読み込み
    final String fileContent = await file.readAsString();

    // XMLパース
    final Map<String,int>? res = readTatsumaFromGPX(fileContent);
    if(res == null) return false;
    final int readCount = res["readCount"] ?? 0;
    final int mergeCount = res["mergeCount"] ?? 0;

    // メッセージを表示
    final String message =
      "${readCount}個の座標を読み込み、${mergeCount}個を追加しました。";
    showDialog(
      context: context,
      builder: (_){ return AlertDialog(content: Text(message)); });

    // タツマをデータベースへ保存して再描画(追加があれば)
    final bool addTatsuma = (0 < mergeCount);
    if(addTatsuma){
      saveTatsumaToDB();
      setState((){
        changeFlag = true;
        updateTatsumaMarkers();
      });
    }

    return addTatsuma;
  }
}
