#include "pm2008m.hpp"

#include <cstddef>

namespace {

constexpr uint8_t kI2cAddress = 0x28;
constexpr uint32_t kI2cClockHz = 100000;
constexpr size_t kFrameSize = 32;
constexpr uint8_t kFrameHeader = 0x16;
constexpr uint8_t kFrameLength = 32;

uint16_t readU16Be(const uint8_t* bytes)
{
    return static_cast<uint16_t>((static_cast<uint16_t>(bytes[0]) << 8) | bytes[1]);
}

uint8_t checksum(const uint8_t* frame)
{
    uint8_t result = 0;
    for (size_t index = 0; index < kFrameSize - 1; ++index) {
        result ^= frame[index];
    }
    return result;
}

esp_err_t pm2008m_parse_frame(const uint8_t* frame, pm2008m::Data* data)
{
    if (frame == nullptr || data == nullptr) {
        return ESP_ERR_INVALID_ARG;
    }
    if (frame[0] != kFrameHeader || frame[1] != kFrameLength) {
        return ESP_ERR_INVALID_RESPONSE;
    }
    if (frame[kFrameSize - 1] != checksum(frame)) {
        return ESP_ERR_INVALID_CRC;
    }

    data->status = frame[2];
    data->measurement_mode = readU16Be(&frame[3]);
    data->calibration = readU16Be(&frame[5]);

    data->grimm.pm1_0 = readU16Be(&frame[7]);
    data->grimm.pm2_5 = readU16Be(&frame[9]);
    data->grimm.pm10 = readU16Be(&frame[11]);

    data->tsi.pm1_0 = readU16Be(&frame[13]);
    data->tsi.pm2_5 = readU16Be(&frame[15]);
    data->tsi.pm10 = readU16Be(&frame[17]);

    data->particles.particles_0_3 = readU16Be(&frame[19]);
    data->particles.particles_0_5 = readU16Be(&frame[21]);
    data->particles.particles_1_0 = readU16Be(&frame[23]);
    data->particles.particles_2_5 = readU16Be(&frame[25]);
    data->particles.particles_5_0 = readU16Be(&frame[27]);
    data->particles.particles_10_0 = readU16Be(&frame[29]);
    return ESP_OK;
}

}  // namespace

namespace pm2008m {

Pm2008m::~Pm2008m()
{
    (void)end();
}

esp_err_t Pm2008m::begin(i2c_master_bus_handle_t bus, const Config& config)
{
    if (bus == nullptr || config.timeout_ms == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    if (device_ != nullptr) {
        return ESP_OK;
    }

    const esp_err_t probe_ret = i2c_master_probe(bus, kI2cAddress, config.timeout_ms);
    if (probe_ret != ESP_OK) {
        return probe_ret;
    }

    i2c_device_config_t device_config = {};
    device_config.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    device_config.device_address = kI2cAddress;
    device_config.scl_speed_hz = kI2cClockHz;
    const esp_err_t add_ret = i2c_master_bus_add_device(bus, &device_config, &device_);
    if (add_ret != ESP_OK) {
        device_ = nullptr;
        return add_ret;
    }
    bus_ = bus;
    timeout_ms_ = config.timeout_ms;
    return ESP_OK;
}

esp_err_t Pm2008m::end()
{
    if (device_ == nullptr) {
        bus_ = nullptr;
        return ESP_OK;
    }

    const esp_err_t ret = i2c_master_bus_rm_device(device_);
    if (ret == ESP_OK) {
        device_ = nullptr;
        bus_ = nullptr;
    }
    return ret;
}

esp_err_t Pm2008m::read(Data* out_data)
{
    if (device_ == nullptr || out_data == nullptr) {
        return ESP_ERR_INVALID_STATE;
    }

    uint8_t frame[kFrameSize] = {};
    const esp_err_t ret = i2c_master_receive(device_, frame, sizeof(frame), timeout_ms_);
    if (ret != ESP_OK) {
        return ret;
    }
    return pm2008m_parse_frame(frame, out_data);
}

}  // namespace pm2008m
