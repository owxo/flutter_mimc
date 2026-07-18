import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../flutter_mimc_platform_interface.dart';
import '../mimc_exception.dart';
import '../model/mimc_capability.dart';
import '../model/mimc_config.dart';
import '../model/mimc_event.dart';
import '../model/mimc_rts.dart';

final class FlutterMimcFfi extends FlutterMimcPlatform {
  FlutterMimcFfi({DynamicLibrary? library})
      : _bindings = _FlutterMimcBindings(library ?? _openLibrary()) {
    _events = StreamController<MimcEvent>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
  }

  final _FlutterMimcBindings _bindings;
  late final StreamController<MimcEvent> _events;
  Timer? _pollTimer;

  @override
  Stream<MimcEvent> get events => _events.stream;

  @override
  Future<Set<MimcCapability>> getCapabilities() async {
    final int bits = _bindings.getCapabilities();
    return <MimcCapability>{
      if (bits & (1 << 0) != 0) MimcCapability.message,
      if (bits & (1 << 1) != 0) MimcCapability.groupMessage,
      if (bits & (1 << 2) != 0) MimcCapability.onlineMessage,
      if (bits & (1 << 3) != 0) MimcCapability.unlimitedGroup,
      if (bits & (1 << 4) != 0) MimcCapability.offlinePull,
      if (bits & (1 << 5) != 0) MimcCapability.realtimeStream,
      if (bits & (1 << 6) != 0) MimcCapability.realtimeChannel,
    };
  }

  @override
  Future<void> initialize({
    required MimcConfig config,
    required String token,
  }) async {
    final Pointer<Utf8> account = config.appAccount.toNativeUtf8();
    final Pointer<Utf8> resource = (config.resource ?? '').toNativeUtf8();
    final Pointer<Utf8> cache = (config.cacheDirectory ?? '').toNativeUtf8();
    final Pointer<Utf8> nativeToken = token.toNativeUtf8();
    try {
      _check(
        _bindings.initialize(
          config.appIdAsInt,
          account,
          resource,
          cache,
          nativeToken,
          config.debug ? 1 : 0,
        ),
      );
      if (_bindings.getCapabilities() & (1 << 5) != 0) {
        await setRtsIncomingCallPolicy(
          config.rtsIncomingCallPolicy,
          description: config.rtsIncomingCallDescription,
        );
      }
      if (_events.hasListener) {
        _startPolling();
      }
    } finally {
      malloc.free(account);
      malloc.free(resource);
      malloc.free(cache);
      malloc.free(nativeToken);
    }
  }

  @override
  Future<void> updateToken(String token) async {
    final Pointer<Utf8> value = token.toNativeUtf8();
    try {
      _check(_bindings.updateToken(value));
    } finally {
      malloc.free(value);
    }
  }

  @override
  Future<void> login() async => _check(_bindings.login());

  @override
  Future<void> logout() async => _check(_bindings.logout());

  @override
  Future<bool> isOnline() async => _bindings.isOnline() != 0;

  @override
  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) =>
      _sendToAccount(
        _bindings.sendMessage,
        toAccount: toAccount,
        payload: payload,
        bizType: bizType,
        store: store,
      );

  @override
  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  }) =>
      _sendToAccount(
        _bindings.sendOnlineMessage,
        toAccount: toAccount,
        payload: payload,
        bizType: bizType,
        store: store,
      );

  @override
  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async {
    final Pointer<Uint8> nativePayload = _copyPayload(payload);
    final Pointer<Utf8> nativeBizType = bizType.toNativeUtf8();
    final Pointer<Utf8> packetId = malloc<Uint8>(128).cast<Utf8>();
    try {
      _check(
        _bindings.sendGroupMessage(
          topicId,
          nativePayload,
          payload.length,
          nativeBizType,
          store ? 1 : 0,
          packetId,
          128,
        ),
      );
      return packetId.toDartString();
    } finally {
      malloc.free(nativePayload);
      malloc.free(nativeBizType);
      malloc.free(packetId);
    }
  }

  @override
  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) =>
      throw const MimcException(
        'unsupported',
        'The C++ desktop adapter does not expose unlimited groups yet',
      );

  @override
  Future<int> createUnlimitedGroup(String topicName) =>
      throw const MimcException(
        'unsupported',
        'The C++ desktop adapter does not expose unlimited groups yet',
      );

  @override
  Future<void> joinUnlimitedGroup(int topicId) => throw const MimcException(
        'unsupported',
        'The C++ desktop adapter does not expose unlimited groups yet',
      );

  @override
  Future<void> quitUnlimitedGroup(int topicId) => throw const MimcException(
        'unsupported',
        'The C++ desktop adapter does not expose unlimited groups yet',
      );

  @override
  Future<void> dismissUnlimitedGroup(int topicId) => throw const MimcException(
        'unsupported',
        'The C++ desktop adapter does not expose unlimited groups yet',
      );

  @override
  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  }) async {
    final Pointer<Utf8> nativeDescription = description.toNativeUtf8();
    try {
      _check(
        _bindings.setRtsIncomingCallPolicy(
          policy == MimcRtsIncomingCallPolicy.accept ? 1 : 0,
          nativeDescription,
        ),
      );
    } finally {
      malloc.free(nativeDescription);
    }
  }

  @override
  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  ) async =>
      _check(
        _bindings.configureRtsStream(
          dataType.index,
          config.strategy.index,
          config.ackWaitTimeMs,
          config.encrypt ? 1 : 0,
        ),
      );

  @override
  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  }) async =>
      _check(_bindings.configureRtsBuffers(sendSize, receiveSize));

  @override
  Future<MimcRtsBufferState> getRtsBufferState() async {
    final Pointer<Int32> sendSize = calloc<Int32>();
    final Pointer<Int32> receiveSize = calloc<Int32>();
    final Pointer<Float> sendUsage = calloc<Float>();
    final Pointer<Float> receiveUsage = calloc<Float>();
    try {
      _check(
        _bindings.getRtsBufferState(
          sendSize,
          receiveSize,
          sendUsage,
          receiveUsage,
        ),
      );
      return MimcRtsBufferState(
        sendSize: sendSize.value,
        receiveSize: receiveSize.value,
        sendUsageRate: sendUsage.value,
        receiveUsageRate: receiveUsage.value,
      );
    } finally {
      calloc.free(sendSize);
      calloc.free(receiveSize);
      calloc.free(sendUsage);
      calloc.free(receiveUsage);
    }
  }

  @override
  Future<void> clearRtsBuffers() async => _check(_bindings.clearRtsBuffers());

  @override
  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  }) async {
    final Pointer<Utf8> account = toAccount.toNativeUtf8();
    final Pointer<Utf8> resource = toResource.toNativeUtf8();
    final Pointer<Uint8> content = _copyPayload(appContent);
    final Pointer<Int64> callId = calloc<Int64>();
    try {
      _check(
        _bindings.dialRtsCall(
          account,
          resource,
          content,
          appContent.length,
          callId,
        ),
      );
      return callId.value;
    } finally {
      malloc.free(account);
      malloc.free(resource);
      malloc.free(content);
      calloc.free(callId);
    }
  }

  @override
  Future<void> closeRtsCall(int callId, {String reason = ''}) async {
    final Pointer<Utf8> nativeReason = reason.toNativeUtf8();
    try {
      _check(_bindings.closeRtsCall(callId, nativeReason));
    } finally {
      malloc.free(nativeReason);
    }
  }

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
  }) async {
    final Pointer<Uint8> nativePayload = _copyPayload(payload);
    final Pointer<Utf8> nativeContext = context.toNativeUtf8();
    final Pointer<Int32> dataId = calloc<Int32>();
    try {
      _check(
        _bindings.sendRtsData(
          callId,
          nativePayload,
          payload.length,
          dataType.index,
          priority.index,
          canBeDropped ? 1 : 0,
          resendCount,
          channelType.index,
          nativeContext,
          dataId,
        ),
      );
      return dataId.value;
    } finally {
      malloc.free(nativePayload);
      malloc.free(nativeContext);
      calloc.free(dataId);
    }
  }

  @override
  Future<int> createRtsChannel({List<int> extra = const <int>[]}) =>
      _unsupportedRtsChannel();

  @override
  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _unsupportedRtsChannel();

  @override
  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _unsupportedRtsChannel();

  @override
  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId) =>
      _unsupportedRtsChannel();

  @override
  Future<void> dispose() async {
    _stopPolling();
    _bindings.dispose();
  }

  Future<String> _sendToAccount(
    _SendToAccount function, {
    required String toAccount,
    required List<int> payload,
    required String bizType,
    required bool store,
  }) async {
    final Pointer<Utf8> account = toAccount.toNativeUtf8();
    final Pointer<Uint8> nativePayload = _copyPayload(payload);
    final Pointer<Utf8> nativeBizType = bizType.toNativeUtf8();
    final Pointer<Utf8> packetId = malloc<Uint8>(128).cast<Utf8>();
    try {
      _check(
        function(
          account,
          nativePayload,
          payload.length,
          nativeBizType,
          store ? 1 : 0,
          packetId,
          128,
        ),
      );
      return packetId.toDartString();
    } finally {
      malloc.free(account);
      malloc.free(nativePayload);
      malloc.free(nativeBizType);
      malloc.free(packetId);
    }
  }

  Pointer<Uint8> _copyPayload(List<int> payload) {
    final Pointer<Uint8> result = malloc<Uint8>(payload.length);
    result.asTypedList(payload.length).setAll(0, payload);
    return result;
  }

  void _check(int result) {
    if (result == 0) {
      return;
    }
    final String message = _bindings.lastError().toDartString();
    throw MimcException('native_$result', message);
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _pollEvents(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollEvents() {
    var capacity = 64 * 1024;
    Pointer<Utf8> buffer = malloc<Uint8>(capacity).cast<Utf8>();
    try {
      while (true) {
        var length = _bindings.pollEvent(buffer, capacity);
        if (length == 0) {
          return;
        }
        if (length < 0) {
          capacity = -length;
          malloc.free(buffer);
          buffer = malloc<Uint8>(capacity).cast<Utf8>();
          length = _bindings.pollEvent(buffer, capacity);
          if (length <= 0) {
            throw const MimcException(
              'invalid_native_event',
              'Native event size changed while it was being copied',
            );
          }
        }
        final Object? decoded = jsonDecode(buffer.toDartString(length: length));
        if (decoded is Map) {
          _events.add(
            MimcEvent.fromMap(Map<Object?, Object?>.from(decoded)),
          );
        }
      }
    } catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    } finally {
      malloc.free(buffer);
    }
  }
}

Never _unsupportedRtsChannel() => throw const MimcException(
      'unsupported',
      'The C++ desktop SDK C API does not expose RTS channels',
    );

DynamicLibrary _openLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('flutter_mimc.framework/flutter_mimc');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libflutter_mimc.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('flutter_mimc.dll');
  }
  throw UnsupportedError(
      'Unsupported FFI platform: ${Platform.operatingSystem}');
}

typedef _SendToAccount = int Function(
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);

final class _FlutterMimcBindings {
  _FlutterMimcBindings(this.library);

  final DynamicLibrary library;

  late final int Function() getCapabilities =
      library.lookupFunction<Uint64 Function(), int Function()>(
          'flutter_mimc_get_capabilities');
  late final Pointer<Utf8> Function() lastError = library.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('flutter_mimc_last_error');
  late final int Function(
    int,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    int,
  ) initialize = library.lookupFunction<
      Int32 Function(
        Int64,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Uint8,
      ),
      int Function(
        int,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Utf8>,
        int,
      )>('flutter_mimc_initialize');
  late final int Function(Pointer<Utf8>) updateToken = library.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('flutter_mimc_update_token');
  late final int Function() login = library
      .lookupFunction<Int32 Function(), int Function()>('flutter_mimc_login');
  late final int Function() logout = library
      .lookupFunction<Int32 Function(), int Function()>('flutter_mimc_logout');
  late final int Function() isOnline =
      library.lookupFunction<Uint8 Function(), int Function()>(
          'flutter_mimc_is_online');
  late final _SendToAccount sendMessage = library.lookupFunction<
      Int32 Function(
        Pointer<Utf8>,
        Pointer<Uint8>,
        Int32,
        Pointer<Utf8>,
        Uint8,
        Pointer<Utf8>,
        Int32,
      ),
      _SendToAccount>('flutter_mimc_send_message');
  late final _SendToAccount sendOnlineMessage = library.lookupFunction<
      Int32 Function(
        Pointer<Utf8>,
        Pointer<Uint8>,
        Int32,
        Pointer<Utf8>,
        Uint8,
        Pointer<Utf8>,
        Int32,
      ),
      _SendToAccount>('flutter_mimc_send_online_message');
  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Utf8>,
    int,
    Pointer<Utf8>,
    int,
  ) sendGroupMessage = library.lookupFunction<
      Int32 Function(
        Int64,
        Pointer<Uint8>,
        Int32,
        Pointer<Utf8>,
        Uint8,
        Pointer<Utf8>,
        Int32,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        Pointer<Utf8>,
        int,
        Pointer<Utf8>,
        int,
      )>('flutter_mimc_send_group_message');
  late final int Function(int, Pointer<Utf8>) setRtsIncomingCallPolicy =
      library.lookupFunction<Int32 Function(Uint8, Pointer<Utf8>),
          int Function(int, Pointer<Utf8>)>(
    'flutter_mimc_set_rts_incoming_call_policy',
  );
  late final int Function(int, int, int, int) configureRtsStream =
      library.lookupFunction<Int32 Function(Int32, Int32, Int32, Uint8),
          int Function(int, int, int, int)>(
    'flutter_mimc_configure_rts_stream',
  );
  late final int Function(int, int) configureRtsBuffers = library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
          'flutter_mimc_configure_rts_buffers');
  late final int Function(
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Float>,
    Pointer<Float>,
  ) getRtsBufferState = library.lookupFunction<
      Int32 Function(
        Pointer<Int32>,
        Pointer<Int32>,
        Pointer<Float>,
        Pointer<Float>,
      ),
      int Function(
        Pointer<Int32>,
        Pointer<Int32>,
        Pointer<Float>,
        Pointer<Float>,
      )>('flutter_mimc_get_rts_buffer_state');
  late final int Function() clearRtsBuffers =
      library.lookupFunction<Int32 Function(), int Function()>(
          'flutter_mimc_clear_rts_buffers');
  late final int Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
    Pointer<Int64>,
  ) dialRtsCall = library.lookupFunction<
      Int32 Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Uint8>,
        Int32,
        Pointer<Int64>,
      ),
      int Function(
        Pointer<Utf8>,
        Pointer<Utf8>,
        Pointer<Uint8>,
        int,
        Pointer<Int64>,
      )>('flutter_mimc_dial_rts_call');
  late final int Function(int, Pointer<Utf8>) closeRtsCall =
      library.lookupFunction<Int32 Function(Int64, Pointer<Utf8>),
          int Function(int, Pointer<Utf8>)>('flutter_mimc_close_rts_call');
  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    int,
    int,
    int,
    int,
    int,
    Pointer<Utf8>,
    Pointer<Int32>,
  ) sendRtsData = library.lookupFunction<
      Int32 Function(
        Int64,
        Pointer<Uint8>,
        Int32,
        Int32,
        Int32,
        Uint8,
        Uint32,
        Int32,
        Pointer<Utf8>,
        Pointer<Int32>,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        int,
        int,
        int,
        int,
        int,
        Pointer<Utf8>,
        Pointer<Int32>,
      )>('flutter_mimc_send_rts_data');
  late final int Function(Pointer<Utf8>, int) pollEvent =
      library.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('flutter_mimc_poll_event');
  late final void Function() dispose = library
      .lookupFunction<Void Function(), void Function()>('flutter_mimc_dispose');
}
