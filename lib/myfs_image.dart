import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 作成済みの Image Widget のキャッシュ
Map<String, Widget> _imageCache = {};


//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// Firebase Storage からの画像取得
// 事前に Firebase Storage を構成して、クロスサイトオリジンを許可すること。
class MyFSImage extends StatefulWidget
{
  const MyFSImage(this.gsPath, { super.key, this.loadingIcon, this.errorIcon });

  final String gsPath;
  final Widget ?loadingIcon;
  final Widget ?errorIcon;

  @override
  State<MyFSImage> createState() => _MyFSImageState();
}

class _MyFSImageState extends State<MyFSImage>
{
  // 画像。読み込みが完了するまでは null。
  Widget ?_iconImage;

  @override
  void initState()
  {
    super.initState();
    getImage(widget.gsPath);
  }

  void getImage(String gsPath) async
  {
    // 読み込み済みキャッシュにあればそれを使う
    if(_imageCache.containsKey(gsPath))
    {
      _iconImage = _imageCache[gsPath];
      return;
    }
  
    try {
      // Firebase Storage のURIスキーム(gs://)からURLを取得し、HTTPリクエストで画像を取得
      // NOTE: ブラウザにキャッシュするために、
      // - Firebase Storate にCORSを設定する必要がある。
      // - Firebase Storage のURLはキャッシュされない。Google Cloud Storage の一般公開URLで参照する。
      // Google Cloud Storage の一般公開URLに変換。
      final fb = DefaultFirebaseOptions.currentPlatform;
      final publicURL = "https://storage.googleapis.com/" + fb.storageBucket! + "/" + gsPath;
      final response = await http.get(Uri.parse(publicURL));

      // HTTPレスポンスを得られたら画像を作成
      setState(() {
        if(response.statusCode == 200)
        {
          final imageBytes = response.bodyBytes;
          _iconImage = Image.memory(imageBytes);
          // キャッシュに登録
          _imageCache[gsPath] = _iconImage!;
        }else{
          // 成功(200)以外ならエラーアイコン
          _iconImage = widget.errorIcon;
          _iconImage ??= const Icon(Icons.error, size:60);
          print("MyFSImage : Error : ${response.statusCode}");
        }
      });
    } catch (e) {
      // 例外が発生したらエラーアイコン
      setState(() {
        _iconImage = widget.errorIcon;
        _iconImage ??= const Icon(Icons.error, size:60);
        print("MyFSImage : Excepthon : $e");
      });
    }
  }

  @override
  Widget build(BuildContext context)
  {
    // 画像が取得できるまでは、適当なアイコンを返す
    Widget? iconImage = _iconImage;
    iconImage ??= widget.loadingIcon;
    iconImage ??= const Icon(Icons.downloading, size:60);
    return iconImage;
  }
}
