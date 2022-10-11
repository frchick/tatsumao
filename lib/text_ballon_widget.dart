import 'package:flutter/material.dart';
import 'dart:async';

final _textBallonStream = StreamController<String>();

// Streamから取得されるメッセージが表示済みかどうかを判定するためのIDX
int _textBallonMessageIdx = 0;
int _lastTextBallonMessageIdx = 0;

//-----------------------------------------------------------------------------
// ポップアップメッセージの表示
void showTextBallonMessage(String message)
{
  // NOTE: 画面の再構築に伴う TextBallonWidget.build() の呼び出しで、直前のメッセージが
  // NOTE: 繰り返し表示されることを抑止するためのメッセージ識別IDXをカウントする。
  _textBallonMessageIdx++;
  _textBallonStream.sink.add(message);
}

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
class TextBallonWidget extends StatelessWidget
{
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      // 指定したstreamにデータが流れてくると再描画される
      stream: _textBallonStream.stream,
      builder: (BuildContext context, AsyncSnapshot<String> snapShot) {
        // NOTE: メッセージの更新がない、もしくはメッセージが空の場合には何も表示しない。
        if((_lastTextBallonMessageIdx == _textBallonMessageIdx) || (snapShot.data == null)){
          return Container();
        }
        _lastTextBallonMessageIdx = _textBallonMessageIdx;
        // フェードアウトメッセージを表示
        return MyFadeOut(
          child: Container(
            padding: EdgeInsets.fromLTRB(25, 8, 25, 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              snapShot.data!,
              style:TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade200,
              ),
              textScaleFactor: 1.25,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
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
  initState() {
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

