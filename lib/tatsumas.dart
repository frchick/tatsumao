import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

import 'package:file_selector/file_selector.dart';  // ファイル選択

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'dart:async';    // for StreamSubscription<>

import 'package:xml/xml.dart';  // GPXの読み込み
import 'mydragmarker.dart';
import 'my_list_tile.dart';

import 'members.dart';  // メンバーマーカーのサイズ
import 'gps_log.dart';  // GPSログの表示/非表示
import 'onoff_icon_button.dart';
import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマデータ
class TatsumaData {
  TatsumaData(
    this.pos,
    this.name,
    this.visible,
    this.areaBits,
    this.originalIndex,
  );
  // 空のタツマデータ
  TatsumaData.empty() :
    pos = LatLng(0,0),
    name = "",
    visible = false,
    areaBits = 0,
    originalIndex = -1
  {}

  // 座標
  LatLng pos;
  // 名前
  String name;
  // 表示/非表示
  bool visible;
  // エリア(ビット和)
  int areaBits;
  // もとの表示順
  int originalIndex;

  // 可視判定
  bool isVisible(){
    // 表示/非表示フラグ
    if(!visible) return false;
    // エリアフィルター
    if((areaFilterBits & _areaFullBits) != _areaFullBits){
      if((areaBits & areaFilterBits) == 0) return false;
    }
    return true;
  }

  // データが空か判定
  bool isEmpty() { return originalIndex < 0; }
}

// タツマの適当な初期データ
List<TatsumaData> tatsumas = [];

// 猟場のエリア名
// NOTE: 設定ボタン表示の都合で、4の倍数個で定義
const List<String> _areaNames = [
  "暗闇沢", "ホンダメ", "苅野上", "笹原林道",
  "桧山", "桧山下", "桧山上", "明神下側",
  "解体場上", "解体場東", "解体場下", "小土肥",
];

List<String> getAreaNames()
{
  return _areaNames;
}

// エリア表示フィルターのビット和
int areaFilterBits = _areaFullBits;
final int _areaFullBits = (1 << _areaNames.length) - 1;

// ソートされているか
bool _isListSorted = false;

// タツマ一覧での表示順
List<int> _tatsumaOrderArray = [];

// 非表示/フィルターされたアイコンをグレー表示するか
bool showFilteredIcon = false;

// マップ上のタツマのマーカー配列
List<Marker> tatsumaMarkers = [];

// タツマデータの保存と読み込みデータベース
FirebaseDatabase database = FirebaseDatabase.instance;

// 変更通知
StreamSubscription<DatabaseEvent>? _changesTatsumaListener;
StreamSubscription<DatabaseEvent>? _addTatsumaListener;

// 他のユーザーによるタツマデータの変更通知があった場合のコールバック
Function(int)? _onTatsumaChanged;

// 連続するタツマ追加イベントを一つにまとめるためのタイマー
Timer? _tatsumaAddEventMergeTimer;

// タツマアイコン画像
// NOTE: 表示回数が多くて静的なので、事前に作成しておく
final Image _tatsumaIcon = Image.asset(
  "assets/misc/tatsu_pos_icon.png",
  width: 32, height: 32);

final Image _tatsumaIconGray = Image.asset(
  "assets/misc/tatsu_pos_icon_gray.png",
  width: 32, height: 32);

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
// 画面座標からタツマデータを参照
int? searchTatsumaByScreenPos(MapController mapController, num x, num y)
{
  // マーカーサイズが16x16である前提
  num minDist = (18.0 * 18.0);
  int? index;
  for(int i = 0; i < tatsumas.length; i++){
    final TatsumaData tatsuma = tatsumas[i];

    // 非表示のタツマは除外
    final bool visible = showFilteredIcon || tatsuma.isVisible();
    if(!visible) continue;
 
    final CustomPoint<num>? pixelPos = mapController.latLngToScreenPoint(tatsuma.pos);
    if(pixelPos != null){
      final num dx = (x - pixelPos.x).abs();
      final num dy = (y - pixelPos.y).abs();
      if ((dx < 16.0) && (dy < 16.0)) {
        num d = (dx * dx) + (dy * dy);
        if(d < minDist){
          minDist = d;
          index = i;
        }
      }
    }
  }
  return index;
}

//----------------------------------------------------------------------------
// 地図上のマーカーにスナップ
LatLng snapToTatsuma(LatLng point)
{
  // 画面座標に変換してマーカーとの距離を判定
  // 指定された座標が画面外なら何もしない
  final CustomPoint<num>? pixelPos0 = mainMapController.latLngToScreenPoint(point);
  if(pixelPos0 == null) return point;

  // マーカーサイズが16x16である前提
  num minDist = (18.0 * 18.0);
  tatsumas.forEach((tatsuma) {
    // 非表示のタツマは除外
    if(!tatsuma.isVisible()) return;
 
    final CustomPoint<num>? pixelPos1 = mainMapController.latLngToScreenPoint(tatsuma.pos);
    if(pixelPos1 != null){
      final num dx = (pixelPos0.x - pixelPos1.x).abs();
      final num dy = (pixelPos0.y - pixelPos1.y).abs();
      if ((dx < 16) && (dy < 16)) {
        num d = (dx * dx) + (dy * dy);
        if(d < minDist){
          minDist = d;
          point = tatsuma.pos;
        }
      }
    }
  });
  return point;
}

//----------------------------------------------------------------------------
// タツマをデータベースへ保存(全体)
void saveAllTatsumasToDB()
{
  // タツマデータをJSONの配列に変換
  List<Map<String, dynamic>> data = [];
  tatsumas.forEach((tatsuma){
    data.add({
      "name": tatsuma.name,
      "latitude": tatsuma.pos.latitude,
      "longitude": tatsuma.pos.longitude,
      "visible": tatsuma.visible,
      "areaBits": tatsuma.areaBits,
    });
  });

  // データベースに上書き保存
  final DatabaseReference ref = database.ref("tatsumas");
  try { ref.set(data); } catch(e) {}
}

//----------------------------------------------------------------------------
// タツマをデータベースへ保存(個別)
void updateTatsumaToDB(int index)
{
  // タツマデータ
  final TatsumaData tatsuma = tatsumas[index];
  final Map<String, dynamic> data = {
    "name": tatsuma.name,
    "latitude": tatsuma.pos.latitude,
    "longitude": tatsuma.pos.longitude,
    "visible": tatsuma.visible,
    "areaBits": tatsuma.areaBits,
  };

  // データベースに上書き保存
  // ソートされている場合でも、元の順番で書き出す。
  final String path = "tatsumas/" + tatsuma.originalIndex.toString();
  final DatabaseReference ref = database.ref(path);
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
  int index = 0;
  tatsumas.clear();
  data.forEach((d){
    Map<String, dynamic> t;
    try {
      t = d as Map<String, dynamic>;
    }catch(e){
      return;
    }
    tatsumas.add(TatsumaData(
      /*pos:*/ LatLng(t["latitude"] as double, t["longitude"] as double),
      /*name:*/ t["name"] as String,
      /*visible:*/ t["visible"] as bool,
      /*areaBits:*/ t["areaBits"] as int,
      /*originalIndex*/ index));
    index++;
  });

  // タツマ一覧での表示順をリセット
  // 結果としてソートされていないことになる
  _tatsumaOrderArray = List<int>.generate(tatsumas.length, (i)=>i);
  _isListSorted = false;

  // 他のユーザーからの変更通知
  // 直前の変更通知を終了しておく
  releaseTatsumasSync();
  _changesTatsumaListener = ref.onChildChanged.listen(_onTatsumaChangedFromDB);
  _addTatsumaListener = ref.onChildAdded.listen(_onTatsumaAddedFromDB);
}

//----------------------------------------------------------------------------
// データベースからの変更通知を停止
void releaseTatsumasSync()
{
  _changesTatsumaListener?.cancel();
  _changesTatsumaListener = null;
  _addTatsumaListener?.cancel();
  _addTatsumaListener = null;
}

//----------------------------------------------------------------------------
// 他のユーザーによるタツマデータの変更通知
void _onTatsumaChangedFromDB(DatabaseEvent event)
{
  DataSnapshot snapshot = event.snapshot;
  if((snapshot.key == null) || (snapshot.value == null)) return;

  // 変更のあったタツマに対して、
  final int index = int.parse(snapshot.key!);
  TatsumaData tatsuma = tatsumas[index];

  // 変更通知から値を代入
  var data = snapshot.value! as Map<String, dynamic>;
  tatsuma.name = data["name"] as String;
  tatsuma.visible = data["visible"] as bool;
  tatsuma.areaBits = data["areaBits"] as int;
  tatsuma.pos.latitude = data["latitude"] as double;
  tatsuma.pos.longitude = data["longitude"] as double;

  // 再描画
  // コールバックが設定されていたらそちら、なければマップを再描画
  updateTatsumaMarkers();
  if(_onTatsumaChanged != null){
    _onTatsumaChanged!(index);
  }else{
    updateMapView();
  }
}

//----------------------------------------------------------------------------
// 他のユーザーによるタツマデータの追加通知
void _onTatsumaAddedFromDB(DatabaseEvent event)
{
  DataSnapshot snapshot = event.snapshot;
  if((snapshot.key == null) || (snapshot.value == null)) return;

  // すでに作成済みのタツマなら何もしない
  final int index = int.parse(snapshot.key!);
  if((index < tatsumas.length) && !tatsumas[index].isEmpty()) return;

  // タツマを追加
  var t = snapshot.value! as Map<String, dynamic>;
  TatsumaData newTatsuma = TatsumaData(
    /*pos:*/ LatLng(t["latitude"] as double, t["longitude"] as double),
    /*name:*/ t["name"] as String,
    /*visible:*/ t["visible"] as bool,
    /*areaBits:*/ t["areaBits"] as int,
    /*originalIndex*/ index);
  if(index < tatsumas.length){
    // すでに確保済みの配列に代入
    tatsumas[index] = newTatsuma;
  }else{
    // 配列を拡張
    // もし非連続なインデックスがきたら、そこまでは空のデータで拡張する
    for(int i = tatsumas.length; i < index; i++){
      tatsumas.add(TatsumaData.empty());
      _tatsumaOrderArray.add(i);
    }
    tatsumas.add(newTatsuma);
    _tatsumaOrderArray.add(index);
  }

  // 連続するタツマ追加イベントを一つにまとめるためのタイマーを設定
  // 1秒のタイマーを使うことで、次の通知が1秒以内であればまとめる。
  if(_tatsumaAddEventMergeTimer != null){
    _tatsumaAddEventMergeTimer!.cancel();
    _tatsumaAddEventMergeTimer = null;
  }
  _tatsumaAddEventMergeTimer = Timer(Duration(seconds:1), (){
    _tatsumaAddEventMergeTimer = null;
    // コールバックが設定されていたらそちら、なければマップを再描画
    updateTatsumaMarkers();
    if(_onTatsumaChanged != null){
      _onTatsumaChanged!(index);
    }else{
      updateMapView();
      showTextBallonMessage("他のユーザーがタツマを追加");
    }
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
        true,
        0,
        0));
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
  final int numTatsumas = tatsumas.length;
  int addCount = 0;
  int index = numTatsumas;
  newTatsumas.forEach((newTatsuma){
    bool existed = false;
    for(int i = 0; i < numTatsumas; i++){
      if(newTatsuma.pos == tatsumas[i].pos){
        existed = true;
        break;
      }
    }
    if(!existed){
      newTatsuma.originalIndex = index;
      tatsumas.add(newTatsuma);
      _tatsumaOrderArray.add(index);
      addCount++;
      index++;
    }
  });

  // マージで追加したタツマ数を返す
  return addCount;
}

//----------------------------------------------------------------------------
// タツマ一覧をソート
List<int> makeTatsumaOrderArray(bool sort)
{
  // タツマデータそのものではなく、インデックスのバッファをソートする
  var buf = List<int>.generate(tatsumas.length, (i)=>i);
  if(sort){
    buf.sort((idxa, idxb){
      final TatsumaData a = tatsumas[idxa];
      final TatsumaData b = tatsumas[idxb];
      // まずはエリアフィルター含めて表示を前に、非表示を後ろに
      final int v0 = (a.isVisible()? 0: 1) - (b.isVisible()? 0: 1);
      if(v0 != 0) return v0;
      //表示/非表示アイコンで非表示なってるやつを後ろに
      final int v1 = (a.visible? 0: 1) - (b.visible? 0: 1);
      if(v1 != 0) return v1;
      // エリア毎にまとめる
      // エリア指定がないタツマは後ろ
      if(a.areaBits != b.areaBits){
        if(a.areaBits == 0) return 1;
        if(b.areaBits == 0) return -1;
        return (a.areaBits - b.areaBits);
      }
      // 最後に元の順番
      return (a.originalIndex - b.originalIndex);
    });
  }
  return buf;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// エリア表示フィルターを文字列に変換
List<String> areaFilterToStrings()
{
  // 特に指定がない場合には特殊キーワード "All" を返す
  if((areaFilterBits & _areaFullBits) == _areaFullBits){
    return ["All"];
  }

  // 可視なエリア名を配列で返す
  List<String> res = [];
  for(int i = 0; i < _areaNames.length; i++){
    final int maskBit = (1 << i);
    if((areaFilterBits & maskBit) != 0){
      res.add(_areaNames[i]);
    }
  }
  return res;
}

// 文字列からエリア表示フィルターを設定
int stringsToAreaFilter(List<String>? areas)
{
  // 特に指定がない場合には現状のママ
  if(areas == null){
    return areaFilterBits;
  }

  // 特殊キーワード "All" の場合はすべて表示
  if((areas.length == 1) && (areas[0] == "All")){
    areaFilterBits = _areaFullBits;
    return areaFilterBits;
  }

  // 文字列に含まれるエリアを可視に
  areaFilterBits = 0;
  areas.forEach((name){
    final int index = _areaNames.indexOf(name);
    if(0 <= index){
      areaFilterBits |= (1 << index);
    }
  });
  return areaFilterBits;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// マップ上のタツママーカーを更新
void updateTatsumaMarkers()
{
  // テキストスタイル
  final TextStyle textStyle = const TextStyle(fontWeight: FontWeight.bold);
  final TextStyle textStyleGray = const TextStyle(color: Color(0xFF616161)/*grey[700]*/);

  // タツマデータからマーカー配列を作成
  // 非表示グレーマーカーが、可視のマーカーの下になるように描画順を制御
  tatsumaMarkers.clear();
  List<Marker> markers2 = [];
  tatsumas.forEach((tatsuma) {
    // スイッチONで非表示アイコンをグレー表示
    if(showFilteredIcon && !tatsuma.isVisible()){
      tatsumaMarkers.add(Marker(
        point: tatsuma.pos,
        width: 200.0,
        height: 64.0,
        anchorPos: AnchorPos.exactly(Anchor(100, 48)),
        builder: (ctx) => Column(
          children: [
            // アイコンを中央寄せにするために、上部にダミーの空テキスト(マシな方法ないか？)
            // 十字アイコン
            _tatsumaIconGray,
            // タツマ名
            Text(tatsuma.name, style: textStyleGray),
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        )
      ));
    }else if(tatsuma.isVisible()){
      // 表示状態のアイコン
      markers2.add(Marker(
        point: tatsuma.pos,
        width: 200.0,
        height: 64.0,
        anchorPos: AnchorPos.exactly(Anchor(100, 48)),
        builder: (ctx) => Column(
          children: [
            _tatsumaIcon,
            Text(tatsuma.name, style: textStyle),
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        )
      ));
    }
  });
  tatsumaMarkers.addAll(markers2);
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
  // タツマデータに変更があったかのフラグ
  bool changeFlag = false;

  // タツマ一覧に表示する、エリアタグ
  // NOTE: 表示回数多いし静的なので事前作成
  List<Container> _areaTags = [];
  List<Container> _hideAreaTags = [];

  // リストビューのスクロールコントロール
  ScrollController _listScrollController = ScrollController();

  @override
  initState() {
    super.initState();

    // エリアラベルを作成
    // NOTE: 初回のみ
    if(_areaTags.length == 0){
      // 表示のスタイル
      final BoxDecoration visibleBoxDec = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange, width:2),
        color: Colors.orange[200],
      );
      final TextStyle visibleTexStyle = const TextStyle(color: Colors.white);
      // 非表示のスタイル
      final BoxDecoration hideBoxDec = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey, width:2),
      );
      final TextStyle hideTexStyle = const TextStyle(color: Colors.grey);

      for(int i = 0; i < _areaNames.length; i++){
        // 表示のエリアラベル
        _areaTags.add(Container(
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(vertical:2, horizontal:8),
          decoration: visibleBoxDec,
          child: Text(
            _areaNames[i],
            textScaleFactor:0.9,
            style: visibleTexStyle
          ),
        ));
        // 非表示のエリアラベル
        _hideAreaTags.add(Container(
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(vertical:2, horizontal:8),
          decoration: hideBoxDec,
          child: Text(
            _areaNames[i],
            textScaleFactor:0.9,
            style: hideTexStyle
          ),
        ));
      }
    }
  }

  // タツマ一覧
  @override
  Widget build(BuildContext context)
  {
    // 他のユーザーによるタツマ変更のコールバックを設定
    _onTatsumaChanged = (_){ setState((){}); };

    return WillPopScope(
      // ページ閉じる際の処理
      onWillPop: (){
        // 他のユーザーによるタツマ変更のコールバックをクリア
        _onTatsumaChanged = null;
        // ページの戻り値
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
              icon: const Icon(Icons.file_open),
              onPressed:() async {
                readTatsumaFromGPXSub(context);
              },
            ),

            // ソート(ON/OFF)
            OnOffIconButton(
              icon: const Icon(Icons.sort),
              onSwitch: _isListSorted,
              onChange: ((onSwitch){
                setState((){
                  _isListSorted = onSwitch;
                  _tatsumaOrderArray = makeTatsumaOrderArray(_isListSorted);
                });
                _listScrollController.animateTo(
                  0,
                  duration: Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                );
              }),
            ),

            // エリアフィルター
            IconButton(
              icon: const Icon(Icons.filter_alt),
              onPressed:() {
                showAreaFilter(context).then((bool? res){
                  if(res ?? false){
                    setState((){
                      changeFlag = true;
                    });
                    // エリアフィルターの設定をデータベースへ保存
                    saveAreaFilterToDB(getOpenedFileUIDPath());
                  }
                });
              },
            ),
          ],
        ),

        // タツマ一覧の作成
        // ソート順をここで反映する
        body: ListView.builder(
          itemCount: tatsumas.length,
          itemBuilder: (context, index){
            return _menuItem(context, _tatsumaOrderArray[index]);
          },
          controller: _listScrollController,
        ),
      )
    );
  }

  // タツマ一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index)
  {
    final TatsumaData tatsuma = tatsumas[index];

    // 表示するエリアタグを選択
    List<Widget> areaTagsAndButton = [];
    for(int i = 0; i < _areaTags.length; i++){
      final int areaMask = (1 << i);
      if((tatsuma.areaBits & areaMask) != 0){
        final bool visibleArea = (areaFilterBits & areaMask) != 0;
        areaTagsAndButton.add(visibleArea? _areaTags[i]: _hideAreaTags[i]);
      }
    }
    // 編集ボタンとの間のスペース調整
    if(tatsuma.areaBits != 0){
      areaTagsAndButton.add(const SizedBox(width:5));
    }

    // 編集ボタンも追加しておく
    areaTagsAndButton.add(IconButton(
      icon: const Icon(Icons.more_horiz),
      onPressed:() {
        // タツマ名の変更ダイアログ
        showChangeTatsumaDialog(context, tatsuma).then((res){
          if(res != null){
            setState((){
              changeFlag = true;
              tatsuma.name     = res["name"] as String;
              tatsuma.visible  = res["visible"] as bool;
              tatsuma.areaBits = res["areaBits"] as int;
            });
            // データベースに同期
            updateTatsumaToDB(index);
          }
        });
      }
    ));
    
    // アイコンの選択
    const Color hideColor = const Color(0xFFBDBDBD)/*Colors.grey[400]*/;
    late Icon icon;
    if(!tatsuma.visible){
      icon = const Icon(Icons.visibility_off, color: hideColor);
    }else if(!tatsuma.isVisible()){
      icon = const Icon(Icons.visibility, color: hideColor);
    }else{
      icon = const Icon(Icons.visibility);
    }

    return Container(
      // 境界線
      decoration: const BoxDecoration(
        border:Border(
          bottom: const BorderSide(width:1.0, color:Colors.grey)
        ),
      ),
      // 表示/非表示アイコンとタツマ名
      child:MyListTile(
        // (左側)表示非表示アイコンボタン
        leading: IconButton(
          icon: icon,
          onPressed:() {
            // 表示非表示の切り替え
            setState((){
              changeFlag = true;
              tatsuma.visible = !tatsuma.visible;
              // データベースに同期
              updateTatsumaToDB(index);
            });
          },
        ),

        // タツマ名
        // 非表示の場合はグレー
        title: Text(
          tatsuma.name,
          style: (tatsuma.isVisible()? null: const TextStyle(color: hideColor)),
        ),

        // (右側)エリアタグと編集ボタン
        trailing: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: areaTagsAndButton
        ),

        // 長押しでポップアップメニュー
        onLongPress: (TapDownDetails details){
          showPopupMenu(context, index, details.globalPosition);
        }
      ),
    );
  }

  //----------------------------------------------------------------------------
  // タツマ一覧長押しのポップアップメニュー
  void showPopupMenu(BuildContext context, int index, Offset offset)
  {
    // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, offset.dy),
      elevation: 8.0,
      items: [
        makePopupMenuItem(0, "この場所へ移動", Icons.travel_explore),
      ],
    ).then((value) {
      switch(value ?? -1){
      case 0:
        // 座標を指定して地図に戻る
        // ある程度のズーム率まで拡大表示する
        double zoom = mainMapController.zoom;
        const double zoomInTarget = 16.25;
        if(zoom < zoomInTarget) zoom = zoomInTarget;
        final TatsumaData tatsuma = tatsumas[index];
        mainMapController.move(tatsuma.pos, zoom);
        Navigator.pop(context);
        break;
      }
    });
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
      saveAllTatsumasToDB();
      setState((){
        changeFlag = true;
        updateTatsumaMarkers();
      });
    }

    return addTatsuma;
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマ入力ダイアログ
class TatsumaDialog extends StatefulWidget
{
  TatsumaDialog({
    super.key,
    required this.name,
    required this.visible,
    required this.areaBits,
  }){}

  // 名前
  String name;
  // 表示非表示フラグ
  bool visible;
  // エリアビット
  int  areaBits;

  @override
  State createState() => _TatsumaDialogDialogState();
}

class _TatsumaDialogDialogState extends State<TatsumaDialog>
{
  late TextEditingController _dateTextController;

  @override 
  void initState()
  {
    super.initState();

    // NOTE: 初期値の設定を build() に書くと、他の Widget 由来の再描画があるたびに、
    // NOTE: テキストフィールドが元に戻ってしまう。initState() に書くのが正解。
    _dateTextController = TextEditingController(text: widget.name);
  }

  @override
  Widget build(BuildContext context)
  {
    final Icon visibilityIcon =
      widget.visible? const Icon(Icons.visibility): const Icon(Icons.visibility_off);

    return AlertDialog(
      title: const Text("タツマ"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 表示/非表示アイコンボタン
              IconButton(
                icon: visibilityIcon,
                onPressed: (){
                  setState((){
                    widget.visible = !widget.visible;
                  });
                },                
              ),
              const SizedBox(width: 10),

              // 名前エディットボックス
              Expanded(
                child: TextField(
                  controller: _dateTextController,
                  autofocus: true,
                ),
              )
            ]
          ),

          // エリアON/OFFボタン
          const SizedBox(height: 10), makeAreaButtonRow(0, 4, _areaNames),
          const SizedBox(height: 5),  makeAreaButtonRow(4, 4, _areaNames),
          const SizedBox(height: 5),  makeAreaButtonRow(8, 4, _areaNames),
        ]
      ),
      actions: [
        ElevatedButton(
          child: const Text("キャンセル"),
          onPressed: () {
            Navigator.pop(context);
          }
        ),
        ElevatedButton(
          child: const Text("OK"),
          onPressed: () {
            Navigator.pop<Map<String,dynamic>>(context, {
              "name": _dateTextController.text,
              "visible": widget.visible,
              "areaBits": widget.areaBits });
          },
        ),
      ],
    );
  }

  // エリア選択ボタンの横一列分を作成
  ToggleButtons makeAreaButtonRow(int offset, int count, List<String> areaNames)
  {
    // 初期状態でのON/OFFフラグ配列を作成
    List<bool> selectFlags = [];
    for(int i = 0; i < count; i++){
      final int maskBit = (1 << (offset + i));
      final bool on = (widget.areaBits & maskBit) != 0;
      selectFlags.add(on);
    }
    // テキストラベルを作成
    List<Text> areaLables = [];
    for(int i = 0; i < count; i++){
      areaLables.add(Text(areaNames[offset+i]));
    }

    return ToggleButtons(
      onPressed: (int index) {
        setState(() {
          final int maskBit = (1 << (offset + index));
          if((widget.areaBits & maskBit) == 0){
            widget.areaBits |= maskBit;
          }else{
            widget.areaBits &= ~maskBit;
          }
        });
      },
      isSelected: selectFlags,
      children: areaLables,

      direction: Axis.horizontal,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      constraints: const BoxConstraints(minHeight: 30, minWidth: 80),
      selectedBorderColor: Colors.orange[700],  // ON枠の色
      selectedColor: Colors.white,              // ONフォントの色
      fillColor: Colors.orange[200],            // ON背景の色
      color: Colors.orange[400],                // OFFフォントの色
    );
  }
}

//----------------------------------------------------------------------------
// タツマ名変更ダイアログ
Future<Map<String,dynamic>?>
  showChangeTatsumaDialog(BuildContext context, TatsumaData tatsuma)
{
  return showDialog<Map<String,dynamic>>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TatsumaDialog(
        name: tatsuma.name,
        visible: tatsuma.visible,
        areaBits: tatsuma.areaBits);
    },
  );
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// エリア表示フィルターダイアログ
class AreaFilterDialog extends StatefulWidget
{
  AreaFilterDialog({ this.showMapDrawOptions=false }){
    _areaFilterBits0 = areaFilterBits;
  }

  @override
  AreaFilterDialogState createState() => AreaFilterDialogState();

  // マップ表示オプションを表示するか
  bool showMapDrawOptions;

  // 表示前のエリアフィルターのフラグ(変更の有無を確認する用)
  int _areaFilterBits0 = 0;
}

class AreaFilterDialogState  extends State<AreaFilterDialog>
{
  @override
  Widget build(BuildContext context)
  {
    // 表示エリアのスタイル
    final visibleBoxDec = BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: Colors.orange, width:2),
      color: Colors.orange[200],
    );
    final visibleTexStyle = const TextStyle(color: Colors.white);

    // 非表示エリアのスタイル
    final hideBoxDec = BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: Colors.grey, width:2),
    );
    final hideTexStyle = const TextStyle(color: Colors.grey);
  
    // エリアごとのリスト項目を作成
    List<Container> areas = [];
    for(int i = 0; i < _areaNames.length; i++){
      final int maskBit = (1 << i);
      final bool visible = (areaFilterBits & maskBit) != 0;

      areas.add(Container(
        height: 42,
      
        child: ListTile(
          // (左側)表示/非表示アイコン
          leading: (visible? const Icon(Icons.visibility): const Icon(Icons.visibility_off)),

          // エリア名タグ
          // 表示/非表示で枠を変える
          title: Row( // このRow入れないと、タグのサイズが横いっぱいになってしまう。
            children: [
              Container(
                child: Text(
                  _areaNames[i],
                  style: (visible? visibleTexStyle: hideTexStyle),
                ),
                decoration: (visible? visibleBoxDec: hideBoxDec),
                padding: const EdgeInsets.symmetric(vertical:3, horizontal:10),
              ),
            ]
          ),
          // タップで
          onTap: (){
            // 表示非表示を反転
            setState((){
              areaFilterBits = (areaFilterBits ^ maskBit);
            });
            updateTatsumaMarkers();
            updateMapView();
          },
        ),
      ));
    };

    // メンバーマーカーとGPSログの表示スイッチ
    List<bool> _memberMarkerSizeFlag = [ false, false, false ];
    _memberMarkerSizeFlag[memberMarkerSizeSelector] = true;
    List<bool> _showGPSLogFlag = [ gpsLog.showLogLine ];

    // ダイアログタイトル
    var titleText = widget.showMapDrawOptions? "表示/非表示設定": "エリアフィルター";

    // ダイアログ表示
    return WillPopScope(
      // ページの戻り値
      onWillPop: (){
        // エリアフィルターに変更があるかを返す
        final bool changeFilter = (widget._areaFilterBits0 != areaFilterBits); 
        Navigator.of(context).pop(changeFilter);
        return Future.value(false);
      },
      child: SimpleDialog(
        // ヘッダ部
        // グレー表示スイッチ含む
        titlePadding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0.0),
        title: Column(
          children: [
            // タイアログタイトル
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [ Text(titleText) ],
            ),
            const SizedBox(height: 20),

            // [2段目]メンバーマーカーサイズ/非表示、GPSログ表示/非表示スイッチ
            if(widget.showMapDrawOptions) Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // メンバーマーカーサイズ/非表示スイッチ
                ToggleButtons(
                  children: [
                    const Icon(Icons.location_pin, size:30),
                    const Icon(Icons.location_pin, size:22),
                    const Icon(Icons.location_off, size:22),
                  ],
                  isSelected: _memberMarkerSizeFlag,
                  onPressed: (index) {
                    setState(() {
                      memberMarkerSizeSelector = index;
                      mainMapDragMarkerPluginOptions.visible
                        = isShowMemberMarker();
                    });
                    createMemberMarkers();
                    updateMapView();
                  },
                ),
                const SizedBox(width:5, height:30),
                // GPSログ表示/非表示スイッチ
                ToggleButtons(
                  children: [
                    const Icon(Icons.timeline, size:30),
                  ],
                  isSelected: _showGPSLogFlag,
                  onPressed: (index) {
                    setState(() {
                      gpsLog.showLogLine = !gpsLog.showLogLine;
                      gpsLog.makePolyLines();
                      gpsLog.makeDogMarkers();
                      gpsLog.redraw();
                    });
                  },
                )
              ],
            ),
            if(widget.showMapDrawOptions)
              const SizedBox(height: 8),

            // [3段目]一括表示/非表示スイッチ、グレー表示スイッチ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // (左寄せ)一括表示/非表示スイッチ
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // 一括表示
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed:() {
                        // 表示非表示を反転
                        setState((){
                          areaFilterBits = _areaFullBits;
                        });
                        updateTatsumaMarkers();
                        updateMapView();
                      },
                    ),
                    // 一括非表示
                    IconButton(
                      icon: const Icon(Icons.visibility_off),
                      onPressed:() {
                        // 表示非表示を反転
                        setState((){
                          areaFilterBits = 0;
                        });
                        updateTatsumaMarkers();
                        updateMapView();
                      },
                    ),
                    if(!widget.showMapDrawOptions)
                      Text("一括", style: Theme.of(context).textTheme.subtitle1),
                  ],
                ),
                // (右寄せ)グレー表示スイッチ
                if(widget.showMapDrawOptions) Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("グレー表示", style: Theme.of(context).textTheme.subtitle1),
                    Switch(
                      value:showFilteredIcon,
                      onChanged:(r){
                        setState((){
                          showFilteredIcon = r;
                        });
                        updateTatsumaMarkers();
                        updateMapView();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ]
        ),
        // エリア一覧
        children: areas,
      )
    );
  }
}

Future<bool?> showAreaFilter(BuildContext context, { bool showMapDrawOptions=false })
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context){
      return AreaFilterDialog(showMapDrawOptions: showMapDrawOptions);
    },
  );
}

// エリア表示フィルターの設定をデータベースへ保存
void saveAreaFilterToDB(String uidPath)
{
  final String dbPath = "assign" + uidPath + "/areaFilter";
  final DatabaseReference ref = database.ref(dbPath);
  List<String> data = areaFilterToStrings();
  ref.set(data);
}

// エリア表示フィルターの設定をデータベースから読み込み
Future loadAreaFilterFromDB(String uidPath) async
{
  final String dbPath = "assign" + uidPath + "/areaFilter";
  final DatabaseReference ref = database.ref(dbPath);
  final DataSnapshot snapshot = await ref.get();
  if(snapshot.exists){
    List<String> data = [];
    try {
      var temp = snapshot.value as List<dynamic>;
      List<String> stringList = [];
      temp.forEach((t){ data.add(t as String); });
    } catch(e) {}
    stringsToAreaFilter(data);
  }
}
