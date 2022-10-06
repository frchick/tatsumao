import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'mydragmarker.dart';
import 'text_ballon_widget.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// メンバーデータ
class Member {
  Member({
    required this.name,
    required this.iconPath,
    required this.pos,
    this.attended = false,
    this.withdrawals = false,
  });
  // 名前
  String name;
  // ドラッグマーカーのアイコンの画像ファイル
  String iconPath;
  // 配置座標
  LatLng pos;
  // 参加しているか？(マップ上に配置されているか？)
  bool attended;
  // 退会者か？
  bool withdrawals;
  // ドラッグマーカーのアイコン
  late Image icon0;
}

List<Member> members = [
  Member(name:"ママっち", iconPath:"assets/member_icon/000.png", pos:LatLng(35.302880, 139.05100), attended: true),
  Member(name:"パパっち", iconPath:"assets/member_icon/002.png", pos:LatLng(35.302880, 139.05200), attended: true),
  Member(name:"高桑さん", iconPath:"assets/member_icon/006.png", pos:LatLng(35.302880, 139.05300), attended: true),
  Member(name:"今村さん", iconPath:"assets/member_icon/007.png", pos:LatLng(35.302880, 139.05400), attended: true),
  Member(name:"しゅうちゃん", iconPath:"assets/member_icon/004.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"まなみさん", iconPath:"assets/member_icon/008.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"がんちゃん", iconPath:"assets/member_icon/011.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"ガマさん", iconPath:"assets/member_icon/005.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"たかちん", iconPath:"assets/member_icon/009.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"加藤さん", iconPath:"assets/member_icon/010.png", pos:LatLng(35.302880, 139.05500), attended: true),
  Member(name:"長さん", iconPath:"assets/member_icon/012.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"望月さん", iconPath:"assets/member_icon/013.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"青池さん", iconPath:"assets/member_icon/014.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"田野倉さん", iconPath:"assets/member_icon/015.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"諸さん", iconPath:"assets/member_icon/016.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"ばったちゃん", iconPath:"assets/member_icon/017.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"あいちゃん", iconPath:"assets/member_icon/018.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"安達さん", iconPath:"assets/member_icon/019.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"友爺", iconPath:"assets/member_icon/020.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"矢崎さん", iconPath:"assets/member_icon/021.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"秋田さん", iconPath:"assets/member_icon/022.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"やまP", iconPath:"assets/member_icon/023.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"梅澤さん", iconPath:"assets/member_icon/024.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"マッスー", iconPath:"assets/member_icon/025.png", pos:LatLng(35.302880, 139.05500), withdrawals:true),
  Member(name:"福島さん", iconPath:"assets/member_icon/026.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"池田さん", iconPath:"assets/member_icon/027.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"山口さん", iconPath:"assets/member_icon/028.png", pos:LatLng(35.302880, 139.05500)),

  Member(name:"娘っち", iconPath:"assets/member_icon/001.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"りんたろー", iconPath:"assets/member_icon/003.png", pos:LatLng(35.302880, 139.05200)),
];

// メンバーのマーカー配列
// 出動していないメンバー分もすべて作成。表示/非表示を設定しておく。
List<MyDragMarker> memberMarkers = [];

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// メンバーデータの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

// このアプリケーションインスタンスを一意に識別するキー
final String _appInstKey = UniqueKey().toString();

// メンバーのアサインデータへのパス
String _assignPath = "";

// 地図再描画のコールバック
Function()? _updateMapViewFunc;

// 初期化
Future initMemberSync(String path, Function() updateMapViewFunc) async
{
  print(">initMemberSync($path)");

  // 地図再描画のコールバックを設定
  _updateMapViewFunc = updateMapViewFunc;

  // 配置データのパス
  _assignPath = "assign" + path;
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
      // 地図上に表示されているメンバーマーカーの情報も変更
      memberMarkers[index].visible = member.attended;
      memberMarkers[index].point = member.pos;
    } else {
      // データベースにメンバーデータがなければ作成
      syncMemberState(index);
    }    
  }

  // 他の利用者からの変更通知を登録
  for(int index = 0; index < members.length; index++){
    final String id = index.toString().padLeft(3, '0');
    final DatabaseReference ref = database.ref(_assignPath + "/" + id);
    ref.onValue.listen((DatabaseEvent event){
      onChangeMemberState(index, event);
    });
  }
}

// メンバーマーカーの移動を他のユーザーへ同期
void syncMemberState(final int index) async
{
  final Member member = members[index];
  final String id = index.toString().padLeft(3, '0');

  DatabaseReference memberRef = database.ref(_assignPath + "/" + id);
  memberRef.update({
    "sender_id": _appInstKey,
    "attended": member.attended,
    "latitude": member.pos.latitude,
    "longitude": member.pos.longitude
  });

  // NOTE: 退会者かどうかのフラグは、配置データとは関係ない。
  // NOTE: 過去の配置データに参加していれば、退会後もその配置データでは表示される。
}

// 他の利用者からの同期通知による変更
void onChangeMemberState(final int index, DatabaseEvent event)
{
  final DataSnapshot snapshot = event.snapshot;

  // 自分が送った変更には(当然)反応しない。送信者IDと自分のIDを比較する。
  final String sender_id = snapshot.child("sender_id").value as String;
  final bool fromOther =
    (sender_id != _appInstKey) &&
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
    if(_updateMapViewFunc != null){
      _updateMapViewFunc!();
    }

    // 家に帰った/参加したポップアップメッセージ
    if(returnToHome){
      final String msg = members[index].name + " は家に帰った";
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
