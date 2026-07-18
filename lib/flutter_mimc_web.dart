import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_mimc_platform_interface.dart';
import 'src/mimc_exception.dart';
import 'src/model/mimc_capability.dart';
import 'src/model/mimc_config.dart';
import 'src/model/mimc_connection_state.dart';
import 'src/model/mimc_event.dart';
import 'src/model/mimc_message.dart';
import 'src/model/mimc_rts.dart';
import 'src/model/mimc_server_ack.dart';

final class FlutterMimcWeb extends FlutterMimcPlatform {
  FlutterMimcWeb();

  static void registerWith(Registrar registrar) {
    FlutterMimcPlatform.instance = FlutterMimcWeb();
  }

  static Future<void>? _sdkLoader;

  final StreamController<MimcEvent> _events =
      StreamController<MimcEvent>.broadcast();
  final Map<int, Completer<int>> _createCompleters = <int, Completer<int>>{};
  final Map<int, Completer<void>> _joinCompleters = <int, Completer<void>>{};
  final Map<int, Completer<void>> _quitCompleters = <int, Completer<void>>{};
  final Map<int, Completer<void>> _dismissCompleters = <int, Completer<void>>{};

  _MimcJsUser? _user;
  JSAny? _tokenObject;
  bool _online = false;
  int _nextRequestId = 1;

  @override
  Stream<MimcEvent> get events => _events.stream;

  @override
  Future<Set<MimcCapability>> getCapabilities() async => <MimcCapability>{
        MimcCapability.message,
        MimcCapability.groupMessage,
        MimcCapability.unlimitedGroup,
        MimcCapability.offlinePull,
      };

  @override
  Future<void> initialize({
    required MimcConfig config,
    required String token,
  }) async {
    await (_sdkLoader ??= _loadSdk());
    final JSAny? decodedToken = _decodeToken(token);
    await dispose();
    _tokenObject = decodedToken;

    final _MimcJsUser user = _MimcJsUser(
      config.appIdString,
      config.appAccount,
      config.resource ?? '',
    );
    _user = user;

    user.registerFetchToken((() => _tokenObject).toJS);
    user.registerStatusChange((
      JSBoolean result,
      JSString? errorType,
      JSString? errorReason,
      JSString? errorDescription,
    ) {
      _online = result.toDart;
      _events.add(
        MimcConnectionChanged(
          state: _online
              ? MimcConnectionState.online
              : MimcConnectionState.offline,
          reason: errorReason?.toDart,
          description: errorDescription?.toDart ?? errorType?.toDart,
        ),
      );
      final String errorText = <String>[
        errorType?.toDart ?? '',
        errorReason?.toDart ?? '',
        errorDescription?.toDart ?? '',
      ].join(' ').toLowerCase();
      if (errorText.contains('token')) {
        _events.add(const MimcTokenRefreshRequired());
      }
    }.toJS);
    user.registerDisconnHandler((() {
      _online = false;
      _events.add(
        const MimcConnectionChanged(state: MimcConnectionState.offline),
      );
    }).toJS);
    user.registerP2PMsgHandler(((_MimcJsDirectMessage message) {
      _events.add(MimcMessageReceived(_directMessageFromJs(message)));
    }).toJS);
    user.registerGroupMsgHandler(((_MimcJsGroupMessage message) {
      _events.add(
        MimcMessageReceived(
          _groupMessageFromJs(message, MimcMessageChannel.group),
        ),
      );
    }).toJS);
    user.registerServerAckHandler((
      JSAny? packetId,
      JSAny? sequence,
      JSAny? timestamp,
      JSAny? error,
    ) {
      _events.add(
        MimcServerAckReceived(
          MimcServerAck(
            packetId: _jsString(packetId),
            sequence: _jsInt(sequence),
            timestamp: _jsInt(timestamp),
            description: _jsString(error),
          ),
        ),
      );
    }.toJS);
    user.registerUCMsgHandler(((_MimcJsGroupMessage message) {
      _events.add(
        MimcMessageReceived(
          _groupMessageFromJs(message, MimcMessageChannel.unlimitedGroup),
        ),
      );
    }).toJS);
    user.registerUCDismissHandler(((JSAny? topicId) {
      _events.add(
        MimcUnlimitedGroupDismissed(topicId: _jsInt(topicId) ?? 0),
      );
    }).toJS);
    user.registerPullNotificationHandler(
        ((JSAny? minSequence, JSAny? maxSequence) {
      _events.add(
        MimcOfflinePullNotification(
          minSequence: _jsInt(minSequence),
          maxSequence: _jsInt(maxSequence),
        ),
      );
      return true.toJS;
    }).toJS);
    user.registerUCJoinRespHandler((
      JSAny? topicId,
      JSAny? code,
      JSAny? message,
      JSAny? context,
    ) {
      final int id = _jsInt(topicId) ?? 0;
      final Completer<void>? completer = _joinCompleters.remove(id);
      if ((_jsInt(code) ?? -1) == 0) {
        completer?.complete();
      } else {
        completer?.completeError(
          MimcException('web_uc_join', _jsString(message)),
        );
      }
    }.toJS);
    user.registerUCQuitRespHandler((
      JSAny? topicId,
      JSAny? code,
      JSAny? message,
      JSAny? context,
    ) {
      final int id = _jsInt(topicId) ?? 0;
      final Completer<void>? completer = _quitCompleters.remove(id);
      if ((_jsInt(code) ?? -1) == 0) {
        completer?.complete();
      } else {
        completer?.completeError(
          MimcException('web_uc_quit', _jsString(message)),
        );
      }
    }.toJS);
  }

  @override
  Future<void> updateToken(String token) async {
    _tokenObject = _decodeToken(token);
  }

  @override
  Future<void> login() async {
    _requireUser().login();
  }

  @override
  Future<void> logout() async {
    _requireUser().logout();
    _online = false;
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      _requireUser().sendMessage(
        toAccount,
        _payloadToJsString(payload),
        bizType,
        store,
      );

  @override
  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      _requireUser().sendGroupMessage(
        topicId.toDouble(),
        _payloadToJsString(payload),
        bizType,
        store,
      );

  @override
  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  }) =>
      throw const MimcException(
        'unsupported',
        'The WebJS SDK does not expose online messages',
      );

  @override
  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      _requireUser().sendUnlimitedGroupMessage(
        topicId.toDouble(),
        _payloadToJsString(payload),
        bizType,
        store,
      );

  @override
  Future<int> createUnlimitedGroup(String topicName) {
    final _MimcJsUser user = _requireUser();
    final int requestId = _nextRequestId++;
    final Completer<int> completer = Completer<int>();
    _createCompleters[requestId] = completer;
    try {
      user.createUnlimitedGroup(
        topicName,
        ((
          JSAny? topicId,
          JSAny? returnedName,
          JSBoolean success,
          JSAny? error,
          JSAny? context,
        ) {
          final Completer<int>? pending = _createCompleters.remove(requestId);
          if (pending == null) return;
          if (success.toDart) {
            pending.complete(_jsInt(topicId) ?? 0);
          } else {
            pending.completeError(
              MimcException('web_uc_create', _jsString(error)),
            );
          }
        }).toJS,
        requestId.toString(),
      );
    } catch (_) {
      _createCompleters.remove(requestId);
      rethrow;
    }
    return completer.future;
  }

  @override
  Future<void> joinUnlimitedGroup(int topicId) {
    final _MimcJsUser user = _requireUser();
    if (_joinCompleters.containsKey(topicId) ||
        _quitCompleters.containsKey(topicId)) {
      return Future<void>.error(
        MimcException(
          'web_uc_topic_pending',
          'Another join or quit request is pending for topic $topicId',
        ),
      );
    }
    final Completer<void> completer = Completer<void>();
    _joinCompleters[topicId] = completer;
    try {
      user.joinUnlimitedGroup(topicId.toDouble(), topicId.toString());
    } catch (_) {
      _joinCompleters.remove(topicId);
      rethrow;
    }
    return completer.future;
  }

  @override
  Future<void> quitUnlimitedGroup(int topicId) {
    final _MimcJsUser user = _requireUser();
    if (_joinCompleters.containsKey(topicId) ||
        _quitCompleters.containsKey(topicId)) {
      return Future<void>.error(
        MimcException(
          'web_uc_topic_pending',
          'Another join or quit request is pending for topic $topicId',
        ),
      );
    }
    final Completer<void> completer = Completer<void>();
    _quitCompleters[topicId] = completer;
    try {
      user.quitUnlimitedGroup(topicId.toDouble(), topicId.toString());
    } catch (_) {
      _quitCompleters.remove(topicId);
      rethrow;
    }
    return completer.future;
  }

  @override
  Future<void> dismissUnlimitedGroup(int topicId) {
    final _MimcJsUser user = _requireUser();
    final int requestId = _nextRequestId++;
    final Completer<void> completer = Completer<void>();
    _dismissCompleters[requestId] = completer;
    try {
      user.dismissUnlimitedGroup(
        topicId.toDouble(),
        ((JSBoolean success, JSAny? returnedTopicId, JSAny? context) {
          final Completer<void>? pending = _dismissCompleters.remove(requestId);
          if (pending == null) return;
          if (success.toDart) {
            pending.complete();
          } else {
            pending.completeError(
              const MimcException(
                'web_uc_dismiss',
                'Failed to dismiss unlimited group',
              ),
            );
          }
        }).toJS,
        requestId.toString(),
      );
    } catch (_) {
      _dismissCompleters.remove(requestId);
      rethrow;
    }
    return completer.future;
  }

  @override
  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  }) =>
      _unsupportedRts();

  @override
  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  ) =>
      _unsupportedRts();

  @override
  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  }) =>
      _unsupportedRts();

  @override
  Future<MimcRtsBufferState> getRtsBufferState() => _unsupportedRts();

  @override
  Future<void> clearRtsBuffers() => _unsupportedRts();

  @override
  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  }) =>
      _unsupportedRts();

  @override
  Future<void> closeRtsCall(int callId, {String reason = ''}) =>
      _unsupportedRts();

  @override
  Future<int> sendRtsData({
    required int callId,
    required List<int> payload,
    required MimcRtsDataType dataType,
    MimcRtsDataPriority priority = MimcRtsDataPriority.p1,
    bool canBeDropped = false,
    int resendCount = 0,
    MimcRtsChannelType channelType = MimcRtsChannelType.automatic,
    String context = '',
  }) =>
      _unsupportedRts();

  @override
  Future<int> createRtsChannel({List<int> extra = const <int>[]}) =>
      _unsupportedRts();

  @override
  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _unsupportedRts();

  @override
  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _unsupportedRts();

  @override
  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId) =>
      _unsupportedRts();

  @override
  Future<void> dispose() async {
    try {
      _user?.logout();
    } catch (_) {
      // The WebJS SDK throws when logout is called before login.
    }
    _user = null;
    _tokenObject = null;
    _online = false;
    for (final Completer<int> completer in _createCompleters.values) {
      completer.completeError(
        const MimcException('disposed', 'MIMC client was disposed'),
      );
    }
    for (final Completer<void> completer in _joinCompleters.values) {
      completer.completeError(
        const MimcException('disposed', 'MIMC client was disposed'),
      );
    }
    for (final Completer<void> completer in _quitCompleters.values) {
      completer.completeError(
        const MimcException('disposed', 'MIMC client was disposed'),
      );
    }
    for (final Completer<void> completer in _dismissCompleters.values) {
      completer.completeError(
        const MimcException('disposed', 'MIMC client was disposed'),
      );
    }
    _createCompleters.clear();
    _joinCompleters.clear();
    _quitCompleters.clear();
    _dismissCompleters.clear();
  }

  _MimcJsUser _requireUser() {
    final _MimcJsUser? user = _user;
    if (user == null) {
      throw const MimcException(
        'not_initialized',
        'Web MIMC user is not initialized',
      );
    }
    return user;
  }
}

Never _unsupportedRts() => throw const MimcException(
      'unsupported',
      'The WebJS SDK does not expose realtime streams',
    );

Future<void> _loadSdk() {
  final Completer<void> completer = Completer<void>();
  final web.HTMLScriptElement script =
      web.document.createElement('script') as web.HTMLScriptElement;
  script.src = 'assets/packages/flutter_mimc/assets/web/mimc-min_1_0_3.js';
  script.async = true;
  script.setAttribute('data-flutter-mimc', '1');
  script.addEventListener(
    'load',
    ((web.Event _) => completer.complete()).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) => completer.completeError(
          const MimcException(
            'web_sdk_load_failed',
            'Unable to load mimc-min_1_0_3.js',
          ),
        )).toJS,
  );
  web.document.head?.append(script);
  return completer.future;
}

JSAny? _decodeToken(String token) {
  try {
    final Object? decoded = jsonDecode(token);
    return decoded?.jsify();
  } on FormatException catch (error) {
    throw MimcException('invalid_token', 'Token must be valid JSON', error);
  }
}

MimcMessage _directMessageFromJs(_MimcJsDirectMessage message) => MimcMessage(
      packetId: _jsString(message.getPacketId()),
      sequence: _jsInt(message.getSequence()),
      timestamp: _jsInt(message.getTimeStamp()),
      fromAccount: _jsString(message.getFromAccount()),
      fromResource: _jsString(message.getFromResource()),
      toAccount: _jsString(message.getToAccount()),
      toResource: _jsString(message.getToResource()),
      bizType: _jsString(message.getBizType()),
      payload: Uint8List.fromList(utf8.encode(_jsString(message.getPayload()))),
      channel: MimcMessageChannel.direct,
    );

MimcMessage _groupMessageFromJs(
  _MimcJsGroupMessage message,
  MimcMessageChannel channel,
) =>
    MimcMessage(
      packetId: _jsString(message.getPacketId()),
      sequence: _jsInt(message.getSequence()),
      timestamp: _jsInt(message.getTimeStamp()),
      fromAccount: _jsString(message.getFromAccount()),
      fromResource: _jsString(message.getFromResource()),
      topicId: _jsInt(message.getTopicId()),
      bizType: _jsString(message.getBizType()),
      payload: Uint8List.fromList(utf8.encode(_jsString(message.getPayload()))),
      channel: channel,
    );

String _payloadToJsString(List<int> payload) {
  try {
    return utf8.decode(payload, allowMalformed: false);
  } on FormatException catch (error) {
    throw MimcException(
      'web_payload_not_utf8',
      'The legacy WebJS SDK only accepts UTF-8 string payloads',
      error,
    );
  }
}

String _jsString(JSAny? value) => switch (value) {
      JSString string => string.toDart,
      JSNumber number => number.toDartDouble.toString(),
      JSBoolean boolean => boolean.toDart.toString(),
      _ => '',
    };

int? _jsInt(JSAny? value) => switch (value) {
      JSNumber number => number.toDartDouble.toInt(),
      JSString string => int.tryParse(string.toDart),
      _ => null,
    };

@JS('MIMCUser')
extension type _MimcJsUser._(JSObject _) implements JSObject {
  external factory _MimcJsUser(
    String appId,
    String appAccount,
    String resource,
  );

  external void registerFetchToken(JSFunction callback);
  external void registerStatusChange(JSFunction callback);
  external void registerDisconnHandler(JSFunction callback);
  external void registerP2PMsgHandler(JSFunction callback);
  external void registerGroupMsgHandler(JSFunction callback);
  external void registerServerAckHandler(JSFunction callback);
  external void registerUCJoinRespHandler(JSFunction callback);
  external void registerUCQuitRespHandler(JSFunction callback);
  external void registerUCMsgHandler(JSFunction callback);
  external void registerUCDismissHandler(JSFunction callback);
  external void registerPullNotificationHandler(JSFunction callback);

  external void login();
  external void logout();

  external String sendMessage(
    String toAccount,
    String payload,
    String bizType,
    bool store,
  );
  external String sendGroupMessage(
    double topicId,
    String payload,
    String bizType,
    bool store,
  );
  external String sendUnlimitedGroupMessage(
    double topicId,
    String payload,
    String bizType,
    bool store,
  );
  external void createUnlimitedGroup(
    String topicName,
    JSFunction callback,
    String context,
  );
  external void joinUnlimitedGroup(double topicId, String context);
  external void quitUnlimitedGroup(double topicId, String context);
  external void dismissUnlimitedGroup(
    double topicId,
    JSFunction callback,
    String context,
  );
}

extension type _MimcJsDirectMessage._(JSObject _) implements JSObject {
  external JSAny? getPacketId();
  external JSAny? getSequence();
  external JSAny? getTimeStamp();
  external JSAny? getFromAccount();
  external JSAny? getFromResource();
  external JSAny? getToAccount();
  external JSAny? getToResource();
  external JSAny? getBizType();
  external JSAny? getPayload();
}

extension type _MimcJsGroupMessage._(JSObject _) implements JSObject {
  external JSAny? getPacketId();
  external JSAny? getSequence();
  external JSAny? getTimeStamp();
  external JSAny? getFromAccount();
  external JSAny? getFromResource();
  external JSAny? getTopicId();
  external JSAny? getBizType();
  external JSAny? getPayload();
}
