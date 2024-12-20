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

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ON/OFFアイコンボタン
// NOTE: ON/OFFの状態があるので StatefulWidget の気がするが、
// NOTE: ON/OFF変更時に毎回、親から状態を指定されて再構築されるので、結局 StatelessWidget でよい。
class OnOffIconButton2 extends StatefulWidget
{
  const OnOffIconButton2({
    super.key,
    required this.icon,
    required this.size,
    this.backgroundColor,
    this.offIcon,
    this.offBackgroundColor,
    this.isOn = false,
    this.onChange,
  });

  // アイコン
  final Icon icon;
  final Icon? offIcon;
  final double size;
  // 背景色
  final Color? backgroundColor;
  final Color? offBackgroundColor;
  // ON/OFF
  final bool isOn;
  // ON/OFF切り替え処理
  final Function(bool, OnOffIconButton2State)? onChange;

  @override
  OnOffIconButton2State createState() => OnOffIconButton2State();
}

class OnOffIconButton2State extends State<OnOffIconButton2> {

  bool _isOn = false;

  // 外部からのON/OFF変更イベント
  var _stream = StreamController<void>();

  @override
  void initState() {
    super.initState();
    _isOn = widget.isOn;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _stream.stream,
      builder: (BuildContext context, AsyncSnapshot<void> snapShot) {
        return TextButton(
          child: _isOn ? widget.icon : (widget.offIcon ?? widget.icon),
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange.shade900,
            backgroundColor: _isOn ? widget.backgroundColor: widget.offBackgroundColor,
            fixedSize: Size(widget.size, widget.size),
            padding: const EdgeInsets.all(0),
            shape: const CircleBorder(),
          ),
          onPressed: () {
            // 自分自身を再描画
            setState(() {
              _isOn = !_isOn;
              if(widget.onChange != null){
                _isOn = widget.onChange?.call(_isOn, this);
              }
            });
          },
        );
      }
    );
  }

  //--------------------------------------------------------------------------
  // ボタンのON/OFF状態を外部から変更する
  void changeState(bool isOn)
  {
    _isOn = isOn;
    _stream.sink.add(null);
  }
}