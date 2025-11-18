# Easy Screen Aligner

Vibe Coded with Open AI's o3-mini-high. The script runs in PowerShell on Windows 11 and has not been tested elsewhere. A compiled version is provided as `EasyScreenAligner.exe`.

If you have multiple monitors at different heights it can be tricky to line them up so the mouse moves smoothly between screens. Easy Screen Aligner draws a red line across all monitors which you drag into alignment. Once each screen is confirmed the script updates their vertical positions for you.

USE WITH CAUTION:- This is **vibecoded** and although the functionality has been checked the code itself has not.

## Prerequisites
- Windows 11 or Windows 10 (tested on Windows 11)
- PowerShell 5.1 or later (PowerShell 7+ also works)
- Permission to run unsigned PowerShell scripts

## Running the Script Directly
1. Clone or download this repository.
2. Open PowerShell and, if needed, allow script execution:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
3. Run the aligner:
   ```powershell
   .\EasyScreenAligner.ps1
   ```

## Compiling to an EXE
The provided `EasyScreenAligner.exe` was produced using [ps2exe](https://github.com/MScholtes/PS2EXE). To build it yourself:
```powershell
ps2exe.ps1 .\EasyScreenAligner.ps1 .\EasyScreenAligner.exe
```
This lets you distribute a standalone executable that does not require PowerShell.

## Warning
This tool modifies display positions via the Windows API. Incorrect settings may shift or hide your monitors. Keep the Windows display settings panel handy in case you need to revert your layout.
=======
## Troubleshooting

If the monitors do not align as expected or you want to revert the changes, you can restore your display layout in two ways:

1. **Use Windows Display Settings**
   - Right-click your desktop and choose *Display settings*.
   - Drag the monitor icons to their original positions and click **Apply**.

2. **Apply a Saved Configuration**
   - If you previously saved your display arrangement using Windows or another tool, apply that file to return to your preferred layout.
