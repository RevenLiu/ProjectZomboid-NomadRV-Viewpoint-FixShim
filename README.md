# ProjectZomboid-NomadRV-Viewpoint-FixShim

A small compatibility shim that restores Nomad RV interactions affected by the following mod combination:

- Viewpoint 0.1.7
- DeadWorks Vehicle Framework (DWVF) 1.0.4
- Nomad RV 0.9.2

**Project Zomboid Version:** 42.22.2

## TL;DR

| Symptom | Immediate Cause | Affected Component |
|---|---|---|
| The "Sit in driver seat" option is missing from the context menu when near the driver's seat, making the vehicle undrivable. | `DWVView.fixture()` always returns `-1`. | DWVF |
| Pressing E does not toggle vehicle doors or entry steps. | The same check in `OnKeyPressed` causes an early return. | DWVF |

### Root Cause

In DWVF 1.0.4, the `deadworks.vehicles.Hooks$DriveCamera` patch targets the method:

`viewpoint.camera.CameraView.place(Frame, float, float, float[])`

However, Viewpoint 0.1.7 changed this method to accept `viewpoint.core.CameraShot` instead.

Due to this method signature mismatch, ZombieBuddy (the Java patching framework) abandons the transformation of the entire target class.

As a result, the camera data required by DWVF is never generated. Consequently, `DWVView` cannot retrieve the necessary frame data, causing:

- `vehicle()` to always return `nil`.
- `fixture()` to always return `-1`.

This breaks the interaction checks that depend on `DWVView`.

## Fixes

- Restores E-key interactions for vehicle doors and entry steps.
- Restores missing interaction options (such as driver seat and door toggles) in Viewpoint's lens menu.

## Installation

1. Download the latest release ZIP archive, or download this repository as a ZIP archive.
2. Extract the mod folder into your Project Zomboid `mods` directory (e.g. `C:\Users\YourUserName\Zomboid\mods`).
3. Enable the shim in the in-game Mods menu.

### In-Game Controls

- **E:** Toggle vehicle doors.
- **Shift + E:** Toggle vehicle entry steps.

## Limitations

- Only supports interactions explicitly defined by Nomad RV (doors, seats, and entry steps). Features such as curtains, roof components, and bike racks that depend on `DWVView` are not covered.
- Replaces the original line-of-sight-based interaction checks with position-based checks and dedicated key bindings.
- This shim depends on the current DWVF implementation. Future DWVF updates may render it unnecessary or make it incompatible.

## Disclaimer

This is an unofficial community compatibility fix. It is not affiliated with, endorsed by, or maintained by the original mod authors.
