# Status LED

Non-blocking driver for the single addressable RGB LED fitted to the target
ESP32-C3 SuperMini boards. The default is GPIO8, one WS2812-compatible pixel,
GRB byte order, and a 32/255 global brightness cap.

Five priority layers are available, from lowest to highest: device, network,
provisioning, resetting, and fault. The animation task refreshes at 20 Hz; API
calls only update desired state. The sensor image uses RMT. The motor image
uses SPI2 so FastAccelStepper retains the ESP32-C3 RMT resources.

Do not attach another peripheral to GPIO8 or, with the SPI backend selected,
to SPI2. GPIO8 is also an ESP32-C3 strapping pin. Verify the actual SuperMini
variant with the asynchronous red/green/blue startup test before enclosure
assembly.

