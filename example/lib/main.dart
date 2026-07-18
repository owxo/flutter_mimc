import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mimc/flutter_mimc.dart';

import 'mimc_test_config.dart';
import 'mimc_token_client.dart';

void main() => runApp(const MimcExampleApp());

class MimcExampleApp extends StatelessWidget {
  const MimcExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'flutter_mimc E2E',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          useMaterial3: true,
        ),
        home: const MimcTestPage(),
      );
}

class MimcTestPage extends StatefulWidget {
  const MimcTestPage({super.key});

  @override
  State<MimcTestPage> createState() => _MimcTestPageState();
}

class _MimcTestPageState extends State<MimcTestPage> {
  final FlutterMimc _mimc = FlutterMimc.instance;
  final TextEditingController _account =
      TextEditingController(text: MimcTestConfig.account);
  final TextEditingController _peer =
      TextEditingController(text: MimcTestConfig.peerAccount);
  final TextEditingController _endpoint =
      TextEditingController(text: MimcTestConfig.tokenEndpoint);
  final TextEditingController _message =
      TextEditingController(text: 'flutter_mimc live ping');
  final List<String> _logs = <String>[];

  StreamSubscription<MimcEvent>? _events;
  Set<MimcCapability> _capabilities = <MimcCapability>{};
  bool _busy = false;
  bool _initialized = false;
  bool _online = false;
  bool _autoMessageSent = false;
  int? _callId;

  @override
  void initState() {
    super.initState();
    _events = _mimc.events.listen(_onEvent, onError: _onStreamError);
    unawaited(
      _loadCapabilities().then((_) {
        if (MimcTestConfig.autoStart) return _initializeAndLogin();
      }),
    );
  }

  Future<void> _loadCapabilities() async {
    await _run('capabilities', () async {
      final Set<MimcCapability> values = await _mimc.getCapabilities();
      if (mounted) setState(() => _capabilities = values);
      _log('capabilities=${values.map((value) => value.name).join(',')}');
    });
  }

  Future<void> _initializeAndLogin() => _run('login', () async {
        final String account = _account.text.trim();
        if (MimcTestConfig.appId.isEmpty) {
          throw StateError('MIMC_APP_ID must be supplied at runtime');
        }
        if (account.isEmpty) throw StateError('appAccount cannot be empty');

        final MimcTokenClient tokenClient = MimcTokenClient(
          endpoint: _endpoint.text.trim(),
          userToken: MimcTestConfig.fastAdminUserToken,
          testAuthToken: MimcTestConfig.testAuthToken,
        );
        await _mimc.initialize(
          config: MimcConfig(
            appId: MimcTestConfig.appId,
            appAccount: account,
            resource: MimcTestConfig.resource,
            debug: true,
            rtsIncomingCallPolicy: MimcRtsIncomingCallPolicy.accept,
          ),
          tokenProvider: () => tokenClient.fetchForAccount(account),
        );
        _initialized = true;
        await _mimc.login();
        _log('login requested: $account@${MimcTestConfig.resource}');
      });

  Future<void> _logout() => _run('logout', () async {
        if (_initialized) await _mimc.logout();
        _online = false;
        _callId = null;
        _log('logout requested');
      });

  Future<void> _sendMessage() => _run('send message', () async {
        final String packetId = await _mimc.sendMessage(
          toAccount: _requiredPeer(),
          payload: utf8.encode(_message.text),
          bizType: 'flutter_mimc.e2e',
        );
        _log('message queued: packetId=$packetId');
      });

  Future<void> _dialRts() => _run('dial RTS', () async {
        final int callId = await _mimc.dialRtsCall(
          toAccount: _requiredPeer(),
          toResource: MimcTestConfig.peerResource,
          appContent: utf8.encode('flutter_mimc E2E'),
        );
        _callId = callId;
        _log('RTS dialing: callId=$callId');
      });

  Future<void> _sendRtsData() => _run('send RTS data', () async {
        final int? callId = _callId;
        if (callId == null) throw StateError('No active RTS call');
        final int dataId = await _mimc.sendRtsData(
          callId: callId,
          payload: utf8.encode(_message.text),
          dataType: MimcRtsDataType.audio,
          context: 'flutter_mimc.e2e',
        );
        _log('RTS data queued: callId=$callId dataId=$dataId');
      });

  Future<void> _closeRts() => _run('close RTS', () async {
        final int? callId = _callId;
        if (callId == null) throw StateError('No active RTS call');
        await _mimc.closeRtsCall(callId, reason: 'E2E completed');
        _callId = null;
        _log('RTS close requested: callId=$callId');
      });

  String _requiredPeer() {
    final String peer = _peer.text.trim();
    if (peer.isEmpty) throw StateError('Peer appAccount cannot be empty');
    return peer;
  }

  void _onEvent(MimcEvent event) {
    switch (event) {
      case MimcConnectionChanged(
          :final state,
          :final reason,
          :final description
        ):
        _online = state == MimcConnectionState.online;
        _log('connection=$state reason=$reason description=$description');
        if (_online && MimcTestConfig.autoStart && !_autoMessageSent) {
          _autoMessageSent = true;
          unawaited(_sendMessage());
        }
      case MimcMessageReceived(:final message):
        _log(
          'message from=${message.fromAccount} '
          'payload=${utf8.decode(message.payload, allowMalformed: true)}',
        );
      case MimcServerAckReceived(:final ack):
        _log('ack packetId=${ack.packetId} code=${ack.code}');
        if (MimcTestConfig.autoStart) {
          _log('MIMC_LIVE_E2E_PASS');
        }
      case MimcRtsCallIncoming(:final callId, :final fromAccount):
        _callId = callId;
        _log('RTS incoming: callId=$callId from=$fromAccount');
      case MimcRtsCallAnswered(
          :final callId,
          :final accepted,
          :final description
        ):
        if (accepted) _callId = callId;
        _log('RTS answered: callId=$callId accepted=$accepted $description');
      case MimcRtsCallClosed(:final callId, :final description):
        if (_callId == callId) _callId = null;
        _log('RTS closed: callId=$callId $description');
      case MimcRtsDataReceived(
          :final callId,
          :final fromAccount,
          :final payload
        ):
        _log(
          'RTS data: callId=$callId from=$fromAccount '
          'payload=${utf8.decode(payload, allowMalformed: true)}',
        );
      default:
        _log(event.runtimeType.toString());
    }
    if (mounted) setState(() {});
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _log('event stream error: $error');
  }

  Future<void> _run(String operation, Future<void> Function() action) async {
    if (_busy) return;
    if (mounted) setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _log('$operation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _log(String message) {
    final String now = DateTime.now().toIso8601String().substring(11, 23);
    _logs.insert(0, '$now $message');
    debugPrint('[flutter_mimc] $message');
    if (_logs.length > 100) _logs.removeLast();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_mimc.dispose());
    _account.dispose();
    _peer.dispose();
    _endpoint.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool supportsRts =
        _capabilities.contains(MimcCapability.realtimeStream);
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_mimc E2E'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(_online ? 'ONLINE' : 'OFFLINE'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextField(
              controller: _endpoint,
              enabled: !_initialized,
              decoration:
                  const InputDecoration(labelText: 'PHP Token endpoint'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _account,
              enabled: !_initialized,
              decoration: const InputDecoration(labelText: '后端用户唯一 ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _peer,
              decoration: const InputDecoration(labelText: '对端用户唯一 ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              decoration: const InputDecoration(labelText: '测试内容'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy || _initialized ? null : _initializeAndLogin,
                  child: const Text('初始化并登录'),
                ),
                OutlinedButton(
                  onPressed: _busy || !_initialized ? null : _logout,
                  child: const Text('退出'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !_online ? null : _sendMessage,
                  child: const Text('发送消息'),
                ),
                if (supportsRts)
                  FilledButton.tonal(
                    onPressed:
                        _busy || !_online || _callId != null ? null : _dialRts,
                    child: const Text('呼叫 RTS'),
                  ),
                if (supportsRts)
                  OutlinedButton(
                    onPressed: _busy || _callId == null ? null : _sendRtsData,
                    child: const Text('发送 RTS 数据'),
                  ),
                if (supportsRts)
                  OutlinedButton(
                    onPressed: _busy || _callId == null ? null : _closeRts,
                    child: const Text('挂断 RTS'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'resource=${MimcTestConfig.resource}\n'
              'capabilities=${_capabilities.map((value) => value.name).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            SelectableText(
              _logs.isEmpty ? '等待操作…' : _logs.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
