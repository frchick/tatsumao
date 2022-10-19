import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';   // Stream使った再描画

import 'mydrag_target.dart';  // メンバー一覧のマーカー

import 'text_ballon_widget.dart';
import 'members.dart';
import 'tatsumas.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 家ボタン＆メンバー一覧メニュー
class HomeIconWidget extends StatelessWidget
{
  HomeIconWidget({
    super.key,
  });

  // メンバーメニュー領域の高さ
  static const double menuHeight = 120;

  // 外部からの再描画
  static var _stream = StreamController();

  // BottomSheet の再描画
  late StateSetter _setModalState;

  //----------------------------------------------------------------------------
  // 再描画
  static void update()
  {
    _stream.sink.add(null);
  }

  //----------------------------------------------------------------------------
  // メンバー一覧メニューからドラッグして出動！
  void onDragEndFunc(MyDraggableDetails details)
  {
    // メンバー一覧メニューの外にドラッグされていなければ何もしない。
    // ドラッグ座標はマーカー左上なので、下矢印の位置にオフセットする。
    var px = details.offset.dx + 32;
    var py = details.offset.dy + 72;
    final double screenHeight = getScreenHeight();
    if((screenHeight - menuHeight) < py) return;
  
    // ドラッグ座標からマーカーの緯度経度を計算
    LatLng? point = mainMapController.pointToLatLng(CustomPoint(px, py));
    if(point == null) return;

    // タツママーカーにスナップ
    point = snapToTatsuma(point);

    // メニュー領域の再描画
    final int index = details.data;
    _setModalState?.call((){
      // データとマップ上マーカーを出動/表示状態に
      members[index].attended = true;
      memberMarkers[index].visible = true;
      if(point != null){
        members[index].pos = point;
        memberMarkers[index].point = point;
      }
    });

    // 地図上のマーカーの再描画
    updateMapView();
    HomeIconWidget.update();

    // データベースに変更を通知
    syncMemberState(index);
  }

  //----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context)
  {
    return Align(
      // 画面右下に配置
      alignment: const Alignment(1.0, 1.0),
      child: Stack(children:[
        // 家アイコン
        ElevatedButton(
          child: const Icon(Icons.home, size: 50),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.orange.shade900,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            fixedSize: Size(80,80),
          ),

          // 家ボタンタップでメンバー一覧メニューを開く
          onPressed: ()
          {
            showMembersBottomSheet(context);
          },

          // 長押しでサブメニュー
          onLongPress: (){
            // 編集ロックならサブメニュー出さない
            if(lockEditing) return;
            showPopupMenu(context);
          },
        ),

        // 参加してないメンバーの人数
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          height: 20,
          width: 20,
          margin: EdgeInsets.only(left:50, top:10),
          alignment: Alignment(0.0, 0.0),
          // 人数の表示は Stream 用いた再描画に対応
          child: StreamBuilder(
            stream: HomeIconWidget._stream.stream,
            builder: (BuildContext context, AsyncSnapshot snapShot)
            {
              // 参加していないメンバーの人数を数える
              int numAbsenter = 0;
              members.forEach((member){
                if(!member.attended && !member.withdrawals) numAbsenter++;
              });
              return Text("${numAbsenter}",
                style: const TextStyle(fontSize:12, color:Colors.white));
            }
          ),
        ),
      ]),
    );
  }

  //----------------------------------------------------------------------------
  // 画面下部のメンバー一覧ボトムシートを開く
  void showMembersBottomSheet(BuildContext context)
  {
    // メンバー一覧メニューを開く
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context)
      {
        return StatefulBuilder(
          builder: (context, StateSetter setModalState)
          {
            _setModalState = setModalState;

            // 出動していないメンバーのアイコンを並べる
            // NOTE: メンバーをドラッグで地図に配置した際、この StatefulBuilder.builder() で
            // NOTE: 再描画を行う。そのためアイコンリストの構築はココに実装する必要がある。
            // NOTE: 退会者はここに表示しないことで、新たにマップ上に配置できないようにする。
            List<Widget> draggableIcons = [];
            for(int index = 0; index < members.length; index++)
            {
              final Member member = members[index];
              if(member.attended || member.withdrawals) continue;

              final String name = members[index].name;
              draggableIcons.add(Align(
                alignment: const Alignment(0.0, -0.8),
                child: GestureDetector(
                  child: MyDraggable<int>(
                    data: index,
                    child: member.icon0,
                    feedback: member.icon0,
                    childWhenDragging: Container(
                      width: 64,
                      height: 72,
                    ),
                    onDragEnd: onDragEndFunc,
                    // 編集がロックされいたらドラッグによる出動を抑止
                    maxSimultaneousDrags: (lockEditing? 0: null),
                  ),
                  // タップして名前表示
                  onTap: (){
                    // ポップアップメッセージ
                    showTextBallonMessage(name);
                  }
                )
              ));
            };

            // 高さ120ドット、横スクロールのリストビュー
            final ScrollController controller = ScrollController();
            return Container(
              height: menuHeight,
              color: Colors.brown.shade100,
              child: Scrollbar(
                thumbVisibility: true,
                controller: controller,
                child: ListView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  children: draggableIcons,
                ),
              ),
            );
          },
        );
      },
    );
  }

  //----------------------------------------------------------------------------
  // 家アイコン長押しのポップアップメニュー
  void showPopupMenu(BuildContext context)
  {
    final double x = context.size!.width;
    final double y = context.size!.height - 150;
    
    // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(x, y, 0, 0),
      elevation: 8.0,
      items: [
        PopupMenuItem(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.hotel, color: Colors.black45),
              const SizedBox(width: 5),
              const Text('全員家に帰る'),
            ]
          ),
          height: (kMinInteractiveDimension * 0.8),
        ),
      ],
    ).then((value) {
      switch(value ?? -1){
      case 0:
        // 全員を家に帰す
        if(goEveryoneHome()){
          updateMapView();
          HomeIconWidget.update();
        }
        break;
      }
    });
  }
}
