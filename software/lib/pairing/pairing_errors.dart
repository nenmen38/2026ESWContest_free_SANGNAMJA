import 'package:esw_device_sdk/esw_device_sdk.dart';

String friendlySdkError(Object error) => switch (error) {
  final ProvisioningException value => switch (value.code) {
    ProvisioningFailureCode.permissionDenied =>
      'Bluetooth 또는 주변 기기 권한이 필요합니다. 설정에서 권한을 허용해 주세요.',
    ProvisioningFailureCode.deviceUnavailable =>
      '장치를 찾을 수 없습니다. 장치가 등록 대기 상태인지 확인해 주세요.',
    ProvisioningFailureCode.bleConnection =>
      '장치와 Bluetooth 연결에 실패했습니다. 가까이에서 다시 시도해 주세요.',
    ProvisioningFailureCode.incompatibleProtocol => '이 앱과 호환되지 않는 장치입니다.',
    ProvisioningFailureCode.wrongPop => '장치 인증 코드가 올바르지 않습니다.',
    ProvisioningFailureCode.wifiRejected => '장치가 Wi-Fi 설정을 거부했습니다.',
    ProvisioningFailureCode.wifiAuthentication => 'Wi-Fi 비밀번호를 확인해 주세요.',
    ProvisioningFailureCode.wifiNotFound => '선택한 Wi-Fi를 장치가 찾지 못했습니다.',
    ProvisioningFailureCode.disconnected => '설정 중 장치 연결이 끊어졌습니다. 다시 시도해 주세요.',
    ProvisioningFailureCode.timeout => '장치 응답 시간이 초과되었습니다. 다시 시도해 주세요.',
  },
  AuthenticationException() => '계정 또는 비밀번호가 올바르지 않습니다.',
  ConnectionException() => '제어 서비스에 연결할 수 없습니다. 네트워크를 확인해 주세요.',
  DeviceAvailabilityTimeoutException() =>
    'Wi-Fi 연결 후 장치 상태를 확인하지 못했습니다. 장치 전원을 확인한 뒤 다시 시도해 주세요.',
  final EswSdkException value => value.message,
  final StateError value => value.message,
  _ => '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
};
