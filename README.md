# Easy Screen Aligner

Easy Screen Aligner is a tiny helper script for Windows that keeps multiple monitors perfectly aligned. When monitors sit at slightly different heights the mouse can snag at the screen borders. This tool draws a bold red line across every screen so you can visually match the borders and then updates the display configuration automatically.

The script was initially vibe-coded with OpenAI's `o3-mini-high` model then later OpenAI's Codex model added the vertical alignment feature. It runs in PowerShell on Windows 11 (PowerShell 5.1 or later) and has not been tested on other platforms. A pre-built `EasyScreenAligner.exe` compiled with [ps2exe](https://github.com/MScholtes/PS2EXE) is included for convenience.

> **Heads up:** The script tweaks your monitor layout through the Windows API. Be sure you understand how to revert the changes (see [Troubleshooting](#troubleshooting)) before experimenting.

## Features

- Visual alignment: drag the shared red line so the edges line up perfectly.
- Automatic adjustments: vertical offsets are applied to each monitor once you confirm the placement.
- Script or EXE: run the PowerShell script directly or launch the compiled executable.
- Lightweight: no installation, drivers, or permanent services.

## Prerequisites
- Windows 11 or Windows 10 (tested on Windows 11)
- PowerShell 5.1 or later (PowerShell 7+ also works)
- Permission to run unsigned PowerShell scripts

## Running the Script Directly
1. Clone or download this repository.
2. Open PowerShell in the repo directory and, if needed, allow script execution for the current session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
3. Launch the aligner:
   ```powershell
   .\EasyScreenAligner.ps1
   ```
4. Follow the on-screen instructions:
   - Drag the red line vertically until the monitor edges are perfectly level.
   - Press **Enter** (or follow the prompts) to confirm each monitor.
   - When all screens are confirmed the script persists the new offsets.

## Running the Compiled EXE

If you prefer not to run scripts you can double-click `EasyScreenAligner.exe`. The executable was generated from the same script and behaves identically.

## Compiling to an EXE
The provided `EasyScreenAligner.exe` was produced using [ps2exe](https://github.com/MScholtes/PS2EXE). To build it yourself:
```powershell
ps2exe.ps1 .\EasyScreenAligner.ps1 .\EasyScreenAligner.exe
```
This lets you distribute a standalone executable that does not require PowerShell.

## Known Limitations

- Only vertical alignment is adjusted. Rotated displays or unusual DPI combinations may require manual tweaking afterward.
- The tool assumes all displays are active and arranged horizontally. If Windows reports an unexpected layout, the red line may not cover every monitor.
- Because the script relies on Windows APIs, it must be run from a user session with permission to change display settings.

## Troubleshooting

If the monitors do not align as expected or you want to revert the changes, you can restore your display layout in two ways:

1. **Use Windows Display Settings**
   - Right-click your desktop and choose *Display settings*.
   - Drag the monitor icons to their original positions and click **Apply**.

2. **Apply a Saved Configuration**
   - If you previously saved your display arrangement using Windows or another tool, apply that file to return to your preferred layout.

If you get stuck, you can always re-run the script and align the monitors again. Keep the Windows display settings panel open for quick recovery whenever you experiment.

## Contributing

Pull requests and issues are welcome! If you find a bug or have an idea for improving the alignment workflow, feel free to file an issue describing your setup (Windows version, monitor arrangement, and the exact behavior you observed).
