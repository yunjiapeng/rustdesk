import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  Timer? _webAuthHeartbeatTimer;
  Timer? _webAuthOnlineTimer;
  HttpServer? _webAuthLoopbackServer;
  Timer? _webAuthLoopbackTimeout;
  String _webAuthToken = '';
  String _webAuthUser = '';
  String _webAuthLocalDeviceId = '';
  List<_WebAuthDevice> _myDevices = [];
  String? _editingDeviceId;
  final TextEditingController _remarkController = TextEditingController();
  static const _webAuthBaseUrl = 'http://202.189.23.82:20101';
  static const _webAuthLoginPath = '/login';
  static const _webAuthRegisterPath = '/devices/register';
  static const _webAuthHeartbeatPath = '/devices/heartbeat';
  static const _webAuthDeviceListPath = '/devices';
  static const _webAuthOnlineStatusPath = '/devices/online-status';
  static const _webAuthLoopbackPort = 27182;
  bool isCardClosed = false;
  int _selectedNavIndex = 0;
  int _deviceCategoryIndex = 0;
  String? _selectedDeviceId;
  bool _showSettings = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      if (_selectedNavIndex != 1 &&
                          !isOutgoingOnly &&
                          !_showSettings)
                        buildLocalAssistSection(context),
                      if (_selectedNavIndex == 1)
                        Expanded(child: buildDevicePane(context))
                      else if (_showSettings)
                        Expanded(
                            child: DesktopSettingPage(
                          initialTabkey: SettingsTabKey.general,
                        ))
                      else if (!isIncomingOnly)
                        Expanded(child: buildRightPane(context)),
                      if (isIncomingOnly)
                        OnlineStatusWidget(
                          onSvcStatusChanged: () {},
                        ).marginOnly(left: 20, right: 20, bottom: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: 198.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: [
                      buildSidebarHeader(context),
                      buildSidebarMenu(context),
                      SizedBox(height: 12),
                    ],
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            Positioned(
              bottom: 10,
              left: 12,
              right: 12,
              child: buildSidebarSettings(context),
            )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  Widget buildDevicePane(BuildContext context) {
    bind.mainLoadRecentPeers();
    final borderColor = Theme.of(context).dividerColor.withOpacity(0.3);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final categories = [
      ('最近控制', Icons.history),
      ('我的设备', Icons.devices_outlined),
      ('公共设备', Icons.public),
    ];
    final showRecent = _deviceCategoryIndex == 0;
    final showMyDevices = _deviceCategoryIndex == 1;
    return Row(
      children: [
        Container(
          width: 96,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(right: BorderSide(color: borderColor)),
          ),
          child: Column(
            children: [
              SizedBox(height: 12),
              ...categories.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final selected = _deviceCategoryIndex == index;
                return InkWell(
                  onTap: () => setState(() {
                    _deviceCategoryIndex = index;
                    _selectedDeviceId = null;
                  }),
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Icon(item.$2,
                            size: 18,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey),
                        SizedBox(height: 6),
                        Text(
                          item.$1,
                          style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : null),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final detailWidth = constraints.maxWidth * 0.4;
            final detailTopPadding = constraints.maxHeight * 0.05;
            final listSection = Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                            showRecent
                                ? '最近控制'
                                : (showMyDevices ? '我的设备' : '设备'),
                            style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(width: 6),
                        Text(
                            '共${showRecent ? gFFI.recentPeersModel.peers.length : (showMyDevices ? _myDevices.length : 0)}条记录',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: gFFI.recentPeersModel,
                      builder: (context, _) {
                        if (showMyDevices) {
                          if (_myDevices.isEmpty) {
                            return Center(
                              child: Text('暂无设备',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey)),
                            );
                          }
                          return ListView.builder(
                            itemCount: _myDevices.length,
                            itemBuilder: (context, index) {
                              final device = _myDevices[index];
                              final selected =
                                  _selectedDeviceId == device.id;
                              return InkWell(
                                onTap: () => setState(
                                    () => _selectedDeviceId = device.id),
                                child: _buildMyDeviceListItem(
                                    context, device, selected, textColor),
                              );
                            },
                          );
                        }
                        final peers = showRecent
                            ? gFFI.recentPeersModel.peers
                            : gFFI.recentPeersModel.peers.take(0).toList();
                        if (peers.isEmpty) {
                          return Center(
                            child: Text('暂无设备',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey)),
                          );
                        }
                        return ListView.builder(
                          itemCount: peers.length,
                          itemBuilder: (context, index) {
                            final peer = peers[index];
                            final selected = _selectedDeviceId == peer.id;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedDeviceId = peer.id),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: peer.online
                                            ? Colors.green
                                            : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: str2color(
                                            '${peer.id}${peer.platform}', 0x66),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                          child: getPlatformImage(
                                              peer.platform,
                                              size: 16)),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            peer.alias.isNotEmpty
                                                ? peer.alias
                                                : (peer.hostname.isNotEmpty
                                                    ? peer.hostname
                                                    : peer.id),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: selected
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : textColor),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            peer.id,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
            if (_selectedDeviceId == null) {
              return listSection;
            }
            return Row(
              children: [
                Expanded(child: listSection),
                Padding(
                  padding: EdgeInsets.only(top: detailTopPadding),
                  child: SizedBox(
                    width: detailWidth,
                    child: AnimatedBuilder(
                      animation: gFFI.recentPeersModel,
                      builder: (context, _) {
                        if (showMyDevices) {
                          final selectedDevice = _myDevices.firstWhereOrNull(
                              (device) => device.id == _selectedDeviceId);
                          if (selectedDevice == null) {
                            return const Offstage();
                          }
                          return _buildMyDeviceDetailPanel(
                              context, selectedDevice);
                        } else {
                          final peers = showRecent
                              ? gFFI.recentPeersModel.peers
                              : gFFI.recentPeersModel.peers.take(0).toList();
                          Peer? selectedPeer;
                          for (final peer in peers) {
                            if (peer.id == _selectedDeviceId) {
                              selectedPeer = peer;
                              break;
                            }
                          }
                          if (selectedPeer == null) {
                            return const Offstage();
                          }
                          return _buildDeviceDetailPanel(context, selectedPeer);
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDeviceDetailPanel(BuildContext context, Peer peer) {
    final subColor =
        Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ??
            Colors.grey;
    final screenshotPath = _deviceScreenshotPath(peer.id);
    final screenshotFile = File(screenshotPath);
    final hasScreenshot = screenshotFile.existsSync();
    final cardBorderColor = subColor.withOpacity(0.25);
    final textOnImage = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(color: Colors.white);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(left: BorderSide(color: subColor.withOpacity(0.3))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              peer.alias.isNotEmpty
                  ? peer.alias
                  : (peer.hostname.isNotEmpty ? peer.hostname : peer.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 6),
            Text(
              peer.id,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: subColor),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: peer.online ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  peer.online ? '在线' : '离线',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: subColor),
                ),
              ],
            ),
            SizedBox(height: 16),
            Opacity(
              opacity: peer.online ? 1 : 0.6,
              child: AbsorbPointer(
                absorbing: !peer.online,
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => connect(context, peer.id),
                      child: Container(
                        height: 126,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorderColor),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: hasScreenshot
                                  ? ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                          sigmaX: 8, sigmaY: 8),
                                      child: Image.file(
                                        screenshotFile,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Container(color: Colors.grey.shade200),
                            ),
                            Positioned.fill(
                              child:
                                  Container(color: Colors.black.withOpacity(0.25)),
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.desktop_windows_outlined,
                                      color: Colors.white, size: 32),
                                  SizedBox(height: 8),
                                  Text('桌面控制', style: textOnImage),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                connect(context, peer.id, isFileTransfer: true),
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cardBorderColor),
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('远程文件',
                                      style:
                                          Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                connect(context, peer.id, isTerminal: true),
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cardBorderColor),
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.terminal_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('终端',
                                      style:
                                          Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDeviceListItem(BuildContext context, _WebAuthDevice device,
      bool selected, Color? textColor) {
    final title = _deviceDisplayName(device);
    final subColor = Theme.of(context).textTheme.bodySmall?.color;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: device.online ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
                child: Icon(Icons.devices_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : textColor),
                ),
                SizedBox(height: 2),
                Text(
                  device.name.isNotEmpty ? device.name : device.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: subColor?.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyDeviceDetailPanel(
      BuildContext context, _WebAuthDevice device) {
    final subColor =
        Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ??
            Colors.grey;
    final connectId =
        device.identifier.isNotEmpty ? device.identifier : device.id;
    final screenshotPath = _deviceScreenshotPath(device.id);
    final screenshotFile = File(screenshotPath);
    final hasScreenshot = screenshotFile.existsSync();
    final cardBorderColor = subColor.withOpacity(0.25);
    final textOnImage = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(color: Colors.white);
    final isEditing = _editingDeviceId == device.id;
    final isLocalDevice = _isLocalDevice(device);
    final title = _deviceDisplayName(device);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(left: BorderSide(color: subColor.withOpacity(0.3))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: isEditing
                      ? TextField(
                          controller: _remarkController,
                          autofocus: true,
                          onSubmitted: (value) =>
                              _saveDeviceRemark(device, value),
                        )
                      : Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                ),
                IconButton(
                  icon: Icon(isEditing ? Icons.check : Icons.edit),
                  onPressed: () {
                    if (isEditing) {
                      _saveDeviceRemark(device, _remarkController.text);
                    } else {
                      _remarkController.text = device.remark.isNotEmpty
                          ? device.remark
                          : device.name;
                      setState(() {
                        _editingDeviceId = device.id;
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: isLocalDevice ? null : () => _deleteDeviceOwner(device),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              device.name.isNotEmpty ? device.name : device.id,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: subColor),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.online ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  device.online ? '在线' : '离线',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: subColor),
                ),
              ],
            ),
            SizedBox(height: 16),
            Opacity(
              opacity: device.online ? 1 : 0.6,
              child: AbsorbPointer(
                absorbing: !device.online,
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        if (isLocalDevice) {
                          _showLocalDeviceConnectTip();
                          return;
                        }
                        connect(context, connectId);
                      },
                      child: Container(
                        height: 126,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorderColor),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: hasScreenshot
                                  ? ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                          sigmaX: 8, sigmaY: 8),
                                      child: Image.file(
                                        screenshotFile,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Container(color: Colors.grey.shade200),
                            ),
                            Positioned.fill(
                              child:
                                  Container(color: Colors.black.withOpacity(0.25)),
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.desktop_windows_outlined,
                                      color: Colors.white, size: 32),
                                  SizedBox(height: 8),
                                  Text('桌面控制', style: textOnImage),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (isLocalDevice) {
                                _showLocalDeviceConnectTip();
                                return;
                              }
                              connect(context, connectId,
                                  isFileTransfer: true);
                            },
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cardBorderColor),
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('远程文件',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (isLocalDevice) {
                                _showLocalDeviceConnectTip();
                                return;
                              }
                              connect(context, connectId, isTerminal: true);
                            },
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cardBorderColor),
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.terminal_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('终端',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardBorderColor),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('OS名称', device.osName),
                  SizedBox(height: 6),
                  _buildInfoRow('上次登录时间', device.lastLoginTime),
                  SizedBox(height: 6),
                  _buildInfoRow('上次登录IP', device.lastLoginIp),
                  SizedBox(height: 6),
                  _buildInfoRow('最后在线时间', device.lastOnlineTime),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final textColor = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: textColor?.withOpacity(0.7))),
        ),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Uri _webAuthUri(String path) {
    return Uri.parse('$_webAuthBaseUrl$path');
  }

  Map<String, String> _webAuthHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_webAuthToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_webAuthToken';
    }
    return headers;
  }

  Map<String, String> _webAuthNoAuthHeaders() {
    return const {'Content-Type': 'application/json'};
  }

  void _applyWebAuthToken(String token) {
    if (token == _webAuthToken) {
      return;
    }
    if (mounted) {
      setState(() {
        _webAuthToken = token;
      });
    } else {
      _webAuthToken = token;
    }
    if (_webAuthToken.isNotEmpty) {
      _startWebAuthHeartbeat();
      _refreshMyDevices();
      _startWebAuthOnlineCheck();
    } else {
      _webAuthHeartbeatTimer?.cancel();
      _webAuthOnlineTimer?.cancel();
    }
  }

  void _applyWebAuthUser(String user) {
    if (user == _webAuthUser) {
      return;
    }
    if (mounted) {
      setState(() {
        _webAuthUser = user;
      });
    } else {
      _webAuthUser = user;
    }
    if (_webAuthUser.isNotEmpty && _webAuthToken.isNotEmpty) {
      _refreshMyDevices();
      _startWebAuthOnlineCheck();
    }
  }

  void _refreshWebAuthToken() {
    final token = bind.mainGetLocalOption(key: 'webauth_token');
    _applyWebAuthToken(token);
  }

  void _refreshWebAuthUser() {
    final user = bind.mainGetLocalOption(key: 'webauth_user');
    _applyWebAuthUser(user);
  }

  void _initWebAuth() {
    _refreshWebAuthToken();
    _refreshWebAuthUser();
    _registerWebAuthDevice();
    _startWebAuthHeartbeat();
    _startWebAuthOnlineCheck();
    _refreshMyDevices();
  }

  Future<void> _registerWebAuthDevice() async {
    final deviceId = await bind.mainGetMyId();
    _webAuthLocalDeviceId = deviceId;
    Map<String, dynamic> deviceInfo = {};
    try {
      deviceInfo = jsonDecode(bind.mainGetLoginDeviceInfo());
    } catch (_) {}
    final deviceName =
        (deviceInfo['name'] ?? deviceInfo['device_name'] ?? deviceId).toString();
    final osName = (deviceInfo['os'] ?? deviceInfo['platform'] ?? '').toString();
    final payload = {
      'name': deviceName,
      'identifier': deviceId,
      'os': osName,
    };
    try {
      await http.post(
        _webAuthUri(_webAuthRegisterPath),
        headers: _webAuthNoAuthHeaders(),
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  void _startWebAuthHeartbeat() {
    _webAuthHeartbeatTimer?.cancel();
    _webAuthHeartbeatTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _sendWebAuthHeartbeat());
    _sendWebAuthHeartbeat();
  }

  Future<void> _sendWebAuthHeartbeat() async {
    if (_webAuthLocalDeviceId.isEmpty) {
      _webAuthLocalDeviceId = await bind.mainGetMyId();
    }
    final payload = {'identifier': _webAuthLocalDeviceId};
    try {
      await http.post(
        _webAuthUri(_webAuthHeartbeatPath),
        headers: _webAuthNoAuthHeaders(),
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  Future<void> _reportWebAuthLogin() async {
    if (_webAuthLocalDeviceId.isEmpty) {
      _webAuthLocalDeviceId = await bind.mainGetMyId();
    }
    final payload = {'identifier': _webAuthLocalDeviceId};
    try {
      await http.put(
        _webAuthUri(_webAuthLoginPath),
        headers: _webAuthNoAuthHeaders(),
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  void _startWebAuthOnlineCheck() {
    _webAuthOnlineTimer?.cancel();
    _webAuthOnlineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refreshWebAuthOnlineStatus());
    _refreshWebAuthOnlineStatus();
  }

  Future<void> _refreshMyDevices() async {
    if (_webAuthToken.isEmpty) {
      return;
    }
    try {
      final response = await http.get(
        _webAuthUri(_webAuthDeviceListPath),
        headers: _webAuthHeaders(),
      );
      final data = jsonDecode(response.body);
      final list = data is List ? data : (data['data'] ?? data['list']);
      if (list is List) {
        final devices = list
            .whereType<Map<String, dynamic>>()
            .map(_WebAuthDevice.fromJson)
            .toList();
        _applyLocalDeviceFirst(devices);
        if (mounted) {
          setState(() {
            _myDevices = devices;
          });
        } else {
          _myDevices = devices;
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshWebAuthOnlineStatus() async {
    if (_webAuthToken.isEmpty || _myDevices.isEmpty) {
      return;
    }
    final identifiers = _myDevices
        .map((e) => e.identifier.isNotEmpty ? e.identifier : e.id)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (identifiers.isEmpty) {
      return;
    }
    final payload = <String, dynamic>{'identifiers': identifiers};
    try {
      final response = await http.post(
        _webAuthUri(_webAuthOnlineStatusPath),
        headers: _webAuthNoAuthHeaders(),
        body: jsonEncode(payload),
      );
      final data = jsonDecode(response.body);
      final statuses = data is Map ? data['statuses'] : null;
      if (statuses is List) {
        final statusMap = <String, Map<String, dynamic>>{};
        for (final item in statuses) {
          if (item is Map) {
            final identifier = item['identifier']?.toString() ?? '';
            if (identifier.isNotEmpty) {
              statusMap[identifier] = Map<String, dynamic>.from(item);
            }
          }
        }
        for (final device in _myDevices) {
          final identifier =
              device.identifier.isNotEmpty ? device.identifier : device.id;
          final status = statusMap[identifier];
          if (status == null) {
            continue;
          }
          final active = status['active'];
          if (active is num) {
            device.online = active == 1;
          } else if (active is bool) {
            device.online = active;
          } else if (active is String) {
            device.online = active == '1' || active.toLowerCase() == 'true';
          }
          final lastHeartbeat = status['last_heartbeat_time']?.toString() ?? '';
          final lastOnline = status['last_online_time']?.toString() ?? '';
          if (lastHeartbeat.isNotEmpty) {
            device.lastHeartbeatTime = lastHeartbeat;
          }
          if (lastOnline.isNotEmpty) {
            device.lastOnlineTime = lastOnline;
          }
        }
        if (mounted) {
          setState(() {});
        }
      }
    } catch (_) {}
  }

  void _applyLocalDeviceFirst(List<_WebAuthDevice> devices) {
    if (_webAuthLocalDeviceId.isEmpty) {
      return;
    }
    final index =
        devices.indexWhere((d) => (d.identifier.isNotEmpty ? d.identifier : d.id) == _webAuthLocalDeviceId);
    if (index > 0) {
      final device = devices.removeAt(index);
      devices.insert(0, device);
    }
  }

  bool _isLocalDevice(_WebAuthDevice device) {
    if (_webAuthLocalDeviceId.isEmpty) {
      return false;
    }
    final id = device.identifier.isNotEmpty ? device.identifier : device.id;
    return id == _webAuthLocalDeviceId;
  }

  String _deviceDisplayName(_WebAuthDevice device) {
    final base = device.displayName;
    return _isLocalDevice(device) ? '$base(本机)' : base;
  }

  void _showLocalDeviceConnectTip() {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('提示'),
        content: Text('本机不允许连接本机设备'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showLocalDeviceDeleteTip() {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('提示'),
        content: Text('本机设备不可删除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDeviceOwner(_WebAuthDevice device) async {
    if (_isLocalDevice(device)) {
      _showLocalDeviceDeleteTip();
      return;
    }
    if (_webAuthToken.isEmpty) {
      return;
    }
    try {
      final response = await http.delete(
        _webAuthUri('/devices/${device.id}/owner'),
        headers: _webAuthHeaders(),
      );
      bool ok = false;
      if (response.body.isNotEmpty) {
        final data = jsonDecode(response.body);
        if (data is Map && data['ok'] == true) {
          ok = true;
        }
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        ok = true;
      }
      if (ok) {
        if (mounted) {
          setState(() {
            _myDevices.removeWhere((d) => d.id == device.id);
            if (_selectedDeviceId == device.id) {
              _selectedDeviceId = null;
            }
            if (_editingDeviceId == device.id) {
              _editingDeviceId = null;
            }
          });
        } else {
          _myDevices.removeWhere((d) => d.id == device.id);
          if (_selectedDeviceId == device.id) {
            _selectedDeviceId = null;
          }
          if (_editingDeviceId == device.id) {
            _editingDeviceId = null;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _updateDeviceRemark(_WebAuthDevice device, String remark) async {
    if (_webAuthToken.isEmpty) {
      return;
    }
    final payload = {'remark': remark.isEmpty ? null : remark};
    try {
      final response = await http.put(
        _webAuthUri('/devices/${device.id}/remark'),
        headers: _webAuthHeaders(),
        body: jsonEncode(payload),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        device.remark = remark;
      }
    } catch (_) {}
  }

  void _saveDeviceRemark(_WebAuthDevice device, String value) {
    final remark = value.trim();
    _updateDeviceRemark(device, remark).then((_) {
      if (mounted) {
        setState(() {
          _editingDeviceId = null;
        });
      } else {
        _editingDeviceId = null;
      }
    });
  }

  Future<void> _startWebAuthLogin() async {
    final url = bind.mainGetLocalOption(key: 'webauth_login_url');
    final target = url.isNotEmpty ? url : _webAuthBaseUrl;
    final loginUrl = await _prepareWebAuthLoginUrl(target);
    await launchUrl(Uri.parse(loginUrl));
  }

  Future<String> _prepareWebAuthLoginUrl(String url) async {
    final redirectUri = await _startWebAuthLoopbackServer();
    if (redirectUri == null) {
      return url;
    }
    if (url.contains('{redirect_uri}')) {
      return url.replaceAll(
          '{redirect_uri}', Uri.encodeComponent(redirectUri));
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) {
      return url;
    }
    if (parsed.queryParameters.containsKey('redirect_uri')) {
      return url;
    }
    final params = Map<String, String>.from(parsed.queryParameters);
    params['redirect_uri'] = redirectUri;
    return parsed.replace(queryParameters: params).toString();
  }

  Future<String?> _startWebAuthLoopbackServer() async {
    if (!isDesktop) {
      return null;
    }
    if (_webAuthLoopbackServer != null) {
      final port = _webAuthLoopbackServer?.port ?? _webAuthLoopbackPort;
      return 'http://127.0.0.1:$port/login';
    }
    await _stopWebAuthLoopbackServer();
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _webAuthLoopbackPort,
      );
      _webAuthLoopbackServer = server;
      _webAuthLoopbackTimeout?.cancel();
      _webAuthLoopbackTimeout =
          Timer(const Duration(minutes: 3), _stopWebAuthLoopbackServer);
      server.listen(_handleWebAuthLoopbackRequest);
      return 'http://127.0.0.1:${server.port}/login';
    } catch (_) {
      return null;
    }
  }

  void _handleWebAuthLoopbackRequest(HttpRequest request) async {
    final params = request.uri.queryParameters;
    final token = params['token'] ?? params['access_token'] ?? '';
    final userName = params['user'] ?? params['username'] ?? '';
    final loginUrl = params['login_url'] ?? params['url'] ?? '';
    if (token.isNotEmpty) {
      bind.mainSetLocalOption(key: 'webauth_token', value: token);
      _refreshWebAuthToken();
    }
    if (userName.isNotEmpty) {
      bind.mainSetLocalOption(key: 'webauth_user', value: userName);
      _refreshWebAuthUser();
    }
    if (loginUrl.isNotEmpty) {
      bind.mainSetLocalOption(key: 'webauth_login_url', value: loginUrl);
    }
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write('<html><body>登录成功，请关闭窗口</body></html>');
    await request.response.close();
    if (token.isNotEmpty) {
      await _registerWebAuthDevice();
      await _reportWebAuthLogin();
      windowOnTop(null);
      await _stopWebAuthLoopbackServer();
    }
  }

  Future<void> _stopWebAuthLoopbackServer() async {
    _webAuthLoopbackTimeout?.cancel();
    _webAuthLoopbackTimeout = null;
    final server = _webAuthLoopbackServer;
    _webAuthLoopbackServer = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  String _deviceScreenshotPath(String peerId) {
    final safeId = peerId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final normalized = safeId.isEmpty ? 'peer' : safeId;
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}$normalized.png';
  }

  Widget buildSidebarHeader(BuildContext context) {
    final isLoggedIn = _webAuthToken.isNotEmpty;
    final displayName = _webAuthUser.isNotEmpty
        ? _webAuthUser
        : (isLoggedIn ? '已登录' : '未登录');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(Icons.person_outline, color: Colors.white, size: 18),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (isLoggedIn)
                  InkWell(
                    onTap: _logoutWebAuth,
                    child: Text(
                      '点我退出登录',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  InkWell(
                    onTap: _startWebAuthLogin,
                    child: Text(
                      '点击登录',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _logoutWebAuth() {
    bind.mainSetLocalOption(key: 'webauth_token', value: '');
    bind.mainSetLocalOption(key: 'webauth_user', value: '');
    _webAuthHeartbeatTimer?.cancel();
    _webAuthOnlineTimer?.cancel();
    if (mounted) {
      setState(() {
        _webAuthToken = '';
        _webAuthUser = '';
        _myDevices = [];
      });
    } else {
      _webAuthToken = '';
      _webAuthUser = '';
      _myDevices = [];
    }
  }

  Widget buildSidebarMenu(BuildContext context) {
    final items = [
      ('远程协助', Icons.desktop_windows_outlined),
      ('设备', Icons.devices_outlined),
    ];
    return Column(
      children: [
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final selected = _selectedNavIndex == index;
          return InkWell(
            onTap: () => setState(() {
              _selectedNavIndex = index;
              _showSettings = false;
            }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(item.$2,
                      size: 18,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.$1,
                      style: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget buildSidebarSettings(BuildContext context) {
        final selected = _showSettings;
        final primaryColor = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () {
        setState(() {
          _showSettings = true;
          _selectedNavIndex = -1;
        });
      },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  selected ? primaryColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  size: 18,
                  color: selected ? primaryColor : Colors.grey,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '设置',
                    style: TextStyle(color: selected ? primaryColor : null),
                  ),
                ),
              ],
            ),
          ),
    );
  }


  Widget buildLocalAssistSection(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, child) {
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        final idText = model.serverId.text;
        return Container(
          padding: const EdgeInsets.fromLTRB(34, 13, 20, 0),
          child: LayoutBuilder(builder: (context, constraints) {
            final leftPad = 12.0;
            final rightShift = constraints.maxWidth * 0.1;
            final topShift = constraints.hasBoundedHeight
                ? constraints.maxHeight * 0.2
                : 55.0;
            final titleStyle = Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 21);
            final labelStyle = Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey, fontSize: 14);
            final valueStyle = const TextStyle(fontSize: 36);
            final isLoggedIn = _webAuthToken.isNotEmpty;
            return Padding(
              padding: EdgeInsets.only(left: rightShift),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: topShift),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: leftPad),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('远程协助本机', style: titleStyle),
                          SizedBox(width: 6),
                          Obx(() {
                            final stopped = svcStopped.value;
                            final canToggle = isLoggedIn;
                            return Switch(
                              value: canToggle ? !stopped : false,
                              onChanged: canToggle
                                  ? (value) async {
                                      await start_service(value);
                                    }
                                  : null,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: leftPad, right: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('本机识别码', style: labelStyle),
                                  SizedBox(width: 4),
                                  IconButton(
                                    onPressed: () {
                                      if (idText.isNotEmpty) {
                                        Clipboard.setData(
                                            ClipboardData(text: idText));
                                        showToast(translate("Copied"));
                                      }
                                    },
                                    icon: Icon(Icons.copy_outlined, size: 16),
                                    splashRadius: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 20, minHeight: 20),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      model.serverId.text,
                                      style: valueStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('验证码', style: labelStyle),
                                  SizedBox(width: 4),
                                  buildVerificationMethodMenu(context, model),
                                  SizedBox(width: 4),
                                  if (showOneTime)
                                    AnimatedRotationWidget(
                                      onPressed: () =>
                                          bind.mainUpdateTemporaryPassword(),
                                      child: Icon(Icons.refresh,
                                          size: 16, color: Colors.grey),
                                    ),
                                ],
                              ),
                              SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      model.serverPasswd.text,
                                      style: valueStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      }),
    );
  }

  Widget buildVerificationMethodMenu(BuildContext context, ServerModel model) {
    final keys = [
      kUseTemporaryPassword,
      kUsePermanentPassword,
      kUseBothPasswords
    ];
    final values = [
      translate('Use one-time password'),
      translate('Use permanent password'),
      translate('Use both passwords'),
    ];
    final currentValue = values[keys.indexOf(model.verificationMethod)];
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == kUsePermanentPassword &&
            (await bind.mainGetPermanentPassword()).isEmpty) {
          setPasswordDialog(notEmptyCallback: () async {
            await model.setVerificationMethod(value);
            await model.updatePasswordModel();
          });
        } else {
          await model.setVerificationMethod(value);
          await model.updatePasswordModel();
        }
      },
      itemBuilder: (context) => [
        for (var i = 0; i < keys.length; i++)
          PopupMenuItem(value: keys[i], child: Text(values[i]))
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(currentValue, style: TextStyle(fontSize: 12)),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 16),
        ],
      ),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('YunDesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://YunDesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/YunDesk/YunDesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await RustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await RustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://YunDesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://YunDesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://YunDesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      _refreshWebAuthToken();
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (_webAuthToken.isEmpty && !svcStopped.value) {
        svcStopped.value = true;
        await start_service(false);
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // RustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    _initWebAuth();
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    RustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    RustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await RustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await RustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await RustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await RustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await RustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    _webAuthHeartbeatTimer?.cancel();
    _webAuthOnlineTimer?.cancel();
    _stopWebAuthLoopbackServer();
    _remarkController.dispose();
    _leftPaneScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

class _WebAuthDevice {
  _WebAuthDevice({
    required this.id,
    required this.name,
    required this.identifier,
    required this.remark,
    required this.osName,
    required this.lastLoginTime,
    required this.lastLoginIp,
    required this.lastHeartbeatTime,
    required this.lastOnlineTime,
    this.online = false,
  });

  final String id;
  final String name;
  final String identifier;
  String remark;
  final String osName;
  final String lastLoginTime;
  final String lastLoginIp;
  String lastHeartbeatTime;
  String lastOnlineTime;
  bool online;

  String get displayName {
    if (remark.isNotEmpty) {
      return remark;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return id;
  }

  static _WebAuthDevice fromJson(Map<String, dynamic> json) {
    return _WebAuthDevice(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? json['device_name'] ?? json['deviceName'] ?? '')
          .toString(),
      identifier: (json['identifier'] ?? json['device_id'] ?? '').toString(),
      remark: (json['remark'] ?? json['note'] ?? json['alias'] ?? '').toString(),
      osName:
          (json['os'] ?? json['osName'] ?? json['platform'] ?? '').toString(),
      lastLoginTime: (json['last_login_time'] ?? json['lastLoginTime'] ?? '')
          .toString(),
      lastLoginIp: (json['last_login_ip'] ?? json['lastLoginIp'] ?? '')
          .toString(),
      lastHeartbeatTime:
          (json['last_heartbeat_time'] ?? json['lastHeartbeatTime'] ?? '')
              .toString(),
      lastOnlineTime:
          (json['last_online_time'] ?? json['lastOnlineTime'] ?? '')
              .toString(),
      online: json['active'] == 1 ||
          json['active'] == true ||
          json['active'] == '1' ||
          json['active'] == 'true',
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();

  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      bind.mainSetPermanentPassword(password: pass);
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginSymmetric(vertical: 8),
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(
              height: 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
