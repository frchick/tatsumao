import 'package:flutter/material.dart';

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
    required this.onSwitch,
    this.onChange,
  });

  // アイコン
  Icon icon;
  // ON/OFF
  bool onSwitch;
  // ON/OFF切り替え処理
  Function(bool)? onChange;

  @override
  Widget build(BuildContext context) {
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
          // ON->OFF
          onPressed:() {
            onChange?.call(false);
          },
        ),
      );
    }else{
      // OFF状態
      return IconButton(
        icon: icon,
        // OFF->ON
        onPressed:() {
          onChange?.call(true);
        },
      );
    }
  }
}
