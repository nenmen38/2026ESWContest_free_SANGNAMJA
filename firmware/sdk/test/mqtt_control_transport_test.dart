// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:esw_device_sdk/src/control_transport.dart';
import 'package:esw_device_sdk/src/mqtt_control_transport.dart';
import 'package:mqtt_client/mqtt_client.dart' hide ConnectionException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a newer connect supersedes stale callbacks and subscriptions',
    () async {
      final clients = <_FakeMqttClient>[];
      final transport = MqttControlTransport(
        createClient: (server, clientId, port) {
          final client = _FakeMqttClient(server, clientId, port);
          clients.add(client);
          return client;
        },
      );
      addTearDown(transport.dispose);
      final states = <ControlTransportState>[];
      final subscription = transport.states.listen(states.add);
      addTearDown(subscription.cancel);

      final first = transport.connect(_config);
      final firstExpectation = expectLater(
        first,
        throwsA(isA<ConnectionException>()),
      );
      await _settle();
      final second = transport.connect(_config);
      await _settle();
      clients.last.completeConnect();

      await firstExpectation;
      await second;
      final connectedCount = states
          .where((state) => state == ControlTransportState.connected)
          .length;
      clients.first.onConnected?.call();
      await _settle();

      expect(states.last, ControlTransportState.connected);
      expect(
        states.where((state) => state == ControlTransportState.connected),
        hasLength(connectedCount),
      );
      expect(clients.first.subscribeCalls, 0);
      expect(clients.last.subscribeCalls, 4);
    },
  );

  test('disconnect supersedes an in-flight connect', () async {
    late _FakeMqttClient client;
    final transport = MqttControlTransport(
      createClient: (server, clientId, port) =>
          client = _FakeMqttClient(server, clientId, port),
    );
    addTearDown(transport.dispose);

    final connecting = transport.connect(_config);
    final connectingExpectation = expectLater(
      connecting,
      throwsA(isA<ConnectionException>()),
    );
    await _settle();
    await transport.disconnect();

    await connectingExpectation;
    expect(client.disconnected, isTrue);
  });

  test('dispose supersedes an in-flight connect', () async {
    late _FakeMqttClient client;
    final transport = MqttControlTransport(
      createClient: (server, clientId, port) =>
          client = _FakeMqttClient(server, clientId, port),
    );

    final connecting = transport.connect(_config);
    final connectingExpectation = expectLater(
      connecting,
      throwsA(isA<ConnectionException>()),
    );
    await _settle();
    await transport.dispose();

    await connectingExpectation;
    expect(client.disconnected, isTrue);
  });
}

const _config = EswConnectionConfig(
  server: 'control.example.com',
  account: 'app',
  secret: 'secret',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _FakeMqttClient extends MqttClient {
  // ignore: use_super_parameters
  _FakeMqttClient(String server, String clientId, int port)
    : super.withPort(server, clientId, port);

  final _status = MqttClientConnectionStatus();
  final _connect = Completer<MqttClientConnectionStatus?>();
  final _updates = StreamController<List<MqttReceivedMessage<MqttMessage>>>();
  int subscribeCalls = 0;
  bool disconnected = false;

  @override
  MqttClientConnectionStatus get connectionStatus => _status;

  @override
  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates => _updates.stream;

  @override
  Future<MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) => _connect.future;

  void completeConnect() {
    _status.state = MqttConnectionState.connected;
    onConnected?.call();
    if (!_connect.isCompleted) _connect.complete(_status);
  }

  @override
  Subscription? subscribe(String topic, MqttQos qosLevel) {
    subscribeCalls += 1;
    return null;
  }

  @override
  void disconnect() {
    disconnected = true;
    _status.state = MqttConnectionState.disconnected;
    if (!_connect.isCompleted) _connect.complete(_status);
    onDisconnected?.call();
  }
}
