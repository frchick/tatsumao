import 'package:flutter/material.dart';
import 'dart:async';

final _textBallonStream = StreamController<String?>.broadcast();

//-----------------------------------------------------------------------------
// ポップアップメッセージの表示
void showTextBallonMessage(String message)
{
  _textBallonStream.sink.add(message);
}

//-----------------------------------------------------------------------------
// ポップアップメッセージの表示を抑制
void resetTextBallonMessage()
{
  // NOTE: 画面の再構築に伴う TextBallonWidget.build() の呼び出しで、直前のメッセージが
  // NOTE: 繰り返し表示されることを抑止するため、ストリーム内のデータをクリアする。
  _textBallonStream.sink.add(null);
}

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
class TextBallonWidget extends StatefulWidget
{
  TextBallonWidget({
    super.key,
  }){}

     @override
  _TextBallonWidgetState createState() => _TextBallonWidgetState();
}

class _TextBallonWidgetState extends State<TextBallonWidget>
{
  @override
  Widget build(BuildContext context)
  {
    return StreamBuilder(
      // 指定したstreamにデータが流れてくると再描画される
      stream: _textBallonStream.stream,
      builder: (BuildContext context, AsyncSnapshot<String?> snapShot)
      {
        return _makeBallonWidget(snapShot.data);
      }
    );
  }

  Widget _makeBallonWidget(String? text)
  {
    // メッセージが空の場合には何も表示しない。
    if(text == null){
      return Container();
    }

    // フェードアウトメッセージを表示
    return MyFadeOut(
      child: Container(
        padding: EdgeInsets.fromLTRB(25, 8, 25, 8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style:TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade200,
          ),
          textScaleFactor: 1.25,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 遅延フェードアウト
class MyFadeOut extends StatefulWidget {
  final Widget child;
  
  // アニメーションの再生が終わったかのフラグ
  // Widget側のメンバーは、インスタンスを作り直すごとにリセットされる。
  // State側のメンバーは、インスタンスが作り直されても永続する？
  bool _completed = false;

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

  @override
  initState()
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
      curve: Interval(0.0, 0.25, curve: Curves.easeIn),
    );
    // アニメーション終了時に非表示
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          widget._completed = true;
        });
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
    // アニメーション終了後の更新では、当然アニメーションの開始はしない。
    if(!widget._completed){
      _controller.forward(from: 0.0);
    }
  
    // アニメーションが終了していたら、Widgetを非表示にする。
    return Visibility(
      visible: !widget._completed,
      child: FadeTransition(opacity: _animation, child: widget.child));
  }
}

