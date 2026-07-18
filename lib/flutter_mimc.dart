library;

import 'dart:async';

import 'flutter_mimc_platform_interface.dart';
import 'src/mimc_exception.dart';
import 'src/model/mimc_capability.dart';
import 'src/model/mimc_config.dart';
import 'src/model/mimc_event.dart';
import 'src/model/mimc_rts.dart';
import 'src/platform_registration.dart';

export 'src/mimc_exception.dart';
export 'src/model/mimc_capability.dart';
export 'src/model/mimc_config.dart';
export 'src/model/mimc_connection_state.dart';
export 'src/model/mimc_event.dart';
export 'src/model/mimc_message.dart';
export 'src/model/mimc_rts.dart';
export 'src/model/mimc_server_ack.dart';

typedef MimcTokenProvider = Future<String> Function();

/// Main entry point for the multi-platform Xiaomi MIMC client.
final class FlutterMimc {
  FlutterMimc._();

  static final FlutterMimc instance = FlutterMimc._();

  MimcTokenProvider? _tokenProvider;
  StreamSubscription<MimcEvent>? _tokenRefreshSubscription;
  bool _initialized = false;

  FlutterMimcPlatform get _platform {
    registerDesktopPlatformIfNeeded();
    return FlutterMimcPlatform.instance;
  }

  Stream<MimcEvent> get events => _platform.events;

  bool get isInitialized => _initialized;

  Future<Set<MimcCapability>> getCapabilities() => _platform.getCapabilities();

  /// Creates the native/web MIMC user and caches a token for synchronous SDK
  /// token callbacks. The app secret must stay in the application's backend.
  Future<void> initialize({
    required MimcConfig config,
    required MimcTokenProvider tokenProvider,
  }) async {
    final String token = await tokenProvider();
    _validateToken(token);

    if (_initialized) {
      await dispose();
    }

    _tokenProvider = tokenProvider;
    await _platform.initialize(config: config, token: token);
    _initialized = true;

    _tokenRefreshSubscription = events
        .where((MimcEvent event) => event is MimcTokenRefreshRequired)
        .listen((_) => unawaited(refreshToken()));
  }

  Future<void> refreshToken() async {
    final MimcTokenProvider? provider = _tokenProvider;
    if (provider == null) {
      throw const MimcException(
        'not_initialized',
        'initialize() must be called before refreshing a token',
      );
    }
    final String token = await provider();
    _validateToken(token);
    await _platform.updateToken(token);
  }

  Future<void> login() {
    _requireInitialized();
    return _platform.login();
  }

  Future<void> logout() {
    _requireInitialized();
    return _platform.logout();
  }

  Future<bool> isOnline() {
    _requireInitialized();
    return _platform.isOnline();
  }

  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) {
    _requireInitialized();
    return _platform.sendMessage(
      toAccount: toAccount,
      payload: payload,
      bizType: bizType,
      store: store,
    );
  }

  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) {
    _requireInitialized();
    return _platform.sendGroupMessage(
      topicId: topicId,
      payload: payload,
      bizType: bizType,
      store: store,
    );
  }

  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  }) {
    _requireInitialized();
    return _platform.sendOnlineMessage(
      toAccount: toAccount,
      payload: payload,
      bizType: bizType,
      store: store,
    );
  }

  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) {
    _requireInitialized();
    return _platform.sendUnlimitedGroupMessage(
      topicId: topicId,
      payload: payload,
      bizType: bizType,
      store: store,
    );
  }

  Future<int> createUnlimitedGroup(String topicName) {
    _requireInitialized();
    return _platform.createUnlimitedGroup(topicName);
  }

  Future<void> joinUnlimitedGroup(int topicId) {
    _requireInitialized();
    return _platform.joinUnlimitedGroup(topicId);
  }

  Future<void> quitUnlimitedGroup(int topicId) {
    _requireInitialized();
    return _platform.quitUnlimitedGroup(topicId);
  }

  Future<void> dismissUnlimitedGroup(int topicId) {
    _requireInitialized();
    return _platform.dismissUnlimitedGroup(topicId);
  }

  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  }) {
    _requireInitialized();
    return _platform.setRtsIncomingCallPolicy(
      policy,
      description: description,
    );
  }

  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  ) {
    _requireInitialized();
    return _platform.configureRtsStream(dataType, config);
  }

  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  }) {
    _requireInitialized();
    if (sendSize <= 0 || receiveSize <= 0) {
      throw const MimcException(
        'invalid_rts_buffer_size',
        'RTS buffer sizes must be greater than zero',
      );
    }
    return _platform.configureRtsBuffers(
      sendSize: sendSize,
      receiveSize: receiveSize,
    );
  }

  Future<MimcRtsBufferState> getRtsBufferState() {
    _requireInitialized();
    return _platform.getRtsBufferState();
  }

  Future<void> clearRtsBuffers() {
    _requireInitialized();
    return _platform.clearRtsBuffers();
  }

  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  }) {
    _requireInitialized();
    if (toAccount.trim().isEmpty) {
      throw const MimcException(
        'invalid_rts_account',
        'RTS destination account is empty',
      );
    }
    return _platform.dialRtsCall(
      toAccount: toAccount,
      toResource: toResource,
      appContent: appContent,
    );
  }

  Future<void> closeRtsCall(int callId, {String reason = ''}) {
    _requireInitialized();
    return _platform.closeRtsCall(callId, reason: reason);
  }

  Future<int> sendRtsData({
    required int callId,
    required List<int> payload,
    required MimcRtsDataType dataType,
    MimcRtsDataPriority priority = MimcRtsDataPriority.p1,
    bool canBeDropped = false,
    int resendCount = 0,
    MimcRtsChannelType channelType = MimcRtsChannelType.automatic,
    String context = '',
  }) {
    _requireInitialized();
    if (resendCount < 0) {
      throw const MimcException(
        'invalid_rts_resend_count',
        'RTS resendCount cannot be negative',
      );
    }
    return _platform.sendRtsData(
      callId: callId,
      payload: payload,
      dataType: dataType,
      priority: priority,
      canBeDropped: canBeDropped,
      resendCount: resendCount,
      channelType: channelType,
      context: context,
    );
  }

  Future<int> createRtsChannel({List<int> extra = const <int>[]}) {
    _requireInitialized();
    return _platform.createRtsChannel(extra: extra);
  }

  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  }) {
    _requireInitialized();
    return _platform.joinRtsChannel(callId: callId, callKey: callKey);
  }

  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  }) {
    _requireInitialized();
    return _platform.leaveRtsChannel(callId: callId, callKey: callKey);
  }

  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId) {
    _requireInitialized();
    return _platform.getRtsChannelMembers(callId);
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    if (_initialized) {
      await _platform.dispose();
    }
    _tokenProvider = null;
    _initialized = false;
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw const MimcException(
        'not_initialized',
        'FlutterMimc.initialize() must be called first',
      );
    }
  }
}

void _validateToken(String token) {
  if (token.trim().isEmpty) {
    throw const MimcException('invalid_token', 'Token response is empty');
  }
}
