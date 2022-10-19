import 'package:flutter/material.dart';
import 'dart:async';   // Stream使った再描画

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
    this.iconOff,
    required this.onSwitch,
    this.onChange,
  });

  // アイコン
  Icon icon;
  Icon? iconOff;
  // ON/OFF
  bool onSwitch;
  // ON/OFF切り替え処理
  Function(bool)? onChange;

  // 外部からのON/OFF変更イベント
  var _stream = StreamController<bool>();

  // Streamから取得されるメッセージが最新かどうかを判定するためのIDX
  int _streamEventIdx = 0;
  int _lastStreamEventIdx = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _stream.stream,
      builder: (BuildContext context, AsyncSnapshot<bool> snapShot)
      {
        // まだ取り込んでいない、最新のストリームイベントのみを参照する
        if((snapShot.data != null) && (_lastStreamEventIdx < _streamEventIdx)){
          onSwitch = snapShot.data as bool;
        }
        _lastStreamEventIdx = _streamEventIdx;

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
              // ON状態で押されてOFFに遷移するときのコールバック
              onPressed:() {
                onChange?.call(false);
              },
            ),
          );
        }else{
          // OFF状態
          return IconButton(
            icon: iconOff ?? icon,
            // OFF状態で押されてONに遷移するときのコールバック
            onPressed:() {
              onChange?.call(true);
            },
          );
        }
      }
    );
  }

  //--------------------------------------------------------------------------
  // ボタンのON/OFF状態を外部から変更する
  void changeState(bool onSwitch)
  {
    // NOTE: 画面の再構築に伴う OnOffIconButton.build() の呼び出しで、直前の本関数から
    // NOTE: 送った値が、初期値を上書きするのを防止するための、イベント識別IDXをカウントする。
    _streamEventIdx++;
    _stream.sink.add(onSwitch);
  }
}
