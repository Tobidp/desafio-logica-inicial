# FusionInventory Agent deployment via PowerShell

param(
    [switch]$ForceInstall,
    [switch]$AssumeYes
)

# Configuration values (edit as needed)
$SetupLocation = "https://glpi.grupoesales.com.br/down"
$SetupOptions  = "/acceptlicense /runnow /server='http://glpi.grupoesales.com.br/plugins/fusioninventory/' /S"
$VerboseLog    = $true

function Write-Log($msg) {
    if ($VerboseLog) { Write-Host $msg }
}

function Get-InstalledVersion {
    $paths = @(
        "HKLM:\SOFTWARE\FusionInventory-Agent",
        "HKLM:\SOFTWARE\Microsoft\\Windows\\CurrentVersion\\Uninstall\\FusionInventory Agent",
        "HKLM:\SOFTWARE\Microsoft\\Windows\\CurrentVersion\\Uninstall\\FusionInventory-Agent",
        "HKLM:\SOFTWARE\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\FusionInventory Agent",
        "HKLM:\SOFTWARE\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\FusionInventory-Agent"
    )
    foreach ($p in $paths) {
        try {
            $v = (Get-ItemProperty -Path $p -ErrorAction Stop).DisplayVersion
            if ($v) { return $v }
        } catch {}
    }
    return $null
}

function Get-LatestRelease {
    $uri = "https://api.github.com/repos/fusioninventory/fusioninventory-agent-windows-installer/releases/latest"
    $release = Invoke-RestMethod -Uri $uri -Headers @{"User-Agent"="PowerShell"}
    return $release
}

function Download-WithProgress([string]$url, [string]$destination) {
    $client = New-Object System.Net.Http.HttpClient
    try {
        $response = $client.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        $response.EnsureSuccessStatusCode()
        $total = $response.Content.Headers.ContentLength
        if (-not $total) {
            Write-Log "Downloading..."
            [System.IO.File]::WriteAllBytes($destination, $response.Content.ReadAsByteArrayAsync().Result)
        } else {
            $stream = $response.Content.ReadAsStreamAsync().Result
            $fileStream = [System.IO.File]::Create($destination)
            $buffer = New-Object byte[] 8192
            $totalRead = 0
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                $percent = [math]::Round(($totalRead / $total) * 100, 2)
                Write-Progress -Activity "Downloading $destination" -PercentComplete $percent -Status "$percent%"
            }
            $fileStream.Close()
            Write-Progress -Activity "Downloading $destination" -Completed
        }
    } finally {
        $client.Dispose()
    }
}

$arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
Write-Log "System architecture detected: $arch"

$release     = Get-LatestRelease
$tag         = $release.tag_name.TrimStart('v')
$installer   = "fusioninventory-agent_windows-$arch`_$tag.exe"
$asset       = $release.assets | Where-Object { $_.name -eq $installer } | Select-Object -First 1
if (-not $asset) {
    Write-Error "Installer $installer not found in release $tag"
    exit 1
}
$downloadUrl = $asset.browser_download_url

Write-Log "Latest version: $tag"
Write-Log "Download URL: $downloadUrl"

$installed = Get-InstalledVersion
$installNeeded = $true
if ($installed) {
    Write-Log "Installed version: $installed"
    if ($installed -eq $tag) { $installNeeded = $false }
}

if ($ForceInstall -or $installNeeded) {
    $outFile = Join-Path $env:TEMP $installer
    Write-Log "Downloading installer to $outFile ..."
    Download-WithProgress -url $downloadUrl -destination $outFile

    if (-not $AssumeYes) {
        $resp = Read-Host "Install FusionInventory Agent $tag now? (Y/N)"
        if ($resp -notin @('Y','y')) {
            Write-Log "Installation cancelled"
            return
        }
    }

    Write-Log "Running installer..."
    Start-Process -FilePath $outFile -ArgumentList $SetupOptions -Wait

    Write-Log "Removing installer"
    Remove-Item $outFile -Force
    Write-Log "Deployment done"
} else {
    Write-Log "FusionInventory Agent is up to date."
}
