// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart' hide ConnectionException;
import 'package:mqtt_client/mqtt_server_client.dart';

import 'control_transport.dart';
import 'errors.dart';
import 'models.dart';

typedef MqttClientFactory =
    MqttClient Function(String server, String clientId, int port);

final class MqttControlTransport implements ControlTransport {
  MqttControlTransport({MqttClientFactory? createClient})
    : _createClient = createClient ?? _createSecureClient;

  final MqttClientFactory _createClient;
  final _states = StreamController<ControlTransportState>.broadcast();
  final _messages = StreamController<ControlEnvelope>.broadcast();
  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<ControlTransportState> get states => _states.stream;

  @override
  Stream<ControlEnvelope> get messages => _messages.stream;

  @override
  Future<void> connect(EswConnectionConfig config) async {
    config.validate();
    final generation = ++_generation;
    await _disconnectCurrent();
    if (generation != _generation || _disposed) {
      throw const ConnectionException('The connection attempt was superseded.');
    }
    _emit(generation, ControlTransportState.connecting);
    final clientId =
        'flutter-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
        '${Random.secure().nextInt(1 << 20).toRadixString(36)}';
    final client = _createClient(config.server, clientId, config.port);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.logging(on: false);
    client.onConnected = () {
      _emit(generation, ControlTransportState.connected);
    };
    client.onAutoReconnect = () {
      _emit(generation, ControlTransportState.reconnecting);
    };
    client.onAutoReconnected = () {
      _emit(generation, ControlTransportState.connected);
    };
    client.onDisconnected = () {
      _emit(generation, ControlTransportState.reconnecting);
    };
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .authenticateAs(config.account, config.secret);
    _client = client;
    try {
      await client.connect();
    } catch (error) {
      client.disconnect();
      if (generation != _generation || _disposed) {
        throw const ConnectionException(
          'The connection attempt was superseded.',
        );
      }
      _emit(generation, ControlTransportState.disconnected);
      throw ConnectionException(
        'Could not connect to the control server.',
        error,
      );
    }
    if (generation != _generation || _disposed || !identical(_client, client)) {
      client.disconnect();
      throw const ConnectionException('The connection attempt was superseded.');
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final code = client.connectionStatus?.returnCode;
      client.disconnect();
      _emit(generation, ControlTransportState.disconnected);
      if (code == MqttConnectReturnCode.badUsernameOrPassword ||
          code == MqttConnectReturnCode.notAuthorized) {
        throw AuthenticationException(
          'The control server rejected the credentials.',
        );
      }
      throw ConnectionException(
        'The control server rejected the connection ($code).',
      );
    }

    for (final suffix in const ['presence', 'state', 'event', 'telemetry']) {
      client.subscribe('v1/devices/+/$suffix', MqttQos.atLeastOnce);
    }
    _updates = client.updates?.listen(
      (incoming) {
        if (generation == _generation && !_disposed) _onMessages(incoming);
      },
      onError: (Object error) {
        _emit(generation, ControlTransportState.reconnecting);
      },
    );
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> incoming) {
    for (final item in incoming) {
      final message = item.payload;
      if (message is! MqttPublishMessage) continue;
      final payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      _messages.add(ControlEnvelope(channel: item.topic, payload: payload));
    }
  }

  @override
  Future<void> send(String channel, String payload) async {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      throw const ConnectionException('The control server is not connected.');
    }
    final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
    final id = client.publishMessage(
      channel,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: false,
    );
    if (id < 0) {
      throw const ConnectionException('The command could not be sent.');
    }
  }

  @override
  Future<void> disconnect() async {
    _generation += 1;
    await _disconnectCurrent();
    if (!_disposed && !_states.isClosed) {
      _states.add(ControlTransportState.disconnected);
    }
  }

  Future<void> _disconnectCurrent() async {
    await _updates?.cancel();
    _updates = null;
    final client = _client;
    _client = null;
    client?.disconnect();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _disconnectCurrent();
    await _states.close();
    await _messages.close();
  }

  void _emit(int generation, ControlTransportState state) {
    if (generation == _generation && !_disposed && !_states.isClosed) {
      _states.add(state);
    }
  }
}

MqttClient _createSecureClient(String server, String clientId, int port) =>
    MqttServerClient.withPort(server, clientId, port)..secure = true;
