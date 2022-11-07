import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:html'; // Web Local Storage
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'text_ballon_widget.dart';
import 'text_edit_dialog.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
// パスワードチェック
Future askAndCheckPassword(BuildContext context) async
{
  const String passwordHash = "6992f4030e10ae944ed6a5691daa19ae";

/* パスワードから MD5 生成するツールコード
  var bytes = utf8.encode(password);
  var digest = md5.convert(bytes);
  print("MD5: ${digest}");
*/

  // 正しいパスワードがキャッシュされてたらOK
  final Storage _localStorage = window.localStorage;
  String? cacheWord = _localStorage["key"];
  if((cacheWord ?? "") == passwordHash) return;

  // 正しいパスワードが入力されるまで聞き続ける
  // (正しいパスワードが入力されるまで、この関数から戻らない)
  while(true){
    String? inputWord = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return TextEditDialog(
          titleText:"パスワード");
      },
    );
    // MD5 に変換して比較およびキャッシュ
    var bytes = utf8.encode(inputWord ?? "");
    var digest = md5.convert(bytes);
    var hash = digest.toString();
    if(hash == passwordHash) break;

    showTextBallonMessage("ハズレ...");
    await new Future.delayed(new Duration(seconds: 2));
  }
  
  // パスワードをキャッシュ
  _localStorage["key"] = passwordHash;
}
