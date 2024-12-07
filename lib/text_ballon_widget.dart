import 'package:flutter/material.dart';
import 'globals.dart';

OverlayEntry? _overlayEntry;

//-----------------------------------------------------------------------------
// ポップアップメッセージの表示
void showTextBallonMessage(String message, { BuildContext? context })
{
  // 呼び出し元から BuildContext が渡されていない場合は、グローバルから参照
  context ??= appScaffoldKey.currentContext;
  if(context == null){
    return;
  }

  // 直前のオーバーレイを消去
  resetTextBallonMessage();

  // 画面中央に表示されるテキスト・ポップアップメッセージ
  _overlayEntry = OverlayEntry(
    builder: (cntx) => Align(  // AlignとRowで中央に表示
      alignment: Alignment.center,
      child: Row(                 // このRowがないと、なぜかテキストが全画面サイズに…
        mainAxisAlignment: MainAxisAlignment.center,
        children: [ 
          MyFadeOut(              // 消えるときのフェードアウトアニメーション
            child: Container(     // テキスト背景のボックス
              padding: const EdgeInsets.fromLTRB(25, 8, 25, 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(5),
              ),
              child:Text(
                message,
                style:TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade200,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ]),
    ),
  );
  
  // オーバーレイ表示を開始
  // 上の MyFadeOut でフェードアウトし、それが完了したら remove() される。
  Overlay.of(context).insert(_overlayEntry!);
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

