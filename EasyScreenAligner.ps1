# Easy Screen Aligner - MIT License
# See the LICENSE file in this repository for the complete license text.
# --- Part 1: Setup calibration overlay on each monitor (transparent background) ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Show calibration instructions popup at launch.
$popupMessage = "Calibration Instructions:`n`n- Use the red line to align your monitors.`n- Drag the red line up or down using your mouse.`n- Click the ✔ button when you're satisfied with the alignment.`n- Press ESC at any time to cancel calibration."
[System.Windows.Forms.MessageBox]::Show($popupMessage, "Calibration Instructions", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

# Global arrays for results and forms, plus a flag for cancellation.
$global:MonitorResults = @()
$global:CalibForms = @()
$global:CalibrationCanceled = $false

# For each screen, open a borderless form that covers it.
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {

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
    $initialLineY = [math]::Round($form.Height / 2)
    $form.Tag = [ordered]@{
        Screen   = $screen
        LineY    = $initialLineY
        Dragging = $false
        Offset   = 0
    }

    # Paint event: Draw a semi-transparent, 5-px thick red line.
    $form.Add_Paint({
        param($sender, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,255,0,0), 5)
        $lineY = $sender.Tag.LineY
        $e.Graphics.DrawLine($pen, 0, $lineY, $sender.Width, $lineY)
    })

    # Allow dragging the line.
    $form.Add_MouseDown({
        param($sender, $e)
        if ([math]::Abs($e.Y - $sender.Tag.LineY) -le 5) {
            $sender.Tag.Dragging = $true
            $sender.Tag.Offset = $e.Y - $sender.Tag.LineY
        }
    })
    $form.Add_MouseMove({
        param($sender, $e)
        if ($sender.Tag.Dragging) {
            $sender.Tag.LineY = $e.Y - $sender.Tag.Offset
            $sender.Invalidate()
        }
    })
    $form.Add_MouseUp({
        param($sender, $e)
        $sender.Tag.Dragging = $false
    })

    # "Done" button with a tick (✔); its click records this screen's calibration.
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "✔"
    $button.Width = 60
    $button.Height = 30
    $button.Location = New-Object System.Drawing.Point(10,10)
    $button.BackColor = [System.Drawing.Color]::White
    $button.ForeColor = [System.Drawing.Color]::Black
    $button.Add_Click({
        param($sender, $e)
        $frm = $sender.FindForm()
        $global:MonitorResults += [PSCustomObject]@{
            Screen = $frm.Tag.Screen
            LineY  = $frm.Tag.LineY
        }
        $frm.Close()
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

# --- Part 2: Compute new vertical positions using the primary monitor as reference ---
# Use the primary monitor's red line absolute Y as the desired alignment.
$primaryResult = $global:MonitorResults | Where-Object { $_.Screen.Primary } | Select-Object -First 1
if ($primaryResult) {
    $desiredAbsolute = $primaryResult.Screen.Bounds.Y + $primaryResult.LineY
    Write-Host "Primary monitor detected; using its red line position ($desiredAbsolute) as reference."
} else {
    # Fallback: use the median of all absolute positions.
    $absPositions = $global:MonitorResults | ForEach-Object { $_.Screen.Bounds.Y + $_.LineY }
    $sorted = $absPositions | Sort-Object
    $medianIndex = [math]::Floor($sorted.Count / 2)
    $desiredAbsolute = $sorted[$medianIndex]
    Write-Host "No primary monitor flagged; using median red line position ($desiredAbsolute) as reference."
}

# Calculate adjustments: primary monitor remains unchanged; for others, adjust Y so that (screen.Top + localLine) = desired.
$global:DisplayAdjustments = @()
foreach ($result in $global:MonitorResults) {
    $currentTop = $result.Screen.Bounds.Y
    $localLineY = $result.LineY
    if ($result.Screen.Primary) {
        $newTop = $currentTop  # Keep primary monitor unchanged.
    } else {
        $newTop = $desiredAbsolute - $localLineY
    }
    $delta = $newTop - $currentTop
    $global:DisplayAdjustments += [PSCustomObject]@{
        DeviceName = $result.Screen.DeviceName
        OldTop     = $currentTop
        NewTop     = $newTop
        Delta      = $delta
        Screen     = $result.Screen
    }
    Write-Host "For monitor $($result.Screen.DeviceName): Old top=$currentTop, local line=$localLineY, new top=$newTop (delta=$delta)"
}

# --- Part 3: Update display configuration via Windows API (adjust only vertical positions) ---
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
        // Update only dmPosition (vertical offset); preserve dmPosition.x by reusing newX.
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

# For each monitor adjustment, update its vertical position while preserving its current X.
foreach ($adj in $global:DisplayAdjustments) {
    $device = $adj.DeviceName
    $currentX = $adj.Screen.Bounds.X
    $newY = $adj.NewTop
    Write-Host "Adjusting $device : setting position to ($currentX, $newY)..."
    $ok = [DisplayConfig]::SetDisplayPosition($device, $currentX, $newY)
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
