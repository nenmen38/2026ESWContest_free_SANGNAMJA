import 'dart:async';

// ignore_for_file: public_member_api_docs

import 'models.dart';

enum ControlTransportState { disconnected, connecting, connected, reconnecting }

final class ControlEnvelope {
  const ControlEnvelope({required this.channel, required this.payload});

  final String channel;
  final String payload;
}

abstract interface class ControlTransport {
  Stream<ControlTransportState> get states;
  Stream<ControlEnvelope> get messages;

  Future<void> connect(EswConnectionConfig config);
  Future<void> disconnect();
  Future<void> send(String channel, String payload);
  Future<void> dispose();
}
