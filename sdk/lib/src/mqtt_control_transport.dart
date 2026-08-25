// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart' hide ConnectionException;

import 'control_transport.dart';
import 'errors.dart';
import 'models.dart';
import 'mqtt_client_factory_native.dart' as mqtt_factory;

final class MqttControlTransport implements ControlTransport {
  final _states = StreamController<ControlTransportState>.broadcast();
  final _messages = StreamController<ControlEnvelope>.broadcast();
  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  bool _intentionalDisconnect = false;

  @override
  Stream<ControlTransportState> get states => _states.stream;

  @override
  Stream<ControlEnvelope> get messages => _messages.stream;

  @override
  Future<void> connect(EswConnectionConfig config) async {
    config.validate();
    await disconnect();
    _intentionalDisconnect = false;
    _states.add(ControlTransportState.connecting);
    final clientId =
        'flutter-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
        '${Random.secure().nextInt(1 << 20).toRadixString(36)}';
    final client = mqtt_factory.createMqttClient(
      server: config.server,
      clientId: clientId,
      port: config.port,
    );
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.logging(on: false);
    client.onConnected = () {
      _states.add(ControlTransportState.connected);
    };
    client.onAutoReconnect = () {
      _states.add(ControlTransportState.reconnecting);
    };
    client.onAutoReconnected = () {
      _states.add(ControlTransportState.connected);
    };
    client.onDisconnected = () {
      _states.add(
        _intentionalDisconnect
            ? ControlTransportState.disconnected
            : ControlTransportState.reconnecting,
      );
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
      _states.add(ControlTransportState.disconnected);
      throw ConnectionException(
        'Could not connect to the control server.',
        error,
      );
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final code = client.connectionStatus?.returnCode;
      client.disconnect();
      _states.add(ControlTransportState.disconnected);
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
      _onMessages,
      onError: (Object error) {
        _states.add(ControlTransportState.reconnecting);
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
    _intentionalDisconnect = true;
    await _updates?.cancel();
    _updates = null;
    _client?.disconnect();
    _client = null;
    if (!_states.isClosed) _states.add(ControlTransportState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _states.close();
    await _messages.close();
  }
}
