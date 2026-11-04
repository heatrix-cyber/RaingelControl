import Foundation
import CoreBluetooth

/// BLE implementation of the verified VC-BLELIGHT protocol.
/// RGB inputs are standard 0...255 and are mapped to the lamp's empirically verified 0...147 range.
enum LampBLE {
    static func setPower(_ on: Bool) async throws {
        try await BLETransaction.send(Data([0x01, on ? 0x01 : 0x00]))
    }

    static func sendRGB(red: Int, green: Int, blue: Int, brightness: Int) async throws {
        let scale = Double(max(1, min(100, brightness))) / 100.0
        func channel(_ value: Int) -> UInt8 {
            let standard = max(0, min(255, value))
            let lamp = Int((Double(standard) * 147.0 / 255.0 * scale).rounded())
            return UInt8(max(0, min(147, lamp)))
        }
        try await BLETransaction.send(Data([0x03, channel(red), channel(green), channel(blue)]))
    }
}

private final class BLETransaction: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let serviceUUID = CBUUID(string: "AE30")
    private static let characteristicUUID = CBUUID(string: "AE01")
    private static var active: BLETransaction?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var payload: Data?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: DispatchWorkItem?

    static func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let transaction = BLETransaction(payload: data, continuation: continuation)
            active = transaction
            transaction.central = CBCentralManager(delegate: transaction, queue: .main)
        }
    }

    private init(payload: Data, continuation: CheckedContinuation<Void, Error>) {
        self.payload = payload
        self.continuation = continuation
        super.init()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting {
                finish(.failure(NSError(domain: "RaingelBLE", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bluetooth is unavailable or turned off."])))
            }
            return
        }
        timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(NSError(domain: "RaingelBLE", code: 2, userInfo: [NSLocalizedDescriptionKey: "VC-BLELIGHT was not found. Keep the lamp powered on and nearby."])))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout!)
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard peripheral.name == "VC-BLELIGHT" || (advertisementData[CBAdvertisementDataLocalNameKey] as? String) == "VC-BLELIGHT" else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            finish(.failure(NSError(domain: "RaingelBLE", code: 3, userInfo: [NSLocalizedDescriptionKey: "Lamp service AE30 was not found."])))
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            finish(.failure(NSError(domain: "RaingelBLE", code: 4, userInfo: [NSLocalizedDescriptionKey: "Write characteristic AE01 was not found."])))
            return
        }
        self.characteristic = characteristic
        guard let payload else { finish(.failure(NSError(domain: "RaingelBLE", code: 5))); return }
        peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
        finish(.success(()))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(.failure(error ?? NSError(domain: "RaingelBLE", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not connect to lamp."])))
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        if central?.isScanning == true { central.stopScan() }
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        let callback = continuation
        continuation = nil
        callback?.resume(with: result)
        if Self.active === self { Self.active = nil }
    }
}
