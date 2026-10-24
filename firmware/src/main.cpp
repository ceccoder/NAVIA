/**
 * NAVIA Wearable Firmware
 * Target: ESP32-C3 SuperMini (RISC-V)
 * Peripherals: Dual NPN-switched Haptic Motors & VL53L0X Time-of-Flight Sensor
 * Protocols: BLE 5.0 GATT Server & I2C
 */

#include <Arduino.h>
#include <Wire.h>
#include <VL53L0X.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "config.h"

// ==========================================
// GLOBALS & OBJECT INSTANCES
// ==========================================
VL53L0X tofSensor;
bool tofInitialized = false;

BLEServer* pServer = nullptr;
BLECharacteristic* pRxCharacteristic = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// ==========================================
// NON-BLOCKING HAPTIC STATE MACHINE
// ==========================================
struct HapticEngine {
    bool active;
    bool motorLeft;
    bool motorRight;
    uint8_t totalCycles;
    uint8_t currentCycle;
    bool isHigh;
    uint32_t onDurationMs;
    uint32_t offDurationMs;
    uint32_t lastTransitionMs;
} haptics = {false, false, false, 0, 0, false, 0, 0, 0};

void triggerHapticPattern(char cmd) {
    haptics.active = true;
    haptics.isHigh = true;
    haptics.currentCycle = 0;
    haptics.lastTransitionMs = millis();

    switch (cmd) {
        case 'L': // Turn Left: 2 distinct pulses on Left Motor (GPIO 0)
            haptics.motorLeft = true;
            haptics.motorRight = false;
            haptics.onDurationMs = 200;
            haptics.offDurationMs = 120;
            haptics.totalCycles = 2;
            Serial.println("[HAPTIC] Actuating Left Motor (GPIO 0) - Turn Left");
            break;

        case 'R': // Turn Right: 2 distinct pulses on Right Motor (GPIO 1)
            haptics.motorLeft = false;
            haptics.motorRight = true;
            haptics.onDurationMs = 200;
            haptics.offDurationMs = 120;
            haptics.totalCycles = 2;
            Serial.println("[HAPTIC] Actuating Right Motor (GPIO 1) - Turn Right");
            break;

        case 'S': // Emergency Stop / Hazard: 3 rapid bursts on Both Motors
        default:
            haptics.motorLeft = true;
            haptics.motorRight = true;
            haptics.onDurationMs = 120;
            haptics.offDurationMs = 80;
            haptics.totalCycles = 3;
            Serial.println("[HAPTIC] Actuating Both Motors (GPIO 0 & 1) - STOP / HAZARD");
            break;
    }

    // Apply initial HIGH state via NPN transistor base
    if (haptics.motorLeft) digitalWrite(MOTOR_LEFT_PIN, HIGH);
    if (haptics.motorRight) digitalWrite(MOTOR_RIGHT_PIN, HIGH);
}

void updateHaptics() {
    if (!haptics.active) return;

    uint32_t now = millis();
    uint32_t elapsed = now - haptics.lastTransitionMs;

    if (haptics.isHigh && elapsed >= haptics.onDurationMs) {
        // Transition from ON to OFF
        if (haptics.motorLeft) digitalWrite(MOTOR_LEFT_PIN, LOW);
        if (haptics.motorRight) digitalWrite(MOTOR_RIGHT_PIN, LOW);
        haptics.isHigh = false;
        haptics.lastTransitionMs = now;
        haptics.currentCycle++;

        if (haptics.currentCycle >= haptics.totalCycles) {
            haptics.active = false;
        }
    } else if (!haptics.isHigh && elapsed >= haptics.offDurationMs) {
        // Transition from OFF to ON for next cycle
        if (haptics.motorLeft) digitalWrite(MOTOR_LEFT_PIN, HIGH);
        if (haptics.motorRight) digitalWrite(MOTOR_RIGHT_PIN, HIGH);
        haptics.isHigh = true;
        haptics.lastTransitionMs = now;
    }
}

// ==========================================
// BLE CALLBACKS
// ==========================================
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* server) override {
        deviceConnected = true;
        Serial.println("[BLE] Mobile client connected to NAVIA-Wearable");
    }

    void onDisconnect(BLEServer* server) override {
        deviceConnected = false;
        Serial.println("[BLE] Mobile client disconnected");
    }
};

class RxCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pChar) override {
        String rxValue = pChar->getValue().c_str();

        if (rxValue.length() > 0) {
            char command = rxValue[0];
            Serial.printf("[BLE RX] Received Command: '%c'\n", command);

            if (command == 'L' || command == 'R' || command == 'S') {
                triggerHapticPattern(command);
            } else {
                Serial.printf("[BLE RX] Unknown command byte: '%c'\n", command);
            }
        }
    }
};

// ==========================================
// HARDWARE INITIALIZATION
// ==========================================
void setup() {
    // USB CDC Serial initialization
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n====================================");
    Serial.println("  NAVIA Wearable Controller v1.0.0  ");
    Serial.println("  ESP32-C3 SuperMini + BLE + ToF   ");
    Serial.println("====================================");

    // 1. Configure Haptic Motor Outputs (NPN switching logic)
    pinMode(MOTOR_LEFT_PIN, OUTPUT);
    pinMode(MOTOR_RIGHT_PIN, OUTPUT);
    digitalWrite(MOTOR_LEFT_PIN, LOW);
    digitalWrite(MOTOR_RIGHT_PIN, LOW);

    // Initial hardware power-on confirmation vibration
    digitalWrite(MOTOR_LEFT_PIN, HIGH);
    digitalWrite(MOTOR_RIGHT_PIN, HIGH);
    delay(100);
    digitalWrite(MOTOR_LEFT_PIN, LOW);
    digitalWrite(MOTOR_RIGHT_PIN, LOW);

    // 2. Configure I2C bus for VL53L0X ToF Proximity Sensor
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(400000); // 400 kHz fast mode

    tofSensor.setTimeout(500);
    if (!tofSensor.init()) {
        Serial.println("[ERROR] Failed to detect and initialize VL53L0X ToF sensor!");
        tofInitialized = false;
    } else {
        tofInitialized = true;
        tofSensor.startContinuous(50); // Continuous sampling every 50ms
        Serial.println("[OK] VL53L0X Time-of-Flight sensor online at I2C (SDA=7, SCL=6)");
    }

    // 3. Initialize BLE 5.0 GATT Server
    BLEDevice::init(BLE_DEVICE_NAME);
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);

    // RX Characteristic (Mobile Phone -> ESP32 Commands: 'L', 'R', 'S')
    pRxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_RX,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pRxCharacteristic->setCallbacks(new RxCallbacks());

    // TX Characteristic (ESP32 -> Mobile Phone: Proximity & Obstacle Alerts)
    pTxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_TX,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pTxCharacteristic->addDescriptor(new BLE2902());

    pService->start();

    // Start BLE Advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[OK] BLE Advertising started as 'NAVIA-Wearable'");
}

// ==========================================
// NON-BLOCKING MAIN LOOP
// ==========================================
void loop() {
    uint32_t currentMillis = millis();
    static uint32_t lastTofCheck = 0;
    static uint32_t lastHazardAlertTime = 0;

    // 1. Advance non-blocking haptic pulse timings
    updateHaptics();

    // 2. Poll Time-of-Flight sensor for immediate proximity obstacles
    if (tofInitialized && (currentMillis - lastTofCheck >= TOF_POLL_INTERVAL_MS)) {
        lastTofCheck = currentMillis;

        uint16_t distanceMm = tofSensor.readRangeContinuousMillimeters();

        if (tofSensor.timeoutOccurred()) {
            Serial.println("[WARN] ToF read timeout");
        } else if (distanceMm > MIN_VALID_DISTANCE_MM && distanceMm < OBSTACLE_THRESHOLD_MM) {
            // Obstacle closer than 70 cm!
            if (currentMillis - lastHazardAlertTime >= HAZARD_DEBOUNCE_MS) {
                lastHazardAlertTime = currentMillis;
                Serial.printf("[PROXIMITY ALERT] Obstacle detected at %u mm (< 700mm)!\n", distanceMm);

                // A) Trigger local emergency haptic pattern (Stop / Warning)
                triggerHapticPattern('S');

                // B) Notify connected mobile application over BLE
                if (deviceConnected && pTxCharacteristic != nullptr) {
                    char alertBuffer[32];
                    snprintf(alertBuffer, sizeof(alertBuffer), "OBSTACLE:%u mm", distanceMm);
                    pTxCharacteristic->setValue(alertBuffer);
                    pTxCharacteristic->notify();
                    Serial.printf("[BLE TX] Dispatched obstacle notification: %s\n", alertBuffer);
                }
            }
        }
    }

    // 3. Handle BLE advertising restarts upon client disconnect
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // Give the bluetooth stack a chance to prepare
        pServer->startAdvertising();
        Serial.println("[BLE] Restarted advertising");
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
}
