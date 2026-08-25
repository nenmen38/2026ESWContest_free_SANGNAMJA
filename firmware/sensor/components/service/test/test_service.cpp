#include "unity.h"
#include "unity_test_runner.h"

#include <limits>

#include "service.hpp"

namespace {

class FakeSensorService final : public SensorService {
public:
    using SensorService::sampleOnce;

    esp_err_t pm_result = ESP_OK;
    esp_err_t bme_result = ESP_OK;
    pm2008m::Data pm_value;
    bme280::Reading bme_value;

protected:
    esp_err_t readPm(pm2008m::Data* out_data) override
    {
        if (pm_result == ESP_OK) {
            *out_data = pm_value;
        }
        return pm_result;
    }

    esp_err_t readBme(bme280::Reading* out_reading) override
    {
        if (bme_result == ESP_OK) {
            *out_reading = bme_value;
        }
        return bme_result;
    }
};

}  // namespace

TEST_CASE("sensor service aggregates both successful sensor reads", "[service]")
{
    FakeSensorService service;
    service.pm_value.grimm.pm2_5 = 42;
    service.bme_value.temperature_c = 23.5f;
    service.bme_value.pressure_hpa = 1013.0f;

    SensorSnapshot snapshot;
    service.sampleOnce(&snapshot);

    TEST_ASSERT_EQUAL(ESP_OK, snapshot.raw.pm_status);
    TEST_ASSERT_EQUAL(ESP_OK, snapshot.raw.bme_status);
    TEST_ASSERT_TRUE(snapshot.pm_valid);
    TEST_ASSERT_TRUE(snapshot.bme_valid);
    TEST_ASSERT_EQUAL_UINT16(42, snapshot.raw.grimm_pm2_5);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 23.5f, snapshot.normalized.temperature_c);
    TEST_ASSERT_TRUE(snapshot.normalized.temperature_valid);
    TEST_ASSERT_EQUAL_UINT32(0, snapshot.error_flags);
    TEST_ASSERT_TRUE(snapshot.timestamp_us > 0);
    TEST_ASSERT_TRUE(snapshot.revision > 0);
}

TEST_CASE("PM failure does not discard a valid BME reading", "[service]")
{
    FakeSensorService service;
    service.pm_result = ESP_ERR_TIMEOUT;
    service.bme_value.humidity_percent = 55.0f;
    service.bme_value.pressure_hpa = 1013.0f;

    SensorSnapshot snapshot;
    service.sampleOnce(&snapshot);

    TEST_ASSERT_EQUAL(ESP_ERR_TIMEOUT, snapshot.raw.pm_status);
    TEST_ASSERT_EQUAL(ESP_OK, snapshot.raw.bme_status);
    TEST_ASSERT_FALSE(snapshot.pm_valid);
    TEST_ASSERT_TRUE(snapshot.bme_valid);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 55.0f, snapshot.normalized.humidity_percent);
    TEST_ASSERT_FALSE(snapshot.normalized.temperature_valid);
    TEST_ASSERT_TRUE((snapshot.error_flags & device_common::kSensorErrorPm) != 0);
}

TEST_CASE("BME failure does not discard a valid PM reading", "[service]")
{
    FakeSensorService service;
    service.bme_result = ESP_FAIL;
    service.pm_value.grimm.pm10 = 77;

    SensorSnapshot snapshot;
    service.sampleOnce(&snapshot);

    TEST_ASSERT_EQUAL(ESP_OK, snapshot.raw.pm_status);
    TEST_ASSERT_EQUAL(ESP_FAIL, snapshot.raw.bme_status);
    TEST_ASSERT_TRUE(snapshot.pm_valid);
    TEST_ASSERT_FALSE(snapshot.bme_valid);
    TEST_ASSERT_EQUAL_UINT16(77, snapshot.raw.grimm_pm10);
    TEST_ASSERT_TRUE((snapshot.error_flags & device_common::kSensorErrorBme) != 0);
}

TEST_CASE("invalid BME field is not marked valid", "[service]")
{
    FakeSensorService service;
    service.bme_value.temperature_c = std::numeric_limits<float>::quiet_NaN();
    service.bme_value.humidity_percent = 45.0f;
    service.bme_value.pressure_hpa = 1013.0f;

    SensorSnapshot snapshot;
    service.sampleOnce(&snapshot);

    TEST_ASSERT_FALSE(snapshot.normalized.temperature_valid);
    TEST_ASSERT_TRUE(snapshot.normalized.humidity_valid);
    TEST_ASSERT_TRUE(snapshot.normalized.pressure_valid);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 45.0f, snapshot.normalized.humidity_percent);
    TEST_ASSERT_TRUE((snapshot.error_flags & device_common::kSensorErrorBme) != 0);
}
