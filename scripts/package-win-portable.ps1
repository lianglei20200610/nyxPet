$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$node = Join-Path $root ".tools\node-v24.16.0-win-x64\node.exe"
$builder = Join-Path $root "node_modules\electron-builder\cli.js"
$dist = Join-Path $root "dist"
$winUnpacked = Join-Path $dist "win-unpacked"
$packageDir = Join-Path $dist "NyxPet-Portable"
$zipPath = Join-Path $dist "NyxPet-Portable.zip"
$exePath = Join-Path $packageDir "Nyx Pet.exe"
$skillsDir = Join-Path $root "skills"
$petsDir = Join-Path $root "pets"
$readmePath = Join-Path $root "README-PORTABLE.md"

if (!(Test-Path $node)) {
  throw "Node runtime not found: $node"
}

if (!(Test-Path $builder)) {
  throw "electron-builder not found. Run npm install first."
}

if (!(Test-Path $skillsDir)) {
  throw "Skills directory not found: $skillsDir"
}

if (!(Test-Path $readmePath)) {
  throw "Portable README not found: $readmePath"
}

Push-Location $root
try {
  & $node $builder --win dir --config.win.signAndEditExecutable=false
} finally {
  Pop-Location
}

if (!(Test-Path (Join-Path $winUnpacked "Nyx Pet.exe"))) {
  throw "Build output is missing Nyx Pet.exe: $winUnpacked"
}

if (Test-Path $packageDir) {
  Remove-Item -LiteralPath $packageDir -Recurse -Force
}
if (Test-Path $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $packageDir | Out-Null
Copy-Item -Path (Join-Path $winUnpacked "*") -Destination $packageDir -Recurse -Force
Copy-Item -Path $skillsDir -Destination (Join-Path $packageDir "skills") -Recurse -Force
if (Test-Path $petsDir) {
  Copy-Item -Path $petsDir -Destination (Join-Path $packageDir "pets") -Recurse -Force
}
Copy-Item -Path $readmePath -Destination $packageDir -Force

$runtimeData = @(
  "data",
  "pet-state.json",
  "events.json",
  "ledger.json",
  "pet-settings.json",
  "skill-inputs.json"
)

foreach ($name in $runtimeData) {
  $target = Join-Path $packageDir $name
  if (Test-Path $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}

Compress-Archive -Path $packageDir -DestinationPath $zipPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $forbidden = @($archive.Entries | Where-Object {
    $_.FullName -match '(^|/)data/' -or
    $_.Name -in @("pet-state.json", "events.json", "ledger.json", "pet-settings.json", "skill-inputs.json")
  })
  if ($forbidden.Count -gt 0) {
    $names = ($forbidden | ForEach-Object { $_.FullName }) -join "`n"
    throw "Portable package contains runtime data:`n$names"
  }
} finally {
  $archive.Dispose()
}

if (!(Test-Path $exePath)) {
  throw "Portable exe missing: $exePath"
}

Write-Host "Portable package created:"
Write-Host "  $zipPath"
