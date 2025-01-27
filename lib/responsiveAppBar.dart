import 'package:flutter/material.dart';
import 'globals.dart';

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// 幅によって1行2行レイアウトが切り替わる AppBar
class ResponsiveAppBar
{
  // タイトルとアクションが重なっているか判定するための仕組み
  final _titleLineTailKey = GlobalKey();
  final _actionsLineHeadKey = GlobalKey();
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
    final screenSize = MediaQuery.of(context).size;
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
            // アクションアイコンの先頭位置を取得するためのダミーウィジェット
            SizedBox(key:_actionsLineHeadKey, width:0, height:lineHeight),
            // アクションアイコンの配列
            ...actionsLine,
          ]
        ),
      );
    }

    // タイトルテキストが幅を超える場合に、テキストの先頭を省略する処理
    if(titleLine.last is Text){
      final org = titleLine.last as Text;
      String titleText = org.data!;
      final scaleFactor = (narrowWidth? 0.8: 1.0);
      final titleTextStyle = Theme.of(context).textTheme.titleLarge!;
      Size textSize = getTextLineSize(titleText, titleTextStyle, scaleFactor);

      // LayoutBuilder で、AppBar のレイアウト中にテキストを表示できる最大幅を取得
      // NOTE: Expanded でラップしないと、constraints.maxWidth が無限大になる…
      titleLine.last = Expanded(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints){
            // 2行レイアウトの時、テキスト終端が最大幅を越えてしまうようなら、先頭を省略する
            final margin = (constraints.maxWidth - textSize.width);
            final ellipsisText = _2LineLayout && (margin < 0);
            if(ellipsisText){
              final r = ellipsisTextStart(
                titleText, titleTextStyle, constraints.maxWidth, scaleFactor:scaleFactor);
              titleText = r["text"] as String;
              textSize = r["size"] as Size;
            }

            // テキストを表示
            // Row にラップしないと、テキストの終端座標を取得できない
            return Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  key:_titleLineTailKey,  // テキストの終端座標を参照するためのキー
                  textScaleFactor: scaleFactor),
              ],
            );
          },              
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
        // タイトル行の配列
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Rowの高さを1行の高さにあわせるためのダミー
            SizedBox(width:0, height:lineHeight),
            // タイトル行の配列
            ...titleLine
          ]
        ),
        // アクション行の配列
        if(actions != null) actions,
      ],
    );
        
    // ウィンドウリサイズで再構築を走らせるためのおまじない
    // ファイルパスとアイコンが重なっているか判定して、1行/2行構成を切り替える
    if(arrow2Line){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if((_titleLineTailKey.currentContext != null) &&
          (_actionsLineHeadKey.currentContext != null)){
          final box0 = _titleLineTailKey.currentContext!.findRenderObject() as RenderBox;
          final box1 = _actionsLineHeadKey.currentContext!.findRenderObject() as RenderBox;
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
