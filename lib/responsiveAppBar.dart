import 'package:flutter/material.dart';

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// 幅によって1行2行レイアウトが切り替わる AppBar
class ResponsiveAppBar
{
  // タイトルとアクションが重なっているか判定するための仕組み
  GlobalKey _titleLineTailKey = GlobalKey();
  GlobalKey _actionsLineHeadKey = GlobalKey();
  // 2行レイアウトにするかどうか
  bool _2LineLayout = false;

  AppBar makeAppBar(
    BuildContext context,
    {
    // タイトル(左側/1行目)の Widget 配列
    required List<Widget> titleLine,
    // アクション(右側/2行目)の Widget 配列
    required List<Widget> actionsLine,
    // 透明度(指定なしで不透明)
    double? opacity,
    bool automaticallyImplyLeading = true,
    required Function setState,
    // 1行の高さ(アイコンボタンある場合が40pxで、それに合わせてある)
    double lineHeight = 40.0,
    })
  {
    // 幅が狭ければ、微調整を入れる
    var screenSize = MediaQuery.of(context).size;
    final bool narrowWidth = (screenSize.width < 640);
    final bool arrow2Line = actionsLine.isNotEmpty;
    _2LineLayout = arrow2Line && _2LineLayout;

    // アクション
    Widget? actions;
    if(actionsLine.isNotEmpty){
      actions = Padding(
        padding: EdgeInsets.only(top:(_2LineLayout? 30: 0)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(key:_actionsLineHeadKey, width:0, height:lineHeight),
            ...actionsLine,
          ]
        ),
      );
    }

    // 画面横幅が狭い場合は、AppBar上のファイルパスとアクションボタンを二行レイアウトにする
    // いわゆるレスポンシブデザイン！？
    // NOTE: titleLine が長くて画面右にかかる場合でも、TextOverflow.ellipsis が効かない。
    // 通常、Raw 内の Text は Expanded でラップすればよいが、そうするとテキストの右端座標を
    // 取得する仕組みとバッティングしてうまくいかない。
    Widget contents = Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ...titleLine,
            Container(key:_titleLineTailKey, width:0, height:lineHeight),
            Expanded(child: Text("")),
          ]
        ),
        if(actions != null) actions,
      ],
    );
        
    // ウィンドウリサイズで再構築を走らせるためのおまじない
    // ファイルパスとアイコンが重なっているか判定して、1行/2行構成を切り替える
    if(arrow2Line){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if((_titleLineTailKey.currentContext != null) &&
          (_actionsLineHeadKey.currentContext != null)){
          final RenderBox box0 = _titleLineTailKey.currentContext!.findRenderObject() as RenderBox;
          final RenderBox box1 = _actionsLineHeadKey.currentContext!.findRenderObject() as RenderBox;
          final double textRight = box0.localToGlobal(Offset.zero).dx + box0.size.width;
          final double buttonsLeft = box1.localToGlobal(Offset.zero).dx;
          final bool overlap = (buttonsLeft < textRight);
          if(_2LineLayout != overlap){
            setState((){ _2LineLayout = overlap; });
          }
        }
      });
    }
  
    // アプリケーションバーの半透明
    final Color? backgroundColor = (opacity != null)?
      Theme.of(context).primaryColor.withOpacity(opacity!):
      null;

    // 2行レイアウト時の高さ
    final double? height = _2LineLayout? (2*lineHeight): null;

    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      toolbarHeight: height,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: (narrowWidth? 0: null), // 狭い画面なら左右パディングなし
      title: contents,
    );
  }
}
