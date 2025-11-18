# Easy Screen Aligner v0.1.0 - MIT License
# See the LICENSE file in this repository for the complete license text.
# --- Part 1: Setup calibration overlay on each monitor (transparent background) ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Show calibration instructions popup at launch.
$popupMessage = "Calibration Instructions:`n`n- Use the red line to align your monitors.`n- Drag the red line along the highlighted axis.`n- Click any green Apply button to confirm all monitors at once.`n- Press ESC at any time to cancel calibration."
[System.Windows.Forms.MessageBox]::Show($popupMessage, "Calibration Instructions", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

# Global arrays for results and forms, plus a flag for cancellation.
$global:MonitorResults = @()
$global:CalibForms = @()
$global:CalibrationCanceled = $false

# Determine monitor arrangement to decide whether we align vertically or horizontally.
$screens = [System.Windows.Forms.Screen]::AllScreens
if ($screens.Count -eq 0) {
    Write-Host "No monitors detected. Exiting." -ForegroundColor Red
    exit
}

$minLeft = ($screens | ForEach-Object { $_.Bounds.X } | Measure-Object -Minimum).Minimum
$maxRight = ($screens | ForEach-Object { $_.Bounds.X + $_.Bounds.Width } | Measure-Object -Maximum).Maximum
$minTop = ($screens | ForEach-Object { $_.Bounds.Y } | Measure-Object -Minimum).Minimum
$maxBottom = ($screens | ForEach-Object { $_.Bounds.Y + $_.Bounds.Height } | Measure-Object -Maximum).Maximum
$widthSpan = $maxRight - $minLeft
$heightSpan = $maxBottom - $minTop

$global:CalibrationAxis = if (($screens.Count -eq 1) -or ($widthSpan -ge $heightSpan)) { 'Y' } else { 'X' }
if ($global:CalibrationAxis -eq 'Y') {
    Write-Host "Detected side-by-side monitors; using horizontal calibration lines."
} else {
    Write-Host "Detected vertically stacked monitors; using vertical calibration lines."
}

$lineThickness = 10
$hitTolerance = 12

# For each screen, open a borderless form that covers it.
foreach ($screen in $screens) {

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.TopMost = $true
    $form.StartPosition = 'Manual'
    $form.Location = $screen.Bounds.Location
    $form.Size = $screen.Bounds.Size
    # Use Magenta as the transparent color so the desktop shows through.
    $form.BackColor = [System.Drawing.Color]::Magenta
    $form.TransparencyKey = [System.Drawing.Color]::Magenta

    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $global:CalibrationCanceled = $true
            foreach ($f in $global:CalibForms) {
                if ($f.Visible) { $f.Close() }
            }
            Write-Host "Calibration canceled via ESC." -ForegroundColor Yellow
        }
    })

    # Start with the red line at mid-screen.
    $initialLine = if ($global:CalibrationAxis -eq 'Y') {
        [math]::Round($form.Height / 2)
    } else {
        [math]::Round($form.Width / 2)
    }
    $form.Tag = [ordered]@{
        Screen     = $screen
        LineValue  = $initialLine
        Dragging   = $false
        Offset     = 0
    }

    # Paint event: Draw a semi-transparent, thicker red line, horizontal or vertical.
    $form.Add_Paint({
        param($sender, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220,255,0,0), $lineThickness)
        $lineValue = $sender.Tag.LineValue
        if ($global:CalibrationAxis -eq 'Y') {
            $e.Graphics.DrawLine($pen, 0, $lineValue, $sender.Width, $lineValue)
        } else {
            $e.Graphics.DrawLine($pen, $lineValue, 0, $lineValue, $sender.Height)
        }
    })

    # Allow dragging the line along the detected axis.
    $form.Add_MouseDown({
        param($sender, $e)
        if ($global:CalibrationAxis -eq 'Y') {
            if ([math]::Abs($e.Y - $sender.Tag.LineValue) -le $hitTolerance) {
                $sender.Tag.Dragging = $true
                $sender.Tag.Offset = $e.Y - $sender.Tag.LineValue
            }
        } else {
            if ([math]::Abs($e.X - $sender.Tag.LineValue) -le $hitTolerance) {
                $sender.Tag.Dragging = $true
                $sender.Tag.Offset = $e.X - $sender.Tag.LineValue
            }
        }
    })
    $form.Add_MouseMove({
        param($sender, $e)
        if ($sender.Tag.Dragging) {
            if ($global:CalibrationAxis -eq 'Y') {
                $newLine = $e.Y - $sender.Tag.Offset
                $sender.Tag.LineValue = [math]::Max(0, [math]::Min($sender.Height, $newLine))
            } else {
                $newLine = $e.X - $sender.Tag.Offset
                $sender.Tag.LineValue = [math]::Max(0, [math]::Min($sender.Width, $newLine))
            }
            $sender.Invalidate()
        }
    })
    $form.Add_MouseUp({
        param($sender, $e)
        $sender.Tag.Dragging = $false
    })

    # Prominent "Apply All" button that finalizes all monitors simultaneously.
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Apply All"
    $button.Width = 160
    $button.Height = 60
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $button.Location = New-Object System.Drawing.Point(10,10)
    $button.BackColor = [System.Drawing.Color]::FromArgb(255, 46, 204, 113)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = 'Popup'
    $button.Add_Click({
        param($sender, $e)
        if ($global:MonitorResults.Count -gt 0) { return }
        $global:MonitorResults = @()
        foreach ($frm in $global:CalibForms) {
            if ($null -ne $frm -and -not $frm.IsDisposed) {
                $global:MonitorResults += [PSCustomObject]@{
                    Screen    = $frm.Tag.Screen
                    LineValue = $frm.Tag.LineValue
                }
                if ($frm.Visible) {
                    $frm.Close()
                }
            }
        }
    })
    $form.Controls.Add($button)

    $global:CalibForms += $form
    $form.Show()
}

# Wait for all calibration windows to close.
while (($global:CalibForms | Where-Object { $_.Visible }).Count -gt 0) {
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}

if ($global:CalibrationCanceled) {
    Write-Host "Calibration canceled. Exiting." -ForegroundColor Yellow
    exit
}

if ($global:MonitorResults.Count -eq 0) {
    Write-Host "No calibration data was captured. Exiting." -ForegroundColor Yellow
    exit
}

# --- Part 2: Compute new positions along the detected calibration axis ---
# Use the primary monitor's red line absolute value as the desired alignment.
$primaryResult = $global:MonitorResults | Where-Object { $_.Screen.Primary } | Select-Object -First 1
$useYAxis = $global:CalibrationAxis -eq 'Y'
if ($primaryResult) {
    $desiredAbsolute = if ($useYAxis) {
        $primaryResult.Screen.Bounds.Y + $primaryResult.LineValue
    } else {
        $primaryResult.Screen.Bounds.X + $primaryResult.LineValue
    }
    Write-Host "Primary monitor detected; using its red line position ($desiredAbsolute) as reference."
} else {
    # Fallback: use the median of all absolute positions.
    $absPositions = $global:MonitorResults | ForEach-Object {
        if ($useYAxis) {
            $_.Screen.Bounds.Y + $_.LineValue
        } else {
            $_.Screen.Bounds.X + $_.LineValue
        }
    }
    $sorted = $absPositions | Sort-Object
    $medianIndex = [math]::Floor($sorted.Count / 2)
    $desiredAbsolute = $sorted[$medianIndex]
    Write-Host "No primary monitor flagged; using median red line position ($desiredAbsolute) as reference."
}

# Calculate adjustments: primary monitor remains unchanged; for others, adjust so absolute line matches desired.
$global:DisplayAdjustments = @()
foreach ($result in $global:MonitorResults) {
    if ($useYAxis) {
        $currentBase = $result.Screen.Bounds.Y
    } else {
        $currentBase = $result.Screen.Bounds.X
    }
    $localLine = $result.LineValue
    if ($result.Screen.Primary) {
        $newBase = $currentBase  # Keep primary monitor unchanged.
    } else {
        $newBase = $desiredAbsolute - $localLine
    }
    $delta = $newBase - $currentBase
    $global:DisplayAdjustments += [PSCustomObject]@{
        DeviceName     = $result.Screen.DeviceName
        OldCoordinate  = $currentBase
        NewCoordinate  = $newBase
        Delta          = $delta
        Screen         = $result.Screen
        Axis           = $global:CalibrationAxis
    }
    if ($useYAxis) {
        Write-Host "For monitor $($result.Screen.DeviceName): Old top=$currentBase, local line=$localLine, new top=$newBase (delta=$delta)"
    } else {
        Write-Host "For monitor $($result.Screen.DeviceName): Old left=$currentBase, local line=$localLine, new left=$newBase (delta=$delta)"
    }
}

# --- Part 3: Update display configuration via Windows API (axis-aware offsets) ---
# Compile a helper C# class. We update only DM_POSITION, leaving orientation fields untouched.
$code = @"
using System;
using System.Runtime.InteropServices;
public class DisplayConfig {
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int DM_POSITION = 0x00000020;
    private const int CDS_UPDATEREGISTRY = 0x00000001;
    private const int CDS_NORESET = 0x10000000;
    private const int DISP_CHANGE_SUCCESSFUL = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct POINTL {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public POINTL dmPosition;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    public static bool SetDisplayPosition(string deviceName, int newX, int newY) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref dm))
            return false;
        dm.dmFields |= DM_POSITION;
        dm.dmPosition.x = newX;
        dm.dmPosition.y = newY;
        int result = ChangeDisplaySettingsEx(deviceName, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
        return result == DISP_CHANGE_SUCCESSFUL;
    }

    public static bool ApplyDisplayChanges() {
        int result = ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        return result == DISP_CHANGE_SUCCESSFUL;
    }
}
"@

# Compile the helper.
Add-Type -TypeDefinition $code -PassThru | Out-Null

# For each monitor adjustment, update the relevant axis while preserving the untouched coordinate.
foreach ($adj in $global:DisplayAdjustments) {
    $device = $adj.DeviceName
    if ($adj.Axis -eq 'Y') {
        $newX = $adj.Screen.Bounds.X
        $newY = $adj.NewCoordinate
    } else {
        $newX = $adj.NewCoordinate
        $newY = $adj.Screen.Bounds.Y
    }
    Write-Host "Adjusting $device : setting position to ($newX, $newY)..."
    $ok = [DisplayConfig]::SetDisplayPosition($device, $newX, $newY)
    if (-not $ok) {
        Write-Host "Failed to update position for $device" -ForegroundColor Red
    }
}

if ([DisplayConfig]::ApplyDisplayChanges()) {
    Write-Host "Display configuration updated successfully."
} else {
    Write-Host "Failed to apply display changes." -ForegroundColor Red
}

exit
