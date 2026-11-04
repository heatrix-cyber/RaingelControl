# Raingel Control

Native iOS controller for the user's Raingel RGB Bluetooth lamp.

## Verified lamp protocol

- BLE advertised name: `VC-BLELIGHT`
- Service UUID: `AE30`
- Write characteristic UUID: `AE01`
- Write type: Write Without Response
- ON payload: `01 01`
- OFF payload: `01 00`
- RGB payload: `03 RR GG BB`
- Lamp channel range: `0...147` (empirically observed for this lamp)

The app translates the RGB and brightness controls into the lamp's 0...147 channel range. The Control Centre extension provides a power toggle and a control that opens the colour interface.

## Build from GitHub on a cloud Mac

1. Upload the **contents** of this folder to the root of a public GitHub repository. Keep `.github/workflows/build.yml` and the `Sources` folders in their exact locations.
2. GitHub Actions runs on pushes to `main`, or manually from the Actions tab using **Build Raingel Control IPA**.
3. Download the `RaingelControl-unsigned-IPA` artifact from the completed workflow run.
4. Import the unsigned IPA into SideStore for signing and installation.

The artifact is unsigned; SideStore must sign it. The project has not yet been validated on a physical lamp or iPhone. Control Centre availability and BLE execution must be tested after installation. An iOS app extension can be subject to execution-time and Bluetooth lifecycle restrictions.
