# Public API

이 문서는 `package:esw_device_sdk/esw_device_sdk.dart`를 통해 앱 코드에
공개되는 API만 정리한다. `lib/src/**` 경로의 타입과 함수는 패키지 내부
구현이며, 테스트 하네스나 전송 계층 검증처럼 패키지 내부 테스트가 필요한
경우를 제외하고 앱에서 직접 import하지 않는다.

## 공개 진입점

앱은 다음 import만 사용한다.

```dart
import 'package:esw_device_sdk/esw_device_sdk.dart';
```

배럴 파일이 공개하는 범위는 다음과 같다.

- 전체 공개: `errors.dart`, `device_setup.dart`, `models.dart`
- 제한 공개: `ProvisioningQrPayload`
- 제한 공개: `EswDeviceSdk`, `MotorController`

`protocol.dart`, `control_transport.dart`, `mqtt_control_transport.dart`,
`provisioning.dart`, `provisioning_workflow.dart`, `ble_prov_transport.dart`,
`SdkTestHarness`는 공개 API가 아니다.

## SDK 수명 주기

### `EswDeviceSdk`

상위 앱이 생성하고 앱 수명 동안 유지하는 SDK facade다.

| 멤버 | 역할 | 주요 조건 |
| --- | --- | --- |
| `factory EswDeviceSdk()` | 프로덕션 MQTT 제어 전송과 BLE 프로비저닝 어댑터로 SDK를 생성한다. | 앱은 내부 전송 타입을 알 필요가 없다. |
| `currentState` | 최신 원자적 SDK 상태를 즉시 반환한다. | 초기값은 연결 끊김과 빈 장치 목록이다. |
| `states` | 상태 변경 스트림을 제공한다. | 모든 구독자는 먼저 `currentState`를 받는다. |
| `errors` | 복구 가능한 백그라운드 오류 스트림이다. | 잘못된 장치 데이터, 연결, 인증, 프로비저닝 오류가 전달된다. |
| `connect(EswConnectionConfig config)` | 보안 제어 서버에 연결하고 자동 발견을 시작한다. | 설정 검증 실패 시 `ArgumentError`를 던진다. |
| `disconnect()` | SDK를 폐기하지 않고 연결만 끊는다. | 기존 장치 도메인 데이터는 유지하되 오프라인으로 표시한다. |
| `motor(String deviceId)` | 특정 모터의 명령 전용 컨트롤러를 반환한다. | `motor-` 접두사가 아니면 `ArgumentError`를 던진다. |
| `discoverSetupDevices({Duration timeout})` | 주변 설정 가능 BLE 장치를 검색한다. | 기본 제한 시간은 8초다. |
| `startDeviceSetup(ProvisioningQrPayload qr, {Duration scanTimeout})` | QR에 지정된 BLE 장치를 찾아 설정 세션을 만든다. | 장치를 찾지 못하면 `ProvisioningException`을 던진다. |
| `startManualDeviceSetup({SetupDevice device, String pop})` | 수동 선택 장치와 PoP로 설정 세션을 만든다. | 빈 PoP는 `ProvisioningException`을 던진다. |
| `dispose()` | 전송, 프로비저닝, 스트림, 대기 중 명령을 정리한다. | 멱등적이며 호출 후 SDK와 세션은 사용할 수 없다. |

동일한 서버, 포트, 계정으로 재연결하면 장치 레지스트리는 유지된다. 다른
연결 범위로 연결하면 이전 계정의 장치 데이터가 노출되지 않도록 장치 목록과
대기 중 명령을 비운다.

### `EswConnectionConfig`

런타임 제어 서버 접속 설정이다.

| 필드 | 설명 |
| --- | --- |
| `server` | URI scheme이 없는 DNS 이름 또는 IP 주소 |
| `port` | 보안 서비스 포트, 기본값 `8883` |
| `account` | 제어 서버 운영자가 발급한 계정 |
| `secret` | 제어 서버 운영자가 발급한 비밀값 |

`validate()`는 빈 서버, URI scheme 포함 서버, 범위를 벗어난 포트, 빈 계정
또는 빈 비밀값을 거부한다. SDK는 이 값을 저장하지 않으며 보안 저장과 삭제
정책은 호스트 앱 책임이다.

## 상태 모델

### 연결과 장치

| API | 설명 |
| --- | --- |
| `EswConnectionState` | `disconnected`, `connecting`, `connected`, `reconnecting` |
| `EswDeviceKind` | `motor`, `airQualitySensor` |
| `EswSdkState` | 현재 연결 상태와 정렬된 불변 장치 스냅샷 목록 |
| `EswDeviceSnapshot` | 모든 장치 스냅샷의 공통 기반 타입 |
| `MotorDeviceSnapshot` | 모터 장치 스냅샷, `latestState` 포함 |
| `AirQualityDeviceSnapshot` | 공기질 장치 스냅샷, `latestReading` 포함 |

`EswDeviceSnapshot`은 sealed class다. 앱에서는 `switch` 패턴 매칭으로
`MotorDeviceSnapshot`과 `AirQualityDeviceSnapshot`을 분기하는 사용 방식이
권장된다.

### 모터 상태

| API | 설명 |
| --- | --- |
| `MotorMainState` | `unknown`, `idle`, `opening`, `closing`, `ventilating`, `stopping`, `fault` |
| `MotorState` | 모터 동작 상태, 현재/목표 위치, 위치 신뢰 여부, 오류 플래그, revision |
| `MotorState.hasError` | `errorFlags != 0`이면 `true` |

`currentPositionPercent`는 위치가 유효하지 않을 때 `null`이다.
`targetPositionPercent`는 0부터 100까지의 백분율 값이다. 실제 안전성,
이동 범위와 위치 피드백 판단은 펌웨어가 최종 권한을 가진다.

### 공기질 상태

| API | 설명 |
| --- | --- |
| `AirQualityLevel` | `unknown`, `good`, `moderate`, `unhealthy`, `veryUnhealthy` |
| `AirQualityReading` | 앱에서 바로 표시할 수 있는 온도, 습도, 압력, PM, 품질 등급, 수신 시각, 장치 타임스탬프, revision, 오류 플래그, 원시값 |
| `AirQualityRaw` | PM2008M과 BME280에서 보고한 세부 원시 필드 |
| `AirQualityReading.hasSensorError` | `errorFlags != 0`이면 `true` |

정규화된 값이 장치에서 invalid로 표시되면 해당 필드는 `null`이다. 앱은
임의로 0으로 치환하지 말고 `hasSensorError`, `errorFlags`, `raw`를 함께
확인한다.

## 모터 명령 API

### `MotorController`

특정 모터에 대한 명령 전용 인터페이스다. 상태는 컨트롤러가 아니라
`EswDeviceSdk.currentState` 또는 `EswDeviceSdk.states`에서 읽는다.

| 메서드 | 명령 |
| --- | --- |
| `open()` | 완전 열림 요청 |
| `close()` | 완전 닫힘 요청 |
| `stop()` | 정지 요청 |
| `ventilate()` | 펌웨어 설정 환기 위치로 이동 |
| `setPosition({required double percent})` | 지정 위치로 이동 |

모든 명령은 `Future<CommandResult>`를 반환한다. 오프라인 장치에는 I/O를
수행하지 않고 `deviceOffline`을 반환한다. 명령 이벤트는 SDK가 생성한
command ID와 대상 device ID가 모두 일치해야 완료된다. 일치하는 결과가
5초 안에 도착하지 않으면 `timeout`이다.

`setPosition`의 `percent`는 유한한 0 이상 100 이하 값이어야 한다. 검증에
실패하면 전송 전에 `ArgumentError`를 던진다.

### `CommandResult`

| API | 설명 |
| --- | --- |
| `CommandStatus.accepted` | 장치가 명령을 수락함 |
| `CommandStatus.deviceOffline` | 장치가 현재 도달 불가 |
| `CommandStatus.feedbackUnavailable` | 최신 위치 피드백 미확립 |
| `CommandStatus.positionUnknown` | 위치 피드백 미확립 |
| `CommandStatus.hardwareRejected` | 모터 하드웨어 거부 |
| `CommandStatus.invalidCommand` | 유효하지 않거나 지원하지 않는 명령 |
| `CommandStatus.duplicateCommand` | 이미 처리한 명령 ID |
| `CommandStatus.timeout` | SDK 제한 시간 내 상관 결과 미수신 |
| `revision` | 결과와 연결된 장치 revision, 없으면 `null` |
| `isAccepted` | `status == accepted` 편의 getter |

## 장치 추가 API

### QR 경로

```dart
final qr = ProvisioningQrPayload.parse(scannedQrText);
final setup = await sdk.startDeviceSetup(qr);
final networks = await setup.scanWifi();
final result = await setup.complete(
  network: networks.first,
  password: userEnteredWifiPassword,
);
```

`ProvisioningQrPayload.parse`는 ESP provisioning v1 JSON, BLE transport,
`PROV-MOTOR-0000` 또는 `PROV-SENSOR-0000` 형식의 서비스 이름, 비어 있지
않은 PoP를 검증한다. 1024자를 초과하거나 지원하지 않는 payload는
`FormatException`을 던진다.

### 수동 경로

```dart
final devices = await sdk.discoverSetupDevices();
final setup = sdk.startManualDeviceSetup(
  device: devices.first,
  pop: userEnteredPop,
);
```

`SetupDevice`는 `id`, `name`, `rssi`를 가진다. `id`는 선택 유지를 위한
플랫폼별 BLE 식별자이고, `name`은 장치 라벨에 인쇄된 provisioning service
name이다.

### `DeviceSetup`

| 멤버 | 설명 |
| --- | --- |
| `device` | 이 설정 세션이 대상으로 삼는 `SetupDevice` |
| `scanWifi()` | 짧은 BLE Security 1 세션으로 장치 주변 Wi-Fi 목록을 검색 |
| `complete({network, password, onProgress, availabilityTimeout})` | Wi-Fi를 적용하고 제어 서버에서 새 도메인 데이터를 기다림 |

`SetupWifiNetwork`는 `ssid`, `rssi`, `bssid`, `isPrivate`를 가진다.
`DeviceSetupResult`는 준비된 `EswDeviceSnapshot`과 선택적 `deviceIp`를
반환한다.

`complete` 진행 단계는 다음 순서로 보고된다.

```text
connecting -> checkingProtocol -> securing -> applyingWifi
  -> waitingForWifi -> waitingForDevice -> completed
```

기본 장치 가용성 제한 시간은 20초다. Wi-Fi 연결 후 일치하는 장치의 새
모터 상태 또는 센서 reading이 도착해야 완료된다. presence만으로는 완료되지
않는다. 한 SDK 인스턴스에서는 검색, Wi-Fi 스캔, 완료 작업 중 하나만 동시에
실행할 수 있다.

## 오류 API

| API | 설명 |
| --- | --- |
| `EswSdkException` | SDK 오류의 기반 sealed class, `message`와 선택적 `cause` 포함 |
| `ConnectionException` | 제어 서버 접속 실패 또는 연결 손실 |
| `AuthenticationException` | 서버 또는 provisioning 자격 증명 거부 |
| `DeviceAvailabilityTimeoutException` | Wi-Fi 설정 후 장치 도메인 데이터 미수신 |
| `ProvisioningException` | BLE 발견 또는 장치 provisioning 실패, `code` 포함 |
| `ProvisioningFailureCode` | `permissionDenied`, `deviceUnavailable`, `bleConnection`, `incompatibleProtocol`, `wrongPop`, `wifiRejected`, `wifiAuthentication`, `wifiNotFound`, `disconnected`, `timeout` |
| `DeviceDataException` | 장치가 잘못되었거나 호환되지 않는 프로토콜 데이터를 제공 |

복구 가능한 백그라운드 오류는 `EswDeviceSdk.errors`에서 관찰한다. 명령
결과처럼 도메인 흐름에 속한 실패는 가능한 경우 `CommandResult`나 명시적
예외로 반환된다.

## 공개 경계 유지 규칙

- 앱 코드는 `package:esw_device_sdk/esw_device_sdk.dart`만 import한다.
- 새 공개 타입은 배럴 export, Dartdoc, 단위 테스트, 예제 사용 경로를 함께
  추가한다.
- MQTT topic, payload JSON, QoS, retained 여부, BLE transport 구현 타입은
  공개하지 않는다.
- 공개 상태 객체는 불변 snapshot으로 유지한다.
- 모터 제어는 상태 객체가 아니라 `MotorController` 명령으로만 노출한다.
- 계정 발급, 자격 증명 저장, 사용자 확인 UI, 현지화는 SDK가 아니라 호스트
  앱 책임으로 둔다.
