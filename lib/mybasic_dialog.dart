import 'package:flutter/material.dart';

const EdgeInsets _defaultInsetPadding = EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0);

/**
サイズや画面に対する配置を指定できるダイアログ表示

引数:
- context : ビルドコンテキスト
- width : ダイアログの幅
- height : ダイアログの高さ
- alignment : 画面に対するダイアログの配置
- margin : 画面に対する、ダイアログ外側のマージン
- padding : ダイアログ内側のパディング
- barrierDismissible : ダイアログ外をタップした時に閉じるかどうか
- onClose : ダイアログを閉じる時の処理
- builder : ダイアログの中身
*/ 
Future<T?> showMyBasicDialog<T>({
  required BuildContext context,
  double? width,
  double? height,
  AlignmentGeometry? alignment,
  EdgeInsets? margin = _defaultInsetPadding,
  EdgeInsets? padding,
  bool barrierDismissible = true,
  Future<bool> Function()? onClose,
  required Widget Function(BuildContext) builder})
{
  if(onClose != null){
    // ダイアログの終了処理あり
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: onClose,
          child: Dialog(
            alignment: alignment,
            insetPadding: margin,
            child: Container(
              width: width,
              height: height,
              padding: padding,
              child: builder(context),
            ),
          ),
        );
      },
    );
  }else{
    // ダイアログの終了処理なし
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return Dialog(
          alignment: alignment,
          insetPadding: margin,
          child: Container(
            width: width,
            height: height,
            padding: padding,
            child: builder(context),
          ),
        );
      },
    );
  }
}
