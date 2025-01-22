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
Future<bool> askAndCheckPassword(
  BuildContext context, String titleText, String passwordHash, String key) async
{
/* パスワードから MD5 生成するツールコード
  var bytes = utf8.encode(password);
  var digest = md5.convert(bytes);
  print("MD5: ${digest}");
*/

  // 正しいパスワードがキャッシュされてたらOK
  final Storage _localStorage = window.localStorage;
  String? cacheWord = _localStorage[key];
  if((cacheWord ?? "") == passwordHash) return true;

  // パスワード聞いてチェック
  String? inputWord = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditDialog(
        titleText: titleText,
        cancelText: null);
    },
  );
  // MD5 に変換して比較およびキャッシュ
  var bytes = utf8.encode(inputWord ?? "");
  var digest = md5.convert(bytes);
  var hash = digest.toString();
  final bool res = (hash == passwordHash);

  // 正解してたらパスワードをキャッシュ
  if(res){
    _localStorage[key] = passwordHash;
  }

  return res;
}

//----------------------------------------------------------------------------
// 編集ロックパスワードの入力
Future<bool> askEditingLockPassword(BuildContext context, String title) async
{
  bool authenOk = await askAndCheckPassword(context,
    title, lockEditingPasswordHash, lockEditingPasswordKey);
  // ハズレ
  if(!authenOk){
    showTextBallonMessage("ハズレ...");
  }
  return authenOk;
}
