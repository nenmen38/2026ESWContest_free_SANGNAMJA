#include <cstring>

#include "unity.h"
#include "unity_test_runner.h"

/* Include the implementation so its pure frame parser can be unit tested. */
#include "../pm2008m.cpp"

static void makeValidFrame(uint8_t frame[32])
{
    const uint8_t values[31] = {
        0x16, 0x20, 0x80, 0x12, 0x34, 0x56, 0x78,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
        0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
        0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12,
        0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    };

    std::memcpy(frame, values, sizeof(values));
    frame[31] = checksum(frame);
}

TEST_CASE("PM2008M parses a valid measurement frame", "[pm2008m]")
{
    uint8_t frame[32];
    pm2008m::Data data;
    makeValidFrame(frame);

    TEST_ASSERT_EQUAL(ESP_OK, pm2008m_parse_frame(frame, &data));

    TEST_ASSERT_EQUAL_HEX8(0x80, data.status);
    TEST_ASSERT_EQUAL_HEX16(0x1234, data.measurement_mode);
    TEST_ASSERT_EQUAL_HEX16(0x5678, data.calibration);

    TEST_ASSERT_EQUAL_HEX16(0x0102, data.grimm.pm1_0);
    TEST_ASSERT_EQUAL_HEX16(0x0304, data.grimm.pm2_5);
    TEST_ASSERT_EQUAL_HEX16(0x0506, data.grimm.pm10);
    TEST_ASSERT_EQUAL_HEX16(0x0708, data.tsi.pm1_0);
    TEST_ASSERT_EQUAL_HEX16(0x090a, data.tsi.pm2_5);
    TEST_ASSERT_EQUAL_HEX16(0x0b0c, data.tsi.pm10);

    TEST_ASSERT_EQUAL_HEX16(0x0d0e, data.particles.particles_0_3);
    TEST_ASSERT_EQUAL_HEX16(0x0f10, data.particles.particles_0_5);
    TEST_ASSERT_EQUAL_HEX16(0x1112, data.particles.particles_1_0);
    TEST_ASSERT_EQUAL_HEX16(0x1314, data.particles.particles_2_5);
    TEST_ASSERT_EQUAL_HEX16(0x1516, data.particles.particles_5_0);
    TEST_ASSERT_EQUAL_HEX16(0x1718, data.particles.particles_10_0);
}

TEST_CASE("PM2008M rejects an invalid header", "[pm2008m]")
{
    uint8_t frame[32];
    pm2008m::Data data;
    makeValidFrame(frame);
    frame[0] = 0x00;

    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_RESPONSE, pm2008m_parse_frame(frame, &data));
}

TEST_CASE("PM2008M rejects an invalid length", "[pm2008m]")
{
    uint8_t frame[32];
    pm2008m::Data data;
    makeValidFrame(frame);
    frame[1] = 0x1f;

    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_RESPONSE, pm2008m_parse_frame(frame, &data));
}

TEST_CASE("PM2008M rejects an invalid checksum", "[pm2008m]")
{
    uint8_t frame[32];
    pm2008m::Data data;
    makeValidFrame(frame);
    frame[31] ^= 0xff;

    TEST_ASSERT_EQUAL(ESP_ERR_INVALID_CRC, pm2008m_parse_frame(frame, &data));
}
