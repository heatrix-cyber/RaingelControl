import SwiftUI
import UIKit

@main
struct RaingelControlApp: App {
    var body: some Scene {
        WindowGroup {
            LampView()
        }
    }
}

struct LampView: View {
    @State private var red = 113.0
    @State private var green = 0.0
    @State private var blue = 147.0
    @State private var brightness = 100.0
    @State private var isOn = true
    @State private var status = "Ready"

    private func applyColour() {
        Task {
            do {
                try await LampBLE.sendRGB(
                    red: Int(red), green: Int(green), blue: Int(blue),
                    brightness: Int(brightness)
                )
                status = "Colour sent"
            } catch { status = error.localizedDescription }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Raingel RGB Controller") {
                    Toggle("Power", isOn: $isOn)
                        .onChange(of: isOn) { _, on in
                            Task {
                                do {
                                    try await LampBLE.setPower(on)
                                    if on { applyColour() }
                                    status = on ? "Lamp on" : "Lamp off"
                                } catch { status = error.localizedDescription }
                            }
                        }
                }
                Section("Colour") {
                    ColorPicker("Choose colour", selection: Binding(
                        get: { Color(red: red / 255, green: green / 255, blue: blue / 255) },
                        set: { c in
                            let ui = UIColor(c)
                            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                            red = (r * 255).rounded(); green = (g * 255).rounded(); blue = (b * 255).rounded()
                            if isOn { applyColour() }
                        }
                    ))
                    channelSlider("Red", value: $red)
                    channelSlider("Green", value: $green)
                    channelSlider("Blue", value: $blue)
                    HStack { Text("Brightness"); Spacer(); Text("\(Int(brightness))%") }
                    Slider(value: $brightness, in: 1...100, step: 1).onChange(of: brightness) { _, _ in if isOn { applyColour() } }
                    Button("Send colour") { if isOn { applyColour() } }
                }
                Section("Status") { Text(status) }
            }
            .navigationTitle("Raingel Lamp")
            .onOpenURL { url in
                if url.host == "power" {
                    isOn.toggle()
                    Task { try? await LampBLE.setPower(isOn) }
                }
            }
        }
    }

    @ViewBuilder private func channelSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))") }
            Slider(value: value, in: 0...255, step: 1).onChange(of: value.wrappedValue) { _, _ in if isOn { applyColour() } }
        }
    }
}
