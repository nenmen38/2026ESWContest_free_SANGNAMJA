# PM2008M I2C component

ESP-IDF 6.0 이상에서 PM2008M을 읽는 C++ RAII 드라이버입니다. UART와
측정 모드 변경 명령은 지원하지 않습니다.

## 지원 범위

- 32바이트 프레임 수신
- Header `0x16`, length `32`, XOR checksum 검증
- GRIMM/TSI PM1.0, PM2.5, PM10 파싱
- 0.3, 0.5, 1.0, 2.5, 5.0, 10.0 um 입자 개수 파싱
- status, measurement mode, calibration raw 값 보존

## 하드웨어 연결

| PM2008M | 연결 |
| --- | --- |
| VCC | 5 V |
| GND | ESP32와 공통 접지 |
| SDA/SCL | 3.3 V pull-up이 있는 단일 I2C 버스 |
| CTL | LOW (I2C mode) |

PM2008M은 5 V 전원을 사용하지만 ESP32 GPIO는 5 V tolerant가 아닙니다.
SDA/SCL pull-up이 5 V인 모듈은 3.3 V 레벨 시프터를 사용하십시오.

## I2C 및 수명주기

- 7-bit 주소: `0x28`
- 클록: `100000 Hz` 이하
- 버스 생성/삭제: 상위 `SensorService` 소유
- PM2008M device handle: `Pm2008m` 소유
- 서비스 종료 순서: `Pm2008m::end()` 후 버스 삭제

```cpp
#include "pm2008m.hpp"

pm2008m::Pm2008m sensor;
pm2008m::Config config;
config.timeout_ms = 1000;
ESP_ERROR_CHECK(sensor.begin(application_bus, config));

pm2008m::Data data;
ESP_ERROR_CHECK(sensor.read(&data));
// data.grimm.pm1_0 / pm2_5 / pm10
// data.tsi.pm1_0 / pm2_5 / pm10
// data.particles.particles_0_3 ... particles_10_0
```

`read()`는 센서 I2C 오류를 그대로 반환하며, 잘못된 프레임은
`ESP_ERR_INVALID_RESPONSE`, 잘못된 XOR는 `ESP_ERR_INVALID_CRC`를 반환합니다.
PM2008M의 알려진 status 값은 해석하지 않고 raw 값으로 보존합니다.
