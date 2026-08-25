// ignore_for_file: public_member_api_docs

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createMqttClient({
  required String server,
  required String clientId,
  required int port,
}) {
  final client = MqttServerClient.withPort(server, clientId, port);
  client.secure = true;
  return client;
}
