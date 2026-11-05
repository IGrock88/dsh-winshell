# dsh-winshell - install/uninstall for a DSH profile.
# Usage:  powershell -ExecutionPolicy Bypass -File install.ps1 [install|uninstall] [-ProfileDir <path>]
#
# This script supports local source installs (it links the current checkout
# into the profile's node_modules). DSH's official bundle mechanism is used for
# mounting, so the profile's cordis.patch.yml is intentionally NOT modified on
# install anymore.

param(
  [ValidateSet("install", "uninstall")]
  [string]$Action = "install",
  [string]$ProfileDir = ""
)

$ErrorActionPreference = "Stop"
$pluginDir = $PSScriptRoot
$profileDir = if ($ProfileDir) { $ProfileDir } else { Join-Path $env:USERPROFILE ".dsh\profiles\web" }
$pluginLink = Join-Path $profileDir "node_modules\dsh-winshell"
$depLink = Join-Path $pluginDir "node_modules\@deepseek-ai"

function Ensure-ParentDirectory($path) {
  $parent = Split-Path $path -Parent
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
}

function New-Junction($path, $target) {
  Ensure-ParentDirectory $path
  if (Test-Path $path) { Remove-Item $path -Force -Recurse }
  New-Item -ItemType Junction -Path $path -Target $target | Out-Null
  Write-Host "  linked: $path -> $target"
}

# DSH's settings UI keeps a hard-coded namespace allowlist in
# dsh-host-apiproxy; third-party settings namespaces are refused with
# settings-not-exposed unless listed. install patches that allowlist.
$apiproxy = Join-Path $profileDir "..\node_modules\@deepseek-ai\dsh-host-apiproxy\lib\index.js"
$apiproxyBak = "$apiproxy.dsh-winshell.bak"

function Set-ApiProxyAllowlist {
  if (-not (Test-Path $apiproxy)) {
    Write-Host "  WARN: dsh-host-apiproxy not found at $apiproxy" -ForegroundColor Yellow
    return
  }
  $content = Get-Content $apiproxy -Raw
  if ($content -match '"winshell"') {
    Write-Host "  apiproxy allowlist already patched."
    return
  }
  # DSH >= 0.1.5 exposes settings through a dynamic describe() enumeration and
  # keeps no hard-coded namespace allowlist. Refuse to rewrite the host file
  # when the legacy pattern is absent (that rewrite would only add a BOM).
  if ($content -notmatch '"web-search-deepseek"\r?\n\];') {
    Write-Host "  this DSH version has no namespace allowlist; nothing to patch (expected on DSH >= 0.1.5)."
    return
  }
  Copy-Item $apiproxy $apiproxyBak -Force
  $replacement = @"
"web-search-deepseek",
	"winshell" // dsh-winshell: user-chosen default terminal
];
"@
  $content = $content -replace '"web-search-deepseek"\r?\n\];', $replacement
  Set-Content -Path $apiproxy -Value $content -Encoding UTF8
  Write-Host "  patched dsh-host-apiproxy allowlist (backup saved)."
}

function Restore-ApiProxyAllowlist {
  if (Test-Path $apiproxyBak) {
    $content = Get-Content $apiproxy -Raw
    if ($content -match '"winshell"') {
      Copy-Item $apiproxyBak $apiproxy -Force
      Write-Host "  restored apiproxy allowlist from backup."
    }
  }
}

if ($Action -eq "install") {
  Write-Host "[1/4] link plugin into profile node_modules ..."
  New-Junction $pluginLink $pluginDir

  Write-Host "[2/4] link @deepseek-ai deps into plugin node_modules ..."
  New-Junction $depLink (Join-Path $profileDir "..\node_modules\@deepseek-ai")

  Write-Host "[3/4] patch dsh-host-apiproxy settings allowlist ..."
  Set-ApiProxyAllowlist

  Write-Host "[4/4] migrate to official bundle install (dsh.bundle) ..."
  $profilePkg = Join-Path $profileDir "package.json"
  if (Test-Path $profilePkg) {
    $pkg = Get-Content $profilePkg -Raw | ConvertFrom-Json
    $bundles = @($pkg.dsh.profile.bundles)
    if ($bundles -contains "dsh-winshell") {
      Write-Host "  profile already lists dsh-winshell bundle."
    } else {
      $bundles += "dsh-winshell"
      $pkg.dsh.profile.bundles = @($bundles | Sort-Object -Unique)
      # PS 5.1 Set-Content -Encoding UTF8 writes a BOM, which breaks JSON.parse;
      # write without BOM via .NET.
      $json = $pkg | ConvertTo-Json -Depth 6
      [System.IO.File]::WriteAllText($profilePkg, $json, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "  added dsh-winshell to dsh.profile.bundles (no BOM)."
    }
  } else {
    Write-Host "  WARN: $profilePkg not found; add dsh-winshell to dsh.profile.bundles manually." -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "Done! Restart dsh web for the plugin to take effect:"
  Write-Host "  1) close the running dsh web (Ctrl+C or kill the process)"
  Write-Host "  2) run:  dsh web"
  Write-Host "After restart, open Settings -> General: a 'Default terminal' dropdown"
  Write-Host "(PowerShell / Git Bash / WSL) appears; the shell tool obeys it."
} else {
  Write-Host "[1/4] remove links ..."
  if (Test-Path $pluginLink) { Remove-Item $pluginLink -Force -Recurse; Write-Host "  removed: $pluginLink" }
  if (Test-Path $depLink) { Remove-Item $depLink -Force -Recurse; Write-Host "  removed: $depLink" }

  Write-Host "[2/4] restore dsh-host-apiproxy allowlist ..."
  Restore-ApiProxyAllowlist

  Write-Host "[3/4] clean legacy mount block from cordis.patch.yml (older installs) ..."
  $patchFile = Join-Path $profileDir "cordis.patch.yml"
  if (Test-Path $patchFile) {
    $content = Get-Content $patchFile -Raw
    $pattern = "(?s)[ \t]*# =+ dsh-winshell =+.*?\n- insert:\n    - id: tool-winshell\n      name: 'dsh-winshell'\n*"
    if ($content -match $pattern) {
      $content = $content -replace $pattern, ""
      if ([string]::IsNullOrWhiteSpace($content)) {
        $content = "[]"
      }
      [System.IO.File]::WriteAllText($patchFile, $content, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "  legacy patch block removed."
    } else {
      Write-Host "  no legacy dsh-winshell block found in patch."
    }
  }

  Write-Host "[4/4] remove dsh-winshell from profile bundles ..."
  $profilePkg = Join-Path $profileDir "package.json"
  if (Test-Path $profilePkg) {
    $pkg = Get-Content $profilePkg -Raw | ConvertFrom-Json
    $bundles = @($pkg.dsh.profile.bundles)
    if ($bundles -contains "dsh-winshell") {
      $bundles = @($bundles | Where-Object { $_ -ne "dsh-winshell" })
      $pkg.dsh.profile.bundles = $bundles
      $json = $pkg | ConvertTo-Json -Depth 6
      [System.IO.File]::WriteAllText($profilePkg, $json, (New-Object System.Text.UTF8Encoding($false)))
      Write-Host "  removed dsh-winshell from dsh.profile.bundles."
    } else {
      Write-Host "  dsh-winshell not in dsh.profile.bundles."
    }
  } else {
    Write-Host "  WARN: $profilePkg not found; remove dsh-winshell from dsh.profile.bundles manually." -ForegroundColor Yellow
  }

  Write-Host "Uninstalled. Restart dsh web; the shell tool disappears."
}
