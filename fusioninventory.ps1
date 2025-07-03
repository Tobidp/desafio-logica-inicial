# FusionInventory Agent deployment via PowerShell

# Configuration values (edit as needed)
$SetupLocation = "http://glpi.grupoesales.com.br/down"
$SetupOptions  = "/acceptlicense /runnow /server='http://glpi.grupoesales.com.br/plugins/fusioninventory/' /S"
$ForceInstall  = $false
$VerboseLog    = $true

function Write-Log($msg) {
    if ($VerboseLog) { Write-Host $msg }
}

function Get-InstalledVersion {
    $paths = @(
        "HKLM:\SOFTWARE\FusionInventory-Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FusionInventory Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FusionInventory-Agent",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\FusionInventory Agent",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\FusionInventory-Agent"
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
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile

    Write-Log "Running installer..."
    Start-Process -FilePath $outFile -ArgumentList $SetupOptions -Wait

    Write-Log "Removing installer"
    Remove-Item $outFile -Force
    Write-Log "Deployment done"
} else {
    Write-Log "FusionInventory Agent is up to date."
}
