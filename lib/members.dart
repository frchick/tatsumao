import 'dart:async';
import 'dart:math'; // min,max

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';   // for クリップボード

import 'mydragmarker.dart';   // マップ上のメンバーマーカー
import 'text_ballon_widget.dart';
import 'text_multiline_dialog.dart';
import 'tatsumas.dart';
import 'home_icon.dart';
import 'file_tree.dart';
import 'myfs_image.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 外部参照されるグローバル変数

// 適当な初期位置
final _defaultPos = LatLng(35.302880, 139.05100);

// メンバーアイコンのパス
const String _iconPath = "assets/member_icon/";

// メンバーアイコンの読み込み中に表示するアイコン
// こちらはWEBアプリの assets から読み込み。(Cloud Storage ではない)
final Image _loadingIcon = Image.asset(_iconPath + 'loading.png', width:64, height:72);

// メンバー一覧データ
// loadMembersListFromDB() で firebase realtime database から読み込まれる。
// この配列の並び順が配置データと関連しているので、順番を変えないこと！
// TODO: メンバー一覧 BottomSheet でのメンバーアイコンの並び順を変えられるようにする。
List<Member> members = [];

// メンバーのマーカー配列
// 出動していないメンバー分もすべて作成。表示/非表示を設定しておく。
List<MyDragMarker> memberMarkers = [];

// メンバーマーカーのサイズ指定
// [0:大 / 1:小 / それ以外:非表示]
int memberMarkerSizeSelector = 0;

// メンバーマーカーの表示/非表示フラグ
bool isShowMemberMarker()
{
  return (memberMarkerSizeSelector < 2);
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// メンバーデータ
class Member {
  Member({
    required this.index,
    required this.name,
    required this.iconFile,
    required this.pos,
    required this.orderSortValue,
    this.attended = false,
    this.withdrawals = false,
  });
  // 名前
  String name;
  // ドラッグマーカーのアイコンの画像ファイル
  String iconFile;
  // 配置座標
  LatLng pos;
  // 参加しているか？(マップ上に配置されているか？)
  bool attended;
  // 退会者か？
  bool withdrawals;
  // 起動直後のデータベース変更通知を受け取ったか
  bool firstSyncEvent = true;
  // ドラッグマーカーのアイコン
  Widget? icon0;
  // ドラッグマーカーのアイコンのキー
  final Key iconKey = GlobalKey();
  // メンバー一覧リスト上のインデックス
  final int index;
  // 表示順ソート用の比較値
  final int orderSortValue;
}

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// メンバーデータの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

// メンバーのアサインデータへのパス
String _assignPath = "";

// 現在のデータベース変更通知のリスナー
List<StreamSubscription<DatabaseEvent>> _membersListener = [];

// メンバー一覧データをデータベースから取得
Future loadMembersListFromDB() async
{
  print(">loadMembersListFromDB()");

  // キーの存在をチェックして、あればメンバー一覧を読み込む
  final snapshot = await FirebaseFirestore.instance.collection("members").get();
  final documentList = snapshot.docs;

  members.clear();
  for(int i = 0; i < documentList.length; i++){
    final m = documentList[i].data();
    final withdrawals = m.containsKey("withdrawals") ? m["withdrawals"] as bool : false;
    members.add(Member(
      index: i,
      name: m["name"] as String,
      iconFile: m["icon"] as String,
      pos: _defaultPos,
      withdrawals: withdrawals,
      orderSortValue: m["order"] as int));
  }
}

//---------------------------------------------------------------------------
// 初期化
Future initMemberSync(String uidPath) async
{
  print(">initMemberSync($uidPath)");

  // 配置データのパス
  _assignPath = "assign" + uidPath;
  final DatabaseReference ref = database.ref(_assignPath);
  final DataSnapshot snapshot = await ref.get();
  for(int index = 0; index < members.length; index++)
  {
    Member member = members[index];
    final String id = index.toString().padLeft(3, '0');

    if (snapshot.hasChild(id)) {
      // メンバーデータがデータベースにあれば、初期値として取得(直前の状態)
      // NOTE: 退会者かどうかのフラグは、配置データとは関係ない。
      // NOTE: 過去の配置データに参加していれば、退会後もその配置データでは表示される。
      member.attended = snapshot.child(id + "/attended").value as bool;
      member.pos = LatLng(
        snapshot.child(id + "/latitude").value as double,
        snapshot.child(id + "/longitude").value as double);
      member.firstSyncEvent = true;
      // 地図上に表示されているメンバーマーカーの情報も変更
      memberMarkers[index].visible = member.attended;
      memberMarkers[index].point = member.pos;
    } else {
      // データベースにメンバーデータがなければ作成
      syncMemberState(index);
    }    
  }

  // 他のユーザーからの変更通知を受け取るリスナーを設定
  // 直前のリスナーは停止しておく
  releaseMemberSync();
  for(int index = 0; index < members.length; index++){
    final String id = index.toString().padLeft(3, '0');
    final DatabaseReference ref = database.ref(_assignPath + "/" + id);
    var listener = ref.onValue.listen((DatabaseEvent event){
      onChangeMemberState(index, event);
    });
    _membersListener.add(listener);
  }
}

//---------------------------------------------------------------------------
// データベースからの変更通知を停止
void releaseMemberSync()
{
  _membersListener.forEach((listener){
    listener.cancel();
  });
  _membersListener.clear();
}

//---------------------------------------------------------------------------
// メンバーマーカーの移動を他のユーザーへ同期
void syncMemberState(final int index, { bool goEveryoneHome=false}) async
{
  final Member member = members[index];
  final String id = index.toString().padLeft(3, '0');
  final String senderId = goEveryoneHome? "GoEveryoneHome": appInstKey;

  DatabaseReference memberRef = database.ref(_assignPath + "/" + id);
  memberRef.update({
    "sender_id": senderId,
    "attended": member.attended,
    "latitude": member.pos.latitude,
    "longitude": member.pos.longitude
  });

  // NOTE: 退会者かどうかのフラグは、配置データとは関係ない。
  // NOTE: 過去の配置データに参加していれば、退会後もその配置データでは表示される。
}

//---------------------------------------------------------------------------
// 他の利用者からの同期通知による変更
void onChangeMemberState(final int index, DatabaseEvent event)
{
  final DataSnapshot snapshot = event.snapshot;

  // リスナー設定直後のイベントは破棄する
  if(members[index].firstSyncEvent){
    members[index].firstSyncEvent = false;
    print("onChangeMemberState(index:${index}) -> first event");
    return;
  }

  // 自分が送った変更には(当然)反応しない。送信者IDと自分のIDを比較する。
  final String sender_id = snapshot.child("sender_id").value as String;
  final bool fromOther =
    (sender_id != appInstKey) &&
    (event.type == DatabaseEventType.value);
  if(fromOther){
    print("onChangeMemberState(index:${index}) -> from other");
    // メンバーデータとマーカーのパラメータを、データベースの値に更新
    Member member = members[index];
    final bool attended = snapshot.child("attended").value as bool;
    final bool returnToHome = (member.attended && !attended);
    final bool joinToTeam = (!member.attended && attended);
    member.attended = attended;
    member.pos = LatLng(
      snapshot.child("latitude").value as double,
      snapshot.child("longitude").value as double);
    MyDragMarker memberMarker = memberMarkers[index];
    memberMarker.visible = member.attended;
    memberMarker.point = member.pos;

    // マーカーの再描画
    updateMapView();
    HomeIconWidget.update();

    // 家に帰った/参加したポップアップメッセージ
    if(returnToHome){
      late String msg;
      if(sender_id == "GoEveryoneHome"){
        msg = "全員家に帰った";
      }else{
        msg = members[index].name + " は家に帰った";
      }
      showTextBallonMessage(msg);
    }
    else if(joinToTeam){
      final String msg = members[index].name + " が参加した";
      showTextBallonMessage(msg);
    }
  }
  else{
    print("onChangeMemberState(index:${index}) -> myself");
  }
}

//---------------------------------------------------------------------------
// 全員家に帰る
bool goEveryoneHome()
{
  bool goHome = false;
  for(int i = 0; i < members.length; i++){
    if(members[i].attended){
      members[i].attended = false;
      memberMarkers[i].visible = false;
      syncMemberState(i, goEveryoneHome:true);
      goHome = true;
    }
  }
  return goHome;
}

//---------------------------------------------------------------------------
// タツマ配置をクリップボートへコピー
void copyAssignToClipboard(BuildContext context)
{
  // クリップボードにコピーする文字列を作成
  String text = "";

  // メンバーの配置
  int count = 0;
  String assignText = "";
  members.forEach((member){
    if(member.attended){
      TatsumaData? tatsuma = searchTatsumaByPoint(member.pos);
      String line;
      if(tatsuma != null){
        // メンバー名 + タツマ名
        line = member.name + ": " + tatsuma.name;
      }
      else{
        // タツマに立っていない？
        line = member.name + ": ["
          + member.pos.latitude.toStringAsFixed(4) + ","
          + member.pos.longitude.toStringAsFixed(4) + "]";
      }
      assignText += line + "\n";
      count++;
    }
  });

  // 先頭はファイル名と人数
  text  = getOpenedFileName() + "\n";
  text += "参加: ${count}人\n";
  text += assignText;

  // 起動リンク
  String fullPath = getOpenedFileUIDPath();
  fullPath = fullPath.replaceAll("/", "~");
  String fullURL = "https://tatsumao-976e2.web.app/?open=" + fullPath;
  fullURL = Uri.encodeFull(fullURL);
  final String textWithLink = text + fullURL;

  // ダイアログ表示
  showMultilineTextDialog(context, "タツマ配置", text).then((res) async {
    if(res ?? false){
      final data = ClipboardData(text: textWithLink);
      await Clipboard.setData(data);    
      showTextBallonMessage("配置をクリップボードへコピー");
    }
  });
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// メンバーマーカーの拡張クラス
class MyDragMarker2 extends MyDragMarker
{
  // 最後にデータベースに同期したドラッグ座標
  static LatLng _lastDraggingPoiny = LatLng(0,0);
  // ドラッグ中の連続同期のためのタイマー
  static Timer? _draggingTimer;

  MyDragMarker2({
    required super.point,
    super.builder,
    super.feedbackBuilder,
    super.width,
    super.height,
    super.offset,
    super.feedbackOffset,
    super.onLongPress,
    super.updateMapNearEdge = false, // experimental
    super.nearEdgeRatio = 2.0,
    super.nearEdgeSpeed = 1.0,
    super.rotateMarker = false,
    AnchorPos? anchorPos,
    required super.index,
    super.visible = true,
  })
  {
    super.onDragStart = onDragStartFunc;
    super.onDragUpdate = onDragUpdateFunc;
    super.onDragEnd = onDragEndFunc;
    super.onTap = onTapFunc;
  }

  //---------------------------------------------------------------------------
  // メンバーマーカーのドラッグ

  // ドラッグ中、マーカー座標をデータベースに同期する実装
  void onDragStartFunc(DragStartDetails details, LatLng point, int index)
  {
    // ドラッグ中の連続同期のためのタイマーをスタート
    Timer.periodic(const Duration(milliseconds: 500), (Timer timer){
      _draggingTimer = timer;
      // 直前に同期した座標から動いていたら変更を通知
      if(_lastDraggingPoiny != members[index].pos){
        _lastDraggingPoiny = members[index].pos;
        syncMemberState(index);
      }
    });
  }

  void onDragUpdateFunc(DragUpdateDetails detils, LatLng point, int index)
  {
    // メンバーデータを更新(ドラッグ中の連続同期のために)
    members[index].pos = point;
  }

  // ドラッグ終了時の処理
  LatLng onDragEndFunc(DragEndDetails details, LatLng point, Offset offset, int index, MapState? mapState)
  {
    // ドラッグ中の連続同期のためのタイマーを停止
    if(_draggingTimer != null){
      _draggingTimer!.cancel();
      _draggingTimer = null;
    }

    // 家アイコンに投げ込まれたら削除する
    // 画面右下にサイズ80x80で表示されている前提
    final bool dropToHome = 
      (0.0 < (offset.dx - (getScreenWidth()  - 80))) &&
      (0.0 < (offset.dy - (getScreenHeight() - 80)));
    if(dropToHome){
        // メンバーマーカーを非表示にして再描画
        memberMarkers[index].visible = false;
        members[index].attended = false;
        updateMapView();
        HomeIconWidget.update();

        // データベースに変更を通知
        syncMemberState(index);

        // ポップアップメッセージ
        String msg = members[index].name + " は家に帰った";
        showTextBallonMessage(msg);
        
        return point;
    }

    // タツママーカーにスナップ
    point = snapToTatsuma(point);

    // メンバーデータを更新
    members[index].pos = point;

    // データベースに変更を通知
    syncMemberState(index);

    return point;
  }

  //---------------------------------------------------------------------------
  // タップしてメンバー名表示
  void onTapFunc(LatLng point, int index)
  {
    // ポップアップメッセージ
    showTextBallonMessage(members[index].name);
  }
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// メンバーマーカーを作成
void createMemberMarkers()
{
  // サイズを決定
  const widthTable = [ 64.0, 42.0 ];
  const heightTable = [ 72.0, 48.0 ];
  final width  = widthTable[min(memberMarkerSizeSelector, 1)];
  final height = heightTable[min(memberMarkerSizeSelector, 1)];

  // メンバーデータからマーカー配列を作成
  memberMarkers.clear();
  int memberIndex = 0;
  members.forEach((member) {
    // アイコンを読み込んでおく
    member.icon0 ??= MyFSImage(
      _iconPath + member.iconFile, loadingIcon:_loadingIcon, key:member.iconKey);
    // マーカーを作成
    memberMarkers.add(
      MyDragMarker2(
        point: member.pos,
        builder: (ctx) => member.icon0!,
        width: width,
        height: height,
        offset: Offset(0.0, -height/2),
        feedbackOffset: Offset(0.0, -height/2),
        index: memberIndex,
        visible: member.attended,
      )
    );
    memberIndex++;
  });
}
