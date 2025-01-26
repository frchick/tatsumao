import 'package:flutter/material.dart';
import 'globals.dart';

OverlayEntry? _overlayEntry;

//-----------------------------------------------------------------------------
// ポップアップメッセージの表示
void showTextBallonMessage(String message, { BuildContext? context, bool? start_ellipsis })
{
  // 呼び出し元から BuildContext が渡されていない場合は、グローバルから参照
  context ??= appScaffoldKey.currentContext;
  if(context == null){
    return;
  }

  // 直前のオーバーレイを消去
  resetTextBallonMessage();

  // 文字スタイル
  final textStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade200,
    decoration: TextDecoration.none,
  );

  // 長いテキストの省略のために、テキストの最大幅を計算
  final sidePadding = 25.0;
  final maxTextWidth = MediaQuery.of(context).size.width - (2 * sidePadding);

  // 文字列が画面幅より長かった場合、
  TextOverflow? overflow;
  bool? softWrap;
  if((start_ellipsis != null) && start_ellipsis){
    // 最大幅を越えていたら、前側を切って省略記号
    var size = _getTextSize(message, textStyle);
    if(maxTextWidth < size.width){
      String t = "…";
      for(int i = 1; i < message.length; i++){
        t = "…" + message.substring(i);
        size = _getTextSize(t, textStyle);
        if(size.width <= maxTextWidth){
          break;
        }
      }
      message = t;
    }
  }else if((start_ellipsis != null) && !start_ellipsis){
    // 後ろ側を切って省略記号
    overflow = TextOverflow.ellipsis;
  }else{
    // 画面幅を超えるときは折り返し
    softWrap = true;
  }

  // 画面中央に表示されるテキスト・ポップアップメッセージ
  _overlayEntry = OverlayEntry(
    builder: (cntx) => Align(  // 中央に表示
      alignment: Alignment.center,
      child: MyFadeOut(       // 消えるときのフェードアウトアニメーション
        child: Container(     // テキスト背景のボックス
          padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(5),
          ),
          child: ConstrainedBox(  // 画面幅より長いテキストの制限
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child:Text(
              message,
              style: textStyle,
              overflow: overflow,
              softWrap: softWrap,
            ),
          ),
        ),
      ),
    ),
  );

  // オーバーレイ表示を開始
  // 上の MyFadeOut でフェードアウトし、それが完了したら remove() される。
  Overlay.of(context).insert(_overlayEntry!);
}

Size _getTextSize(String text, TextStyle style)
{
  final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr)
      ..layout();
  return textPainter.size;
}

//-----------------------------------------------------------------------------
// ポップアップメッセージを消去
void resetTextBallonMessage()
{
  if(_overlayEntry != null){
    _overlayEntry!.remove();
    _overlayEntry = null;
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 遅延フェードアウト
class MyFadeOut extends StatefulWidget {
  final Widget child;
  
  MyFadeOut({
    required this.child,
  }){}

  @override
  _MyFadeOutState createState() => _MyFadeOutState();
}

class _MyFadeOutState extends State<MyFadeOut>
    with TickerProviderStateMixin
{
  late AnimationController _controller;
  late Animation<double> _reverse;
  late Animation<double> _animation;

  // すでに表示が開始されているか
  bool _started = false;

  @override
  void initState()
  {
    super.initState();
    // 1.5秒のアニメーション
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this);
    // 表示→フェードアウトとなるように、値を逆転
    _reverse = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    // フェードアウトを遅延させる
    _animation = CurvedAnimation(
      parent: _reverse,
      curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
    );
    // アニメーション終了時に非表示
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        resetTextBallonMessage();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // アニメーション開始
    if(!_started){
      _started = true;
      _controller.forward(from: 0.0);
    }
  
    // アニメーションが終了していたら、Widgetを非表示にする。
    return Visibility(
      child: FadeTransition(opacity: _animation, child: widget.child));
  }
}

