import 'dart:async';
import 'dart:io';

import 'package:ZY_Player_flutter/Collect/provider/collect_provider.dart';
import 'package:ZY_Player_flutter/common/common.dart';
import 'package:ZY_Player_flutter/model/detail_reource.dart';
import 'package:ZY_Player_flutter/net/dio_utils.dart';
import 'package:ZY_Player_flutter/net/http_api.dart';
import 'package:ZY_Player_flutter/player/provider/detail_provider.dart';
import 'package:ZY_Player_flutter/player/widget/diy_fijkPanel.dart';
import 'package:ZY_Player_flutter/provider/theme_provider.dart';
import 'package:ZY_Player_flutter/res/colors.dart';
import 'package:ZY_Player_flutter/res/resources.dart';
import 'package:ZY_Player_flutter/util/log_utils.dart';
import 'package:ZY_Player_flutter/util/theme_utils.dart';
import 'package:ZY_Player_flutter/util/toast.dart';
import 'package:ZY_Player_flutter/util/utils.dart';
import 'package:ZY_Player_flutter/utils/provider.dart';
import 'package:ZY_Player_flutter/utils/qs_common.dart';
import 'package:ZY_Player_flutter/widgets/load_image.dart';
import 'package:ZY_Player_flutter/widgets/my_app_bar.dart';
import 'package:ZY_Player_flutter/widgets/my_card.dart';
import 'package:ZY_Player_flutter/widgets/state_layout.dart';
import 'package:fijkplayer/fijkplayer.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_picker/flutter_picker.dart';
import 'package:giffy_dialog/giffy_dialog.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PlayerDetailPage extends StatefulWidget {
  const PlayerDetailPage({
    Key key,
    @required this.url,
    @required this.title,
  }) : super(key: key);

  final String url;
  final String title;

  @override
  _PlayerDetailPageState createState() => _PlayerDetailPageState();
}

class _PlayerDetailPageState extends State<PlayerDetailPage> with WidgetsBindingObserver {
  final FijkPlayer _player = FijkPlayer();

  bool startedPlaying = false;

  DetailProvider _detailProvider = DetailProvider();
  CollectProvider _collectProvider;
  ThemeProvider _themeProvider;
  StreamSubscription _currentPosSubs;

  String actionName = "";
  bool _isFullscreen = false;

  int currentVideoIndex = -1;
  Timer searchTimer;

  String currentUrl = "";
  Picker _picker;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _collectProvider = Store.value<CollectProvider>(context);
    _themeProvider = Store.value<ThemeProvider>(context);
    _collectProvider.setListDetailResource("collcetPlayer");
    _player.addListener(_fijkValueListener);

    initData();
    initDlna();
    super.initState();
  }

  Future _fijkValueListener() async {
    FijkValue value = _player.value;
    _isFullscreen = value.fullScreen;
    // 播放完成 是否从新播放下一集 completed
    Log.d(value.duration.inMilliseconds.toString());
    if (value.state == FijkState.completed) {
      if (_detailProvider.detailReource.videoList.length > 1) {
        currentVideoIndex += 1;
        _themeProvider.setloadingState(true);
        Toast.show("正在解析地址,开始播放下一集");
        await getPlayVideoUrl(_detailProvider.detailReource.videoList[currentVideoIndex].url, currentVideoIndex);
        _detailProvider.saveJuji("${widget.url}_$currentVideoIndex");
        _player.reset().then((value) {
          _player.setDataSource(currentUrl, autoPlay: true);
          Toast.show("开始播放第${currentVideoIndex + 1}集");
          _themeProvider.setloadingState(false);
        });
      } else {
        Toast.show("已播放完成");
      }
    }
  }

  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    _isFullscreen ? SystemChrome.setEnabledSystemUIOverlays([]) : SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('app lifecycle state: $state');
    if (state == AppLifecycleState.inactive) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      _player.start();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    super.dispose();
    _player.removeListener(_fijkValueListener);
    _player.release();
    _currentPosSubs?.cancel();
  }

  Future getPlayVideoUrl(String videoUrl, int index) async {
    await DioUtils.instance.requestNetwork(Method.get, HttpApi.getPlayVideoUrl, queryParameters: {"url": videoUrl}, onSuccess: (data) {
      currentUrl = data;
    }, onError: (_, __) {
      currentVideoIndex = index;
    });
  }

  Future initData() async {
    _detailProvider.setStateType(StateType.loading);
    await DioUtils.instance.requestNetwork(Method.get, HttpApi.detailReource, queryParameters: {"url": widget.url}, onSuccess: (data) {
      _detailProvider.setDetailResource(DetailReource.fromJson(data[0]));
      _detailProvider.setJuji();
      _collectProvider.changeNoti();
      setPlayerVideo();
      if (getFilterData(_detailProvider.detailReource)) {
        _detailProvider.setActionName("点击取消");
      } else {
        _detailProvider.setActionName("点击收藏");
      }
      _detailProvider.setStateType(StateType.empty);
    }, onError: (_, __) {
      _detailProvider.setStateType(StateType.network);
    });
  }

  Future initDlna() async {
    Constant.dlnaManager.init();
    // 5秒后返回搜索结果
    Constant.dlnaManager.setSearchCallback((devices) {
      // 成功之后回调
      _themeProvider.setloadingState(false);
      if (devices != null && devices.length > 0) {
        Constant.dlnaDevices = devices;
      } else {
        searchDialog();
      }
    });
  }

  searchDialog() {
    // 提示是否继续搜索
    showDialog(
        context: context,
        builder: (_) => FlareGiffyDialog(
              flarePath: 'assets/images/space_demo.flr',
              flareAnimation: 'loading',
              title: Text('设备搜索超时', textAlign: TextAlign.center, style: TextStyle(fontSize: 22.0, fontWeight: FontWeight.w600)),
              description: Text(
                '请打开相关设备后点击重新搜索',
                textAlign: TextAlign.center,
              ),
              entryAnimation: EntryAnimation.BOTTOM,
              buttonOkText: Text("重新搜索"),
              buttonCancelText: Text("停止搜索"),
              onOkButtonPressed: () {
                Navigator.pop(context);
                _themeProvider.setloadingState(true, "正在搜索设备");
                Constant.dlnaManager.search();
              },
              onCancelButtonPressed: () {
                Navigator.pop(context);
                Constant.dlnaManager.stop();
              },
            ));
  }

  Future setPlayerVideo() async {
    await _player.applyOptions(FijkOption()
      ..setFormatOption('fflags', 'fastseek')
      ..setHostOption('request-screen-on', 1)
      ..setHostOption('request-audio-focus', 1)
      ..setCodecOption('cover-after-prepared', 1)
      ..setPlayerOption('framedrop', 5)
      ..setPlayerOption('packet-buffering', 1)
      ..setPlayerOption('mediacodec', 1)
      ..setPlayerOption('enable-accurate-seek', 1)
      ..setPlayerOption('reconnect', 5)
      ..setPlayerOption('render-wait-start', 1));
  }

  bool getFilterData(DetailReource data) {
    if (data != null) {
      var result = _collectProvider.listDetailResource.where((element) => element.url == data.url).toList();
      return result.length > 0;
    }
    return false;
  }

  Widget buildShare(String image, String title) {
    GlobalKey haibaoKey = GlobalKey();
    return FlatButton.icon(
        onPressed: () => {
              showElasticDialog<void>(
                context: context,
                builder: (BuildContext context) {
                  const OutlinedBorder buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(0)));
                  return Material(
                    type: MaterialType.transparency,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RepaintBoundary(
                            key: haibaoKey,
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.dialogBackgroundColor,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              width: 270.0,
                              height: ScreenUtil.getInstance().getWidth(400),
                              // padding: const EdgeInsets.only(top: 24.0),
                              child: TextButtonTheme(
                                data: TextButtonThemeData(
                                    style: ButtonStyle(
                                  // 文字颜色
                                  foregroundColor: MaterialStateProperty.all<Color>(Theme.of(context).primaryColor),
                                  // 按下高亮颜色
                                  shadowColor: MaterialStateProperty.all<Color>(Theme.of(context).primaryColor.withOpacity(0.2)),
                                  // 按钮大小
                                  minimumSize: MaterialStateProperty.all<Size>(const Size(double.infinity, double.infinity)),
                                  // 修改默认圆角
                                  shape: MaterialStateProperty.all<OutlinedBorder>(buttonShape),
                                )),
                                child: Column(
                                  children: <Widget>[
                                    LoadImage(
                                      image,
                                      height: ScreenUtil.getInstance().getWidth(250),
                                    ),
                                    Expanded(
                                        child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text("分享 zy_player_flutter"),
                                            Container(
                                              child: Text(
                                                "影片名称:$title",
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: true,
                                              ),
                                              width: ScreenUtil.getInstance().getWidth(120),
                                            ),
                                            Text("点击复制链接"),
                                            Text("或者保存到相册分享")
                                          ],
                                        ),
                                        QrImage(
                                          padding: EdgeInsets.all(ScreenUtil.getInstance().getWidth(7)),
                                          backgroundColor: Colors.white,
                                          data: "www.baidu.com",
                                          size: ScreenUtil.getInstance().getWidth(120),
                                        ),
                                      ],
                                    ))
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                child: const Text('点击复制链接'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: "123121"));
                                  Toast.show("复制链接成功，快去分享吧");
                                },
                              ),
                              TextButton(
                                child: const Text('保存到相册'),
                                onPressed: () async {
                                  ByteData byteData = await QSCommon.capturePngToByteData(haibaoKey);
                                  // 保存
                                  File file = await QSCommon.saveImageToCamera(byteData);
                                  debugPrint('$file');
                                  if (file.path.length > 0) {
                                    Toast.show("保存成功, 快去分享吧");
                                  } else {
                                    Toast.show("保存失败");
                                  }
                                },
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              )
            },
        icon: Icon(Icons.share),
        label: Text("分享"));
  }

  Future pickerDevices() async {
    List<PickerItem<String>> devices = [];
    if (Constant.dlnaDevices.length == 0) {
      devices.add(PickerItem(text: Text("正在搜寻...")));
    } else {
      for (var item in Constant.dlnaDevices) {
        devices.add(PickerItem(text: Text(item["name"]), value: item["id"]));
      }
    }
    List<PickerItem<String>> videos = [];
    for (VideoList item in _detailProvider.detailReource.videoList) {
      videos.add(PickerItem(text: Text("${item.title}"), value: item.url, children: devices));
    }
    PickerDataAdapter<String> _adapter = PickerDataAdapter<String>(data: videos);

    // 显示picker窗口
    _picker = Picker(
        adapter: _adapter,
        title: Text("请选择推送内容"),
        cancelText: "取消",
        confirmText: "确认",
        onConfirm: (Picker picker, List<int> selecteds) {
          List selected = picker.adapter.getSelectedValues();
          String videoUrl = selected[0];
          String deviceUuid = selected[1];
          if (deviceUuid == null || videoUrl == null) {
            return;
          }
          var device;
          for (var item in Constant.dlnaDevices) {
            if (item['id'] == deviceUuid) {
              device = item;
              break;
            }
          }
          String videoTitle;
          for (var item in _detailProvider.detailReource.videoList) {
            if (item.url == videoUrl) {
              videoTitle = item.title;
              break;
            }
          }
          if (device == null || videoTitle == null) {
            return;
          }
          _themeProvider.setloadingState(true);
          Toast.show("正在解析地址");
          getPlayVideoUrl(videoUrl, currentVideoIndex).then((value) async {
            print("推送视频 $videoTitle $currentUrl 到设备：${device['name']}");

            Toast.show("推送视频 $videoTitle 到设备：${device['name']}");
            await Constant.dlnaManager.setDevice(device["id"]);
            await Constant.dlnaManager.setVideoUrlAndName(currentUrl, videoTitle);
            _themeProvider.setloadingState(false);
            _picker.onCancel();
          });
          _picker = null;
        });
    _picker.show(_scaffoldKey.currentState);
  }

  Widget buildTuiSong() {
    return FlatButton.icon(
        onPressed: () async {
          _player.pause();
          _themeProvider.setloadingState(false);
          // 强制重新搜寻设备
          if (Constant.dlnaDevices.length == 0) {
            _themeProvider.setloadingState(true, "正在搜索设备");
            Constant.dlnaManager.search();
          } else {
            await pickerDevices();
          }
        },
        icon: Icon(Icons.present_to_all_sharp),
        label: Text("投屏"));
  }

  Wrap buildJuJi(var provider, var isDark) {
    return Wrap(
      spacing: 20, // 主轴(水平)方向间距
      runSpacing: 10, // 纵轴（垂直）方向间距
      alignment: WrapAlignment.start, //沿主轴方向居中
      children: List.generate(provider.detailReource.videoList.length, (index) {
        return InkWell(
            onTap: () async {
              if (currentVideoIndex == index) return;
              currentVideoIndex = index;
              _themeProvider.setloadingState(true);
              Toast.show("正在解析地址");
              await getPlayVideoUrl(_detailProvider.detailReource.videoList[currentVideoIndex].url, currentVideoIndex);
              _detailProvider.saveJuji("${widget.url}_$currentVideoIndex");
              _player.reset().then((value) {
                _player.setDataSource(currentUrl, autoPlay: true);
                Toast.show("开始播放第${currentVideoIndex + 1}集");
                _themeProvider.setloadingState(false);
              });
            },
            child: Container(
                width: ScreenUtil.getInstance().getWidth(100),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _detailProvider.kanguojuji.contains("${widget.url}_$index") ? Colors.redAccent : Colors.blueAccent,
                    borderRadius: BorderRadius.all(Radius.circular(5))),
                alignment: Alignment.center,
                child: Text(
                  '${_detailProvider.detailReource.videoList[index].title}',
                  style: TextStyle(
                    color: isDark ? Colours.dark_text : Colors.white,
                  ),
                )));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final bool isDark = themeData.brightness == Brightness.dark;

    final bool fill = true;
    final int duration = 4000;
    final bool doubleTap = true;
    final bool snapShot = true;

    return ChangeNotifierProvider<DetailProvider>(
        create: (_) => _detailProvider,
        child: Scaffold(
          key: _scaffoldKey,
          appBar: PreferredSize(
              preferredSize: Size.fromHeight(48.0),
              child: Selector<DetailProvider, String>(
                  builder: (_, actionName, __) {
                    return MyAppBar(
                        centerTitle: widget.title,
                        actionName: actionName,
                        onPressed: () {
                          if (getFilterData(_detailProvider.detailReource)) {
                            Log.d("点击取消");
                            _collectProvider.removeResource(_detailProvider.detailReource.url);
                            _detailProvider.setActionName("点击收藏");
                          } else {
                            Log.d("点击收藏");
                            _collectProvider.addResource(
                              _detailProvider.detailReource,
                            );
                            _detailProvider.setActionName("点击取消");
                          }
                        });
                  },
                  selector: (_, store) => store.actionName)),
          body: Consumer<DetailProvider>(builder: (_, provider, __) {
            return provider.detailReource != null
                ? Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: MediaQuery.of(context).size.width,
                            height: ScreenUtil.getInstance().getWidth(230),
                            child: FijkView(
                              player: _player,
                              color: Colors.black,
                              panelBuilder: (player, data, BuildContext context, Size viewSize, Rect texturePos) {
                                return DiyFijkPanel(
                                  player: player,
                                  onBack: () {
                                    player.exitFullScreen();
                                  },
                                  onError: () {
                                    _player.reset().then((value) {
                                      _player.setDataSource(currentUrl, autoPlay: true);
                                      Toast.show("开始播放第${currentVideoIndex + 1}集");
                                      _themeProvider.setloadingState(false);
                                    });
                                  },
                                  data: data,
                                  viewSize: viewSize,
                                  texPos: texturePos,
                                  fill: fill,
                                  doubleTap: doubleTap,
                                  snapShot: snapShot,
                                  hideDuration: duration,
                                );
                              },
                              fsFit: FijkFit.ar16_9,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                          child: CustomScrollView(
                        slivers: <Widget>[
                          SliverToBoxAdapter(
                            child: MyCard(
                              child: Container(
                                padding: EdgeInsets.all(10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text("剧情介绍"),
                                    Text(
                                      provider.detailReource.content,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 10,
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: provider.detailReource.videoList.length > 0
                                ? MyCard(
                                    child: Container(
                                    padding: EdgeInsets.only(left: 10, right: 10, bottom: 10),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Padding(
                                          padding: EdgeInsets.only(top: 10, bottom: 10),
                                          child: Row(
                                            children: [
                                              Text(
                                                "剧集选择",
                                                style: TextStyle(fontSize: 15),
                                              ),
                                              buildTuiSong(),
                                              buildShare(provider.detailReource.cover, provider.detailReource.title)
                                            ],
                                          ),
                                        ),
                                        buildJuJi(provider, isDark),
                                      ],
                                    ),
                                  ))
                                : Container(),
                          )
                        ],
                      ))
                    ],
                  )
                : StateLayout(
                    type: provider.stateType,
                    onRefresh: initData,
                  );
          }),
        ));
  }
}
