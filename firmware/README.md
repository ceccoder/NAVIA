# NAVIA Wearable Firmware (ESP32-C3 SuperMini)

Firmware for the NAVIA tactile navigation wearable powered by the RISC-V **ESP32-C3 SuperMini** board with integrated Bluetooth 5.0 LE and I2C Time-of-Flight proximity sensing.

---

## Hardware Pinout & Wiring Specifications

### 1. Pin Assignment Table

| Function | ESP32-C3 Pin | Peripheral Component | Notes |
|---|---|---|---|
| **Left Haptic Motor** | `GPIO 0` | 2N2222 / SS8050 NPN Transistor Base | 1 kΩ base current-limiting resistor |
| **Right Haptic Motor**| `GPIO 1` | 2N2222 / SS8050 NPN Transistor Base | 1 kΩ base current-limiting resistor |
| **I2C SDA** | `GPIO 7` | VL53L0X ToF Data line | 3.3V logic level |
| **I2C SCL** | `GPIO 6` | VL53L0X ToF Clock line | 400 kHz fast I2C mode |
| **VCC** | `3V3` or `5V` | Sensor VDD & Motor positive rail | Regulated 3.3V from USB / LiPo |
| **GND** | `GND` | Common system ground | Star-ground topology recommended |

---

### 2. NPN Transistor Switching Circuit Diagram

```
                 +3.3V / +5V (VCC)
                      |
                      +----------+
                      |          |
                   +------+      |
                   | Coin |    [ - ] 1N4148 / 1N4001
                   | Motor|    [ + ] Flyback Diode (Inductive kickback protection)
                   +------+      |
                      |          |
                      +----------+
                      |
                 Collector
                   /
GPIO 0 / 1 ----[ 1kΩ ]--- Base (2N2222 / SS8050 NPN)
                   \
                  Emitter
                      |
                     GND
```

> **Why NPN Transistor Switching?**  
> Microcontroller GPIO pins on the ESP32-C3 are rated for a maximum source/sink current of ~20mA. Coin vibration motors draw between 60mA and 120mA at startup. Driving the motor through an NPN switching transistor with a flyback diode prevents MCU thermal overload and resets caused by inductive back-EMF spikes.

---

## 3. BLE GATT Specification

- **Device Name**: `NAVIA-Wearable`
- **Service UUID**: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- **RX Characteristic (Write)**: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
  - Accepts single ASCII command bytes:
    - `'L'`: Actuates Left Haptic Motor (GPIO 0) with a 2-pulse turn-left pattern.
    - `'R'`: Actuates Right Haptic Motor (GPIO 1) with a 2-pulse turn-right pattern.
    - `'S'`: Actuates Both Motors simultaneously with a 3-pulse urgent stop pattern.
- **TX Characteristic (Notify)**: `beb5483f-36e1-4688-b7f5-ea07361b26a8`
  - Dispatches obstacle warnings (e.g. `OBSTACLE:450 mm`) whenever the VL53L0X sensor detects an obstacle closer than 700 mm (70 cm).

---

## 4. Building and Flashing

### Using PlatformIO (Recommended)
```bash
cd firmware
pio run --target upload
pio device monitor -b 115200
```

### Using Arduino IDE
1. Install **ESP32 by Espressif Systems** via Boards Manager.
2. Select Board: **ESP32C3 Dev Module**.
3. Set **USB CDC On Boot**: Enabled.
4. Install library: **VL53L0X** by Pololu.
5. Compile and flash to the SuperMini COM port.
