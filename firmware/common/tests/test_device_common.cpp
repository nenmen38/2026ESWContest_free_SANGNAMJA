#include "device_common.hpp"

#include <cassert>
#include <cstdint>

int main()
{
    int32_t steps = 0;
    assert(device_common::position100thsToSteps(0, -100, 900, &steps));
    assert(steps == -100);
    assert(device_common::position100thsToSteps(10000, -100, 900, &steps));
    assert(steps == 900);

    device_common::MotorCommand command;
    command.metadata.command_id = "id-1";
    command.metadata.received_at_ms = 100;
    command.metadata.ttl_ms = 1000;
    command.action = device_common::MotorCommandAction::SetPosition;
    command.position100ths = 2500;
    assert(device_common::validateMotorCommand(command, 1099, true) ==
           device_common::CommandValidationResult::Ok);
    assert(device_common::validateMotorCommand(command, 1100, true) ==
           device_common::CommandValidationResult::Expired);

    device_common::CommandDeduplicator deduplicator;
    assert(deduplicator.accept("id-1", 100, 1000));
    assert(!deduplicator.accept("id-1", 200, 1000));
    assert(deduplicator.accept("id-1", 1100, 1000));

    return 0;
}
