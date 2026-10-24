#ifndef NAVIA_CONFIG_H
#define NAVIA_CONFIG_H

#include <Arduino.h>

// ==========================================
// PIN DEFINITIONS FOR ESP32-C3 SUPERMINI
// ==========================================
// Haptic Motor Outputs (via NPN Transistor Switching: 3.3V HIGH turns ON transistor)
#define MOTOR_LEFT_PIN     0    // GPIO 0: Left Vibration Motor (NPN Base)
#define MOTOR_RIGHT_PIN    1    // GPIO 1: Right Vibration Motor (NPN Base)

// I2C Bus for VL53L0X Time-of-Flight Sensor
#define I2C_SDA_PIN        7    // GPIO 7: I2C Data
#define I2C_SCL_PIN        6    // GPIO 6: I2C Clock

// ==========================================
// BLE GATT SERVICE & CHARACTERISTIC UUIDs
// ==========================================
#define BLE_DEVICE_NAME             "NAVIA-Wearable"
#define SERVICE_UUID                "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_RX      "beb5483e-36e1-4688-b7f5-ea07361b26a8" // Write: 'L', 'R', 'S'
#define CHARACTERISTIC_UUID_TX      "beb5483f-36e1-4688-b7f5-ea07361b26a8" // Notify: Obstacle Alerts

// ==========================================
// PROXIMITY & HAPTIC THRESHOLDS
// ==========================================
#define OBSTACLE_THRESHOLD_MM       700    // 70 cm proximity trigger limit
#define MIN_VALID_DISTANCE_MM       20     // Ignore sub-20mm noise/physical occlusions
#define TOF_POLL_INTERVAL_MS        50     // 20 Hz non-blocking sensor poll rate
#define HAZARD_DEBOUNCE_MS          1200   // Minimum interval between repeated hazard alarms

#endif // NAVIA_CONFIG_H
