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
    // 表示/非表示フラグと、エリアの表示判定をチェック
    return
      visible &&
      ((areaBits == 0) || ((areaBits & areaFilterBits) != 0));
  }
}

// タツマの適当な初期データ。
List<TatsumaData> tatsumas = [
  TatsumaData(LatLng(35.306227, 139.049396), "岩清水索道", true, 1, 0),
  TatsumaData(LatLng(35.307217, 139.051598), "岩清水中", true, 1, 1),
  TatsumaData(LatLng(35.306809, 139.052676), "岩清水下", true, 1, 2),
  TatsumaData(LatLng(35.306282, 139.047802), "岩清水", true, 1, 3),
  TatsumaData(LatLng(35.305798, 139.054232), "赤エル", true, 3, 4),
  TatsumaData(LatLng(35.30636, 139.05427), "裏赤エル", true, 3, 5),
  TatsumaData(LatLng(35.305804, 139.055972), "ストッパー", true, 3, 6),
  TatsumaData(LatLng(35.304213, 139.046478), "新トナカイ", true, 1, 7),
  TatsumaData(LatLng(35.305561, 139.045259), "トナカイ", true, 1, 8),
  TatsumaData(LatLng(35.302601, 139.04473), "ムロ岩の先", true, 1, 9),
  TatsumaData(LatLng(35.302488, 139.044131), "ムロ岩", true, 1, 10),
  TatsumaData(LatLng(35.301932, 139.043382), "スター", true, 1, 11),
  TatsumaData(LatLng(35.301166, 139.043601), "アメリカ", true, 1, 12),
  TatsumaData(LatLng(35.300012, 139.044023), "太平洋", true, 1, 13),
  TatsumaData(LatLng(35.30026, 139.046538), "メキシコ", true, 1, 14),
  TatsumaData(LatLng(35.29942, 139.04639), "沢の上", true, 1, 15),
];

// 猟場のエリア名
// NOTE: 設定ボタン表示の都合で、4の倍数個で定義
const List<String> _areaNames = [
  "暗闇沢", "ホンダメ", "苅野上", "笹原林道",
  "桧山", "桧山下", "桧山上", "茗荷谷",
  "金太郎上", "金太郎東", "金太郎下", "",
];

// エリア表示フィルターのビット和
int areaFilterBits = (1 << _areaNames.length) - 1;

// ソートされているか
bool _isListSorted = false;

// マップ上のタツマのマーカー配列
List<Marker> tatsumaMarkers = [];

// タツマデータの保存と読み込みデータベース
FirebaseDatabase database = FirebaseDatabase.instance;

// タツマアイコン画像
// NOTE: 表示回数が多くて静的なので、事前に作成しておく
final Image _tatsumaIcon = Image.asset(
  "assets/misc/tatsu_pos_icon.png",
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
// タツマをデータベースへ保存
void saveTatsumaToDB()
{
  // ソートされている場合でも、元の順番で書き出す。
  List<TatsumaData> tempList = [...tatsumas];
  tempList.sort((a, b){ return a.originalIndex - b.originalIndex; });

  // タツマデータをJSONの配列に変換
  List<Map<String, dynamic>> data = [];
  tempList.forEach((tatsuma){
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
      addCount++;
      index++;
    }
  });

  // マージで追加したタツマ数を返す
  return addCount;
}

//----------------------------------------------------------------------------
// タツマ一覧をソート
void sortTatsumas()
{
  tatsumas.sort((a, b){
    // まずは表示を前に、非表示を後ろに
    final int v = (a.isVisible()? 0: 1) - (b.isVisible()? 0: 1);
    if(v != 0) return v;
    // エリア毎にまとめる
    if(a.areaBits != b.areaBits) return (a.areaBits - b.areaBits);
    // 最後に元の順番
    return (a.originalIndex - b.originalIndex);
  });
  _isListSorted = true;
}

// タツマ一覧のソートを解除
void unsortTatsumas()
{
  tatsumas.sort((a, b){ return a.originalIndex - b.originalIndex; });
  _isListSorted = false;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツママーカーを更新
void updateTatsumaMarkers()
{
  // タツマデータからマーカー配列を作成
  tatsumaMarkers.clear();
  tatsumas.forEach((tatsuma) {
    // 非表示のタツマは除外
    if(!tatsuma.isVisible()) return;

    tatsumaMarkers.add(Marker(
      point: tatsuma.pos,
      width: 200.0,
      height: 96.0,
      builder: (ctx) => Column(
        children: [
          Text(""),
          _tatsumaIcon,
          Text(tatsuma.name, style:TextStyle(fontWeight: FontWeight.bold))
        ],
        mainAxisAlignment: MainAxisAlignment.center,
      )
    ));
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
                  if(onSwitch) sortTatsumas();
                  else unsortTatsumas();
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
                  }
                });
              },
            ),
          ],
        ),

        // タツマ一覧
        body: ListView.builder(
          itemCount: tatsumas.length,
          itemBuilder: (context, index){
            return _menuItem(context, index);
          },
          controller: _listScrollController,
        ),
      )
    );
  }

  // タツマ一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index) {
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
        showChangeTatsumaDialog(context, index).then((res){
          if(res != null){
            setState((){
              changeFlag = true;
              tatsuma.name     = res["name"] as String;
              tatsuma.visible  = res["visible"] as bool;
              tatsuma.areaBits = res["areaBits"] as int;
            });
          }
        });
      }
    ));
    
    return Container(
      // 境界線
      decoration: const BoxDecoration(
        border:Border(
          bottom: const BorderSide(width:1.0, color:Colors.grey)
        ),
      ),
      // 表示/非表示アイコンとタツマ名
      child:ListTile(
        // (左側)表示非表示アイコンボタン
        leading: IconButton(
          icon: (tatsuma.visible? const Icon(Icons.visibility): const Icon(Icons.visibility_off)),
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
          style: (tatsuma.isVisible()? null: const TextStyle(color: Colors.grey)),
        ),

        // (右側)エリアタグと編集ボタン
        trailing: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: areaTagsAndButton
        ),

        onTap: (){
        },
      ),
    );
  }

  //----------------------------------------------------------------------------
  // タツマ名変更ダイアログ
  Future<Map<String,dynamic>?> showChangeTatsumaDialog(BuildContext context, int index)
  {
    return showDialog<Map<String,dynamic>>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final TatsumaData tatsuma = tatsumas[index];
        return TatsumaDialog(
          name: tatsuma.name,
          visible: tatsuma.visible,
          areaBits: tatsuma.areaBits);
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
  @override
  Widget build(BuildContext context) {
    final dateTextController = TextEditingController(text: widget.name);
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
                  controller: dateTextController,
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
              "name": dateTextController.text,
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
//----------------------------------------------------------------------------
// エリア表示フィルターダイアログ
class AreaFilterDialog extends StatefulWidget
{
  AreaFilterDialog(){
    _areaFilterBits0 = areaFilterBits;
  }

  @override
  AreaFilterDialogState createState() => AreaFilterDialogState();

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
    List<ListTile> areas = [];
    for(int i = 0; i < _areaNames.length; i++){
      final int maskBit = (1 << i);
      final bool visible = (areaFilterBits & maskBit) != 0;

      areas.add(ListTile(
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
        },
      ));
    };

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
        title: Row(
          children:[
            const Text("エリア表示フィルター"),
            // 一律表示
            IconButton(
              icon: const Icon(Icons.visibility),
              onPressed:() {
                // 表示非表示を反転
                setState((){
                  areaFilterBits = (1 << _areaNames.length) - 1;
                });
              },
            ),
            // 一律非表示
            IconButton(
              icon: const Icon(Icons.visibility_off),
              onPressed:() {
                // 表示非表示を反転
                setState((){
                  areaFilterBits = 0;
                });
              },
            ),
          ]
        ),
        // エリア一覧
        children: areas
      )
    );
  }
}

Future<bool?> showAreaFilter(BuildContext context)
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context){
      return AreaFilterDialog();
    },
  );
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ON/OFFアイコンボタン
// NOTE: ON/OFFの状態があるので StatefulWidget の気がするが、
// NOTE: ON/OFF変更時に毎回、親から状態を指定されて再構築されるので、結局 StatelessWidget でよい。
class OnOffIconButton extends StatelessWidget
{
  OnOffIconButton({
    super.key,
    required this.icon,
    required this.onSwitch,
    this.onChange,
  });

  // アイコン
  Icon icon;
  // ON/OFF
  bool onSwitch;
  // ON/OFF切り替え処理
  Function(bool)? onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if(onSwitch){
      // ON状態
      // 丸型の座布団敷いて色反転
      return Ink(
        decoration: ShapeDecoration(
          color: theme.colorScheme.onPrimary,
          shape: CircleBorder(),
        ),
        child: IconButton(
          icon: icon,
          color: theme.primaryColor,
          // ON->OFF
          onPressed:() {
            onChange?.call(false);
          },
        ),
      );
    }else{
      // OFF状態
      return IconButton(
        icon: icon,
        // OFF->ON
        onPressed:() {
          onChange?.call(true);
        },
      );
    }
  }
}
