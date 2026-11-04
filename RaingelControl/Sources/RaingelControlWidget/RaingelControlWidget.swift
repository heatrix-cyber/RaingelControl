import AppIntents
import SwiftUI
import WidgetKit
import CoreBluetooth

struct RaingelPowerIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Set Raingel Power"
    @Parameter(title: "Power") var value: Bool

    func perform() async throws -> some IntentResult {
        try await LampBLEForWidget.setPower(value)
        return .result()
    }
}

struct OpenRaingelColoursIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Raingel Colours"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

struct RaingelControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.RaingelControl.power") {
            ControlWidgetToggle("Raingel", isOn: false, action: RaingelPowerIntent()) { isOn in
                Label(isOn ? "Lamp On" : "Lamp Off", systemImage: "lightbulb")
            }
        }
        .displayName("Raingel Power")
        .description("Turn your Raingel RGB lamp on or off.")
    }
}

struct RaingelColoursControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.RaingelControl.colours") {
            ControlWidgetButton(action: OpenRaingelColoursIntent()) {
                Label("Lamp Colours", systemImage: "paintpalette")
            }
        }
        .displayName("Raingel Colours")
        .description("Open the Raingel colour picker.")
    }
}

@main
struct RaingelControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaingelControlWidget()
        RaingelColoursControlWidget()
    }
}

// Kept in the widget extension because App Intents execute in that process.
private enum LampBLEForWidget {
    static func setPower(_ on: Bool) async throws {
        try await WidgetBLEWrite.send(Data([0x01, on ? 0x01 : 0x00]))
    }
}

private final class WidgetBLEWrite: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static var current: WidgetBLEWrite?
    private let data: Data
    private var continuation: CheckedContinuation<Void, Error>?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var timeout: DispatchWorkItem?

    static func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { c in
            let op = WidgetBLEWrite(data: data, continuation: c)
            current = op
            op.central = CBCentralManager(delegate: op, queue: .main)
        }
    }
    private init(data: Data, continuation: CheckedContinuation<Void, Error>) {
        self.data = data; self.continuation = continuation; super.init()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting { finish(.failure(err("Bluetooth is off."))) }
            return
        }
        timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(err("Lamp not found. Keep it nearby and powered on."))) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout!)
        central.scanForPeripherals(withServices: [CBUUID(string: "AE30")])
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard p.name == "VC-BLELIGHT" || (advertisementData[CBAdvertisementDataLocalNameKey] as? String) == "VC-BLELIGHT" else { return }
        central.stopScan(); peripheral = p; p.delegate = self; central.connect(p)
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([CBUUID(string: "AE30")]) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let s = p.services?.first(where: { $0.uuid == CBUUID(string: "AE30") }) else { finish(.failure(err("AE30 service missing."))); return }
        p.discoverCharacteristics([CBUUID(string: "AE01")], for: s)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let c = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "AE01") }) else { finish(.failure(err("AE01 characteristic missing."))); return }
        p.writeValue(data, for: c, type: .withoutResponse); finish(.success(()))
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { finish(.failure(error ?? err("Connection failed."))) }
    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel(); if central?.isScanning == true { central.stopScan() }; if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        let c = continuation; continuation = nil; c?.resume(with: result); if Self.current === self { Self.current = nil }
    }
    private func err(_ message: String) -> NSError { NSError(domain: "RaingelWidgetBLE", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
