# Naver Map Auto-Simulation Infrastructure

This repository is a comprehensive infrastructure for managing and orchestrating a fleet of physical Android devices (Samsung Galaxy S20 series) to perform large-scale parallel simulation of driving paths and traffic on Naver Maps.

## 🚀 Project Overview

The system is designed to automate the entire lifecycle of a simulation device, from initial provisioning to real-time synchronized control and automated traffic generation.

### Key Components

*   **Provisioning (`install.sh`)**: Automates the setup of new devices, including:
    *   Installation of specific Naver Maps versions (v6.5.2.1), GPS Emulator, and ADBKeyboard.
    *   System-level SSL certificate injection for traffic interception.
    *   **WebView Downgrade**: Forcing Android System WebView to factory versions (v111 or lower) to bypass strict SSL checks introduced in v120+.
*   **Visual Orchestration (`scr.sh`, `scrcpy/`)**:
    *   Arranges up to 10 devices in a 5x2 grid for simultaneous monitoring.
    *   **Visual Sync Pad**: A custom GUI (`scrcpy/sync_gui_control.py`) that provides a live preview of a master device and broadcasts all touch/text inputs to all connected slave devices.
*   **Simulation Engine (`test_nmap_v1/`)**:
    *   **`run_multi.sh`**: Parallel runner that launches simulation instances for all devices defined in `api/devices.json`.
    *   **State-Machine Monitor (`utils/log_monitor.sh`)**: Non-blocking packet and UI state monitor. Automatically handles modal popups (Clova AI, Business Hours) via background subshells to avoid interrupting the main polling cycle.
    *   **Dynamic UI Clicker (`utils/ui_clicker.py`)**: Uses local device XML dumps to dynamically seek and tap navigation elements (like `tab_car` and `btn_destination`) using exact text, `content-desc`, or `resource-id` bounds, entirely avoiding hardcoded layout coordinates.
    *   **Intelligent GPS Hot-Reload (`utils/parse_remaining_route.py`, `cmd/reload.sh`)**: Extracts real-time `routeend` remaining distances directly from MITM proxy traffic to detect 'Stalls' (if vehicle stops moving for > 45s). Automatically injects new routes into the headless GPS emulator without touching device UI.
    *   **Traffic Washing (`lib/mitm_addon.py`)**: Intercepts and modifies HTTPS traffic to anonymize device identities (ADID, SSAID, NI, IDFV, etc.) and inject jitter into location data using Protobuf mutation.
    *   **Frida Integration**: Injects stability and network hooks (`lib/hooks/`) during app launch.
*   **Device Utilities (`cmd.sh`, `cmd/`)**: A collection of surgical ADB scripts for mass device control (Home, Mute, Portrait mode, IP rotation via Airplane mode, etc.).

## 🛠 Building and Running

### 1. Device Setup
Ensure devices are connected via ADB and rooted with Magisk.
```bash
./install.sh
```

### 2. Launch Monitoring & Sync Control
Starts the 5x2 grid view and the visual synchronization controller.
```bash
./scr.sh         # Launch grid and sync pad
./scr.sh --reset # Restart all windows and the controller
```

### 3. Run Simulation
Execute the parallel simulation suite.
```bash
cd test_nmap_v1
./run_multi.sh --id {ROUTE_ID} # Run a specific route simulation
./run_multi.sh --reset         # Clear app data before running
```

### 4. Direct Device Commands
```bash
./cmd.sh --home     # Send all devices to Home screen
./cmd.sh --ip       # Rotate IP on all devices (Airplane mode toggle)
./cmd.sh --mute     # Mute all devices
```

## 📂 Directory Structure

*   `cmd/`: Individual ADB utility scripts.
*   `docs/`: PDCA (Plan-Design-Do-Check-Act) development documents.
*   `install/`: APKs, certificates, and Magisk modules for provisioning.
*   `scrcpy/`: Window arrangement and synchronization logic.
*   `test_nmap_v1/`: Core simulation logic, logs, and API configurations.
    *   `api/`: Device and route configuration files.
    *   `lib/`: MITM addons and Frida hooks.
    *   `logs/`: Time-stamped logs for every device session.

## 📝 Development Conventions

*   **Identity Spoofing**: All device-specific identifiers are randomized at runtime in `test_nmap_v1/run_single.sh` and applied via `mitm_addon.py`.
*   **Logging**: Every session generates a dedicated log folder containing `frida.log`, `mitm.log`, and `crash_debug.log`.
*   **Resilience**: Use `run_multi.sh` for parallel tasks as it handles graceful shutdown (SIGINT) for all child processes.
*   **SSL Interception**: Always ensure the `AlwaysTrustUserCerts` Magisk module is active on devices if HTTPS traffic fails to decrypt.
