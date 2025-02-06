import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

import 'package:file_selector/file_selector.dart';  // ファイル選択

import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';    // for StreamSubscription<>

import 'package:xml/xml.dart';  // GPXの読み込み
import 'mydragmarker.dart';
//!!!! import 'my_list_tile.dart';

import 'onoff_icon_button.dart';
import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'globals.dart';
import 'area_filter_dialog.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマデータ
class TatsumaData {
  TatsumaData(
    this.pos,
    this.name,
    this.visible,
    this.areaBits,
    this.auxPoint,
    this.gpxSlot,
    this.originalIndex,
  );
  // 空のタツマデータ
  TatsumaData.empty() :
    pos = LatLng(0,0),
    name = "",
    visible = false,
    areaBits = 0,
    auxPoint = false,
    gpxSlot = 0,
    originalIndex = -1;

  // 座標
  LatLng pos;
  // 名前
  String name;
  // 表示/非表示
  bool visible;
  // エリア(ビット和)
  int areaBits;
  // 「補助地点」
  bool auxPoint;
  // GPXファイル読み込みのスロット番号
  int gpxSlot;
  // データベース上での番号(表示ソートの影響を受けない)
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
// NOTE: TatsumaData.areaBits のビットと対応しているので、後から順番を変えられない。
const List<String> areaNames = [
  "暗闇沢", "ホンダメ", "苅野", "笹原林道",
  "桧山", "858", "金太郎L", "最乗寺",
  "裏山(静)", "中尾沢", "", "(未設定)",
];

// エリア表示フィルターのビット和
int areaFilterBits = _areaFullBits;
final int _areaFullBits = (1 << areaNames.length) - 1;
// エリア未設定を表すビット和
final int _undefAreaBits = 0x0800;

// ソートされているか
bool _isListSorted = false;

// タツマ一覧での表示順
List<int> _tatsumaOrderArray = [];

// 非表示/フィルターされたアイコンをグレー表示するか
bool showFilteredIcon = false;

// マップ上のタツマのマーカー配列
List<Marker> tatsumaMarkers = [];

// 変更通知
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tatsumaUpdateListener;

// NOTE: リスナーコールバック内で、初回のデータ変更通知を拾うために参照
bool _isFirstSyncEvent = true;

// タツマアイコン画像
// NOTE: 表示回数が多くて静的なので、事前に作成しておく
final Image _tatsumaIcon = Image.asset(
  "assets/misc/tatsu_pos_icon.png",
  width: 32, height: 32);

final Image _tatsumaIconGray = Image.asset(
  "assets/misc/tatsu_pos_icon_gray.png",
  width: 32, height: 32);

final Image _tatsumaIconGreen =
  Image.asset("assets/misc/tatsu_pos_icon_green.png",
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
  final CustomPoint<num>? pixelPos0 = mainMapController!.latLngToScreenPoint(point);
  if(pixelPos0 == null) return point;

  // マーカーサイズが16x16である前提
  num minDist = (18.0 * 18.0);
  tatsumas.forEach((tatsuma) {
    // 非表示のタツマは除外
    if(!tatsuma.isVisible()) return;
 
    final CustomPoint<num>? pixelPos1 = mainMapController!.latLngToScreenPoint(tatsuma.pos);
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
  for(final tatsuma in tatsumas){
    data.add({
      "name": tatsuma.name,
      "latitude": tatsuma.pos.latitude,
      "longitude": tatsuma.pos.longitude,
      "visible": tatsuma.visible,
      "auxPoint": tatsuma.auxPoint,
      "areaBits": tatsuma.areaBits,
      "gpxSlot": tatsuma.gpxSlot,
    });
  }

  // データベースに上書き保存
  final colRef = FirebaseFirestore.instance.collection("tatsumas");
  final docRef = colRef.doc("all");
  docRef.set({ "list": data });
}

//----------------------------------------------------------------------------
// データベースからタツマを読み込み
Future loadTatsumaFromDB() async
{
  // Firestore から取得して作成
  final colRef = FirebaseFirestore.instance.collection("tatsumas");
  final docRef = colRef.doc("all");

  // Firestore から変更通知を受け取るリスナーを設定
  _isFirstSyncEvent = true;
  _tatsumaUpdateListener = docRef.snapshots().listen((event){
    _onChangeTatsumaFromDB(event);
    _isFirstSyncEvent = false;
  });
}

void _onChangeTatsumaFromDB(DocumentSnapshot<Map<String, dynamic>> snapshot)
{
  final localChange = snapshot.metadata.hasPendingWrites;
  print("_onChangeTatsumaFromDB(): local=$localChange first=$_isFirstSyncEvent");

  // ローカルの変更による通知では何もしない
  // ただし、マーカーを初期化するために、ファイルを開いた直後のデータ変更通知は拾う
  if(!_isFirstSyncEvent && localChange){
    return;
  }

  // データベースから読み込み
  // List<TatsumaData> を配列として記録してある。
  List<dynamic> data;
  try {
    data = snapshot.data()!["list"] as List<dynamic>;
  }catch(e){
    return;
  }

  // タツマデータを更新
  int index = 0;
  tatsumas.clear();
  for(final d in data){
    try {
      final t = d as Map<String, dynamic>;

      // 禁猟区マークは読み込まない
      // (レッドゾーンの表示に対応したので。)
      var name = t["name"] as String;
      if(name.contains("禁猟区")) continue;

      tatsumas.add(TatsumaData(
        /*pos:*/ LatLng(t["latitude"] as double, t["longitude"] as double),
        /*name:*/ name,
        /*visible:*/ t["visible"] as bool,
        /*areaBits:*/ t["areaBits"] as int,
        /*auxPoint:*/ t["auxPoint"] as bool,
        /*gpxSlot:*/ t["gpxSlot"] as int,
        /*originalIndex*/ index));
      index++;
    }catch(e){ /**/ }
  }

  // タツマ一覧での表示順をリセット
  // 結果としてソートされていないことになる
  _tatsumaOrderArray = List<int>.generate(tatsumas.length, (i)=>i);
  _isListSorted = false;

  // 再描画
  // 初回はこの後のデフォルトファイルの読み込み処理で、タツママーカーが構築される
  if(!_isFirstSyncEvent){
    updateTatsumaMarkers();
    updateMapView();
  }
}

//----------------------------------------------------------------------------
// データベースからの変更通知を停止
void releaseTatsumasSync()
{
  _tatsumaUpdateListener?.cancel();
  _tatsumaUpdateListener = null;
}

//----------------------------------------------------------------------------
// GPXファイルからタツマを読み込む
Map<String,List<TatsumaData>>? readTatsumaFromGPX(String fileContent, int gpxSlot)
{
  // XMLパース
  final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

  final XmlElement? gpx = gpxDoc.getElement("gpx");
  if(gpx == null) return null;

  // GPXからタツマを読み取り
  List<TatsumaData> newTatsumas = [];
  final Iterable<XmlElement> wpts = gpx.findAllElements("wpt");
  int index = 0;
  for(final wpt in wpts){
    final String? lat = wpt.getAttribute("lat");
    final String? lon = wpt.getAttribute("lon");
    final XmlElement? name = wpt.getElement("name");
    if((lat != null) && (lon != null) && (name != null)){
      // 禁猟区マークは読み込まない
      // (レッドゾーンの表示に対応したので。)
      if(name.text.contains("禁猟区")) continue;

      newTatsumas.add(TatsumaData(
        LatLng(double.parse(lat), double.parse(lon)),
        name.text,
        true,     // visible
        0,        // areaBits
        false,    // auxPoint
        gpxSlot,  // gpxSlot
        index));
      index++;
    }
  }

  // 既存のタツマデータを、対象スロットとそれ以外に分割
  List<TatsumaData> targetTatsumas = [];
  List<TatsumaData> otherTatsumas = [];
  for(final tatsuma in tatsumas){
    if(tatsuma.gpxSlot == gpxSlot){
      targetTatsumas.add(tatsuma);
    }else{
      otherTatsumas.add(tatsuma);
    }
  }

  // タツマの属性をコピー
  var res = _copyTatsumaAttribute(newTatsumas, targetTatsumas);

  // 対象スロットでなかったタツマと結合して置き換え
  tatsumas = [...newTatsumas, ...otherTatsumas];

  // 追加された、削除された、変更されたタツマのリストを返す
  return res;
}

//----------------------------------------------------------------------------
// タツマデータを削除
void deleteTatsuma(int index)
{
  // インデックスが範囲外なら何もしない
  if((index < 0) || (tatsumas.length <= index)) return;

  // もとの表示順を先に詰めておく
  final int deleteOriginalIndex = tatsumas[index].originalIndex;
  for(var tatsuma in tatsumas){
    if(deleteOriginalIndex <= tatsuma.originalIndex){
      tatsuma.originalIndex--;
    }
  }
  // 配列から削除
  tatsumas.removeAt(index);
}

//----------------------------------------------------------------------------
// タツマ属性データをコピー
Map<String,List<TatsumaData>> _copyTatsumaAttribute(
  List<TatsumaData> newTatsumas,
  List<TatsumaData> orgTatsumas)
{
  List<TatsumaData> addTatsumaNames = [];

  // 座標をキーにタツマ属性データをコピー
  // NOTE: 現状総当たりになっているので、どうにかする。
  for(var newTatsuma in newTatsumas){
    // とりあえずエリアは未設定にしておく    
    newTatsuma.areaBits = _undefAreaBits;
    bool found = false;
    for(int i = 0; i < orgTatsumas.length; i++){
      // 同じタツマかどうかの判定は、座標の一致のみとする。
      found = (newTatsuma.pos == orgTatsumas[i].pos);
      if(found){
        // 表示フラグ、エリアビットをコピー
        // (名前はGPXから読み込んだものが優先される)
        newTatsuma.visible = orgTatsumas[i].visible;
        newTatsuma.areaBits = orgTatsumas[i].areaBits;
        newTatsuma.auxPoint = orgTatsumas[i].auxPoint;
        // 属性をコピーしたタツマはリストから削除
        orgTatsumas.removeAt(i);
        break;
      }
    }
    // 新規追加の場合は名前を記録
    if(!found){
      addTatsumaNames.add(newTatsuma);
    }
  }

  // 新規追加と削除に同じ名前があれば、座標の変更とみなす
  List<TatsumaData> modifyTatsumas = [];
  for(int i = 0; i < addTatsumaNames.length; i++){
    for(int j = 0; j < orgTatsumas.length; j++){
      if(addTatsumaNames[i].name == orgTatsumas[j].name){
        modifyTatsumas.add(orgTatsumas[j]);
        addTatsumaNames.removeAt(i);
        orgTatsumas.removeAt(j);
        i--;  // リストが縮小したのでインデックスを戻す
        break;
      }
    }
  }

  return {
    // newTatsumas のうち、属性がコピーされなかったものは新規追加
    "addTatsumas": addTatsumaNames,
    // orgTatsumas のうち、属性をコピーしなかったタツマは削除されたものとして
    "removeTatsumas": orgTatsumas,
    // modifyTatsumas は座標が変更されたもの
    "modifyTatsumas": modifyTatsumas,
  };
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
  for(int i = 0; i < areaNames.length; i++){
    final int maskBit = (1 << i);
    if((areaFilterBits & maskBit) != 0){
      res.add(areaNames[i]);
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
    final int index = areaNames.indexOf(name);
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
  final TextStyle textStyleGray = const TextStyle(color: Color(0xFF616161) /*grey[700]*/);

  // タツマデータからマーカー配列を作成
  // 非表示グレーマーカーが、可視のマーカーの下になるように描画順を制御
  tatsumaMarkers.clear();
  List<Marker> visibleMarkers = [];
  List<Marker> auxMarkers = [];
  for(final tatsuma in tatsumas){
    // タツマ(オレンジ)、主要地点(グリーン)、非表示を表示(グレー)毎にマーカーを作り分け
    Image? icon;
    TextStyle ts = textStyle;
    List<Marker> list = visibleMarkers;
    if (tatsuma.isVisible()) {
      if(!tatsuma.auxPoint) {
        // 表示状態のアイコン
        icon = _tatsumaIcon;
      }else{
        // 補助地点アイコン
        icon = _tatsumaIconGreen;
        list = auxMarkers;
      }
    } else if (showFilteredIcon) {
      // 非表示グレーマーカー
      icon = _tatsumaIconGray;
      ts = textStyleGray;
      list = tatsumaMarkers;
    }
    // マーカーを作成
    if (icon != null) {
      list.add(Marker(
        point: tatsuma.pos,
        width: 200.0,
        height: 64.0,
        anchorPos: AnchorPos.exactly(Anchor(100, 48)),
        builder: (ctx) => Column(
          // アイコンを中央寄せにするために、上部にダミーの空テキスト(マシな方法ないか？)
          children: [
            // 十字アイコン
            icon!,
            // タツマ名
            Text(tatsuma.name, style: ts),
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        )));
    }
  }
  // グレー > 表示状態の順
  tatsumaMarkers.addAll(auxMarkers);
  tatsumaMarkers.addAll(visibleMarkers);
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
  var _listScrollController = ScrollController();

  @override
  initState() {
    super.initState();

    // エリアラベルを作成
    // NOTE: 初回のみ
    if(_areaTags.isEmpty){
      // 表示のスタイル
      final BoxDecoration visibleBoxDec = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange, width:2),
        color: Colors.orange[200],
      );
      const visibleTexStyle = TextStyle(color: Colors.white);
      // 非表示のスタイル
      final BoxDecoration hideBoxDec = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey, width:2),
      );
      const hideTexStyle = TextStyle(color: Colors.grey);

      for(int i = 0; i < areaNames.length; i++){
        // 表示のエリアラベル
        _areaTags.add(Container(
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(vertical:2, horizontal:8),
          decoration: visibleBoxDec,
          child: Text(
            areaNames[i],
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
            areaNames[i],
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
    return WillPopScope(
      // ページ閉じる際の処理
      onWillPop: (){
        // ページの戻り値
        Navigator.of(context).pop(changeFlag);
        return Future.value(false);
      },
      child: Scaffold(
        // ヘッダー部
        appBar: AppBar(
          title: const Text("タツマ一覧"),
          actions: [
            // データベースへ保存
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed:() {
                saveAllTatsumasToDB();
                showTextBallonMessage("アップロード完了");
              },
            ),

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
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                );
              }),
            ),

            // エリアフィルター
            IconButton(
              icon: const Icon(Icons.filter_alt),
              onPressed:() {
                showAreaFilterDialog(
                  context, title:"エリアフィルター", showOptions:false).then((bool? res)
                {
                  if(res ?? false){
                    setState((){
                      changeFlag = true;
                    });
                    // エリアフィルターの設定をデータベースへ保存
                    saveAreaFilterToDB(openedFileUID.toString());
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
            changeFlag = true;
            if(res.containsKey("delete")){
              // 削除
              setState((){
                deleteTatsuma(index);
              });
            }else{
              // 変更
              setState((){
                tatsuma.name     = res["name"];
                tatsuma.visible  = res["visible"];
                tatsuma.areaBits = res["areaBits"];
                tatsuma.auxPoint = res["auxPoint"];
              });
            }
          }
        });
      }
    ));
    
    // アイコンの選択
    const hideColor = Color(0xFFBDBDBD)/*Colors.grey[400]*/;
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
//!!!!      child:MyListTile(
        child:ListTile(
        // (左側)表示非表示アイコンボタン
        leading: IconButton(
          icon: icon,
          onPressed:() {
            // 表示非表示の切り替え
            setState((){
              changeFlag = true;
              tatsuma.visible = !tatsuma.visible;
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
/*!!!!
        onLongPress: (TapDownDetails details){
          showPopupMenu(context, index, details.globalPosition);
        }
*/
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
        double zoom = mainMapController!.zoom;
        const double zoomInTarget = 16.25;
        if(zoom < zoomInTarget) zoom = zoomInTarget;
        final TatsumaData tatsuma = tatsumas[index];
        mainMapController!.move(tatsuma.pos, zoom);
        Navigator.pop(context);
        break;
      }
    });
  }

  //----------------------------------------------------------------------------
  // GPXからのタツマ読み込み処理
  Future<bool> readTatsumaFromGPXSub(BuildContext context) async
  {
    // GPXファイルのスロット選択
    final int? gpxSlot = await chooseGpxSlotDialog(context);
    if(gpxSlot == null) return false;
  
    // .pgx ファイルを選択して開く
    final typeGroups = [
      const XTypeGroup(label: 'gpx', extensions: ['gpx']),
    ];
    final XFile? file = await openFile(acceptedTypeGroups: typeGroups);
    if (file == null) return false;

    // ファイル読み込み
    final String fileContent = await file.readAsString();

    // XMLパース
    final Map<String,List<TatsumaData>>? res = readTatsumaFromGPX(fileContent, gpxSlot);
    if(res == null) return false;
    final addCount = res["addTatsumas"]?.length ?? 0;
    final removeCount = res["removeTatsumas"]?.length ?? 0;
    final modifyCount = res["modifyTatsumas"]?.length ?? 0;

    // メッセージを表示
    final String message =
      "$addCount個追加し、$removeCount個削除し、$modifyCount個変更しました。";
    showDialog(
      context: context,
      builder: (_){ return AlertDialog(content: Text(message)); });

    // タツマをデータベースへ保存して再描画
//!!!!    saveAllTatsumasToDB();
    setState((){
      changeFlag = true;
      updateTatsumaMarkers();
    });

    final bool changed = (0 < addCount) || (0 < removeCount);
    return changed;
  }
}

//----------------------------------------------------------------------------
// GPXファイルのスロット選択ダイアログ
Future<int?> chooseGpxSlotDialog(BuildContext context) async
{
  List<Widget> slots = [];
  const slotNames = [ "南足柄", "加増野", "(未定義)", "(未定義)" ];
  for(int i = 0; i < slotNames.length; i++){
    slots.add(ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
      leading: const Icon(Icons.folder),
      horizontalTitleGap: 0,
      title: Text(slotNames[i]),
      onTap: (){
        Navigator.pop(context, i);
      },
    ));      
  }

  return showDialog<int>(
    context: context,
    builder: (BuildContext context) {
      return SimpleDialog(
        title: const Row(children:[
          Icon(Icons.map),
          SizedBox(width: 8),
          Text("タツマフォルダ"),
        ]),
        titlePadding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
        contentPadding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 12.0),
        children: slots
      );
    },
  );
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
    required this.auxPoint,
  }){}

  // 名前
  String name;
  // 表示非表示フラグ
  bool visible;
  // エリアビット
  int  areaBits;
  // 補助地点フラグ
  bool auxPoint;

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
    // 表示/非表示アイコンと色
    final Icon visibilityIcon =
      widget.visible?
        const Icon(Icons.visibility):
        const Icon(Icons.visibility_off, color:Colors.grey);
    // 補助地点アイコンと色
    final Icon auxPointIcon =
      widget.auxPoint ?
        const Icon(Icons.landscape, color:Color(0xFF4CFF00)):
        const Icon(Icons.landscape_outlined, color:Colors.grey);

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("タツマ"),
          // 削除ボタン
          IconButton(
            icon: const Icon(Icons.delete),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: (){
              Navigator.pop<Map<String,dynamic>>(context, {
                "delete": true,
            });
            },
          ),
        ]
      ),
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

              // 補助地点アイコンボタン
              IconButton(
                icon: auxPointIcon,
                onPressed: (){
                  setState((){
                    widget.auxPoint = !widget.auxPoint;
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
          const SizedBox(height: 10), makeAreaButtonRow(0, 4, areaNames),
          const SizedBox(height: 5),  makeAreaButtonRow(4, 4, areaNames),
          const SizedBox(height: 5),  makeAreaButtonRow(8, 4, areaNames),
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
              "areaBits": widget.areaBits,
              "auxPoint": widget.auxPoint });
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
        areaBits: tatsuma.areaBits,
        auxPoint: tatsuma.auxPoint);
    },
  );
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// エリア表示フィルターの設定をデータベースへ保存
void saveAreaFilterToDB(String fileUID)
{
  // Firestore に保存
  final docRef = FirebaseFirestore.instance.collection("assign").doc(fileUID);
  final data = areaFilterToStrings();
  docRef.update({ "areaFilter": data });
}

// エリア表示フィルターの設定をデータベースから読み込み
// オフラインでかつ、キャッシュにデータが無い場合は false。
Future<Map<String,bool>> loadAreaFilterFromDB(String fileUID) async
{
  // Firestore から取得して作成
  final docRef = FirebaseFirestore.instance.collection("assign").doc(fileUID);

  // Firestore から読み込み
  bool existData = false;
  bool isFromCache = false;
  try{
    final docSnapshot = await docRef.get(); // オフラインかつキャッシュ無いとここで例外
    if(docSnapshot.exists){
      final doc = docSnapshot.data();
      final data = doc!["areaFilter"];
      existData = (data != null);
      if(existData){
        stringsToAreaFilter(data.cast<String>());
        isFromCache = docSnapshot.metadata.isFromCache;
      }
    }
  }catch(e) { /**/ }

  return { "existData": existData, "isFromCache": isFromCache };
}
