# Full Throttle Flux v17 - remove the old recording/blending system.
# Run from the REPOSITORY ROOT (the folder containing full_throttle_flux\):
#     powershell -ExecutionPolicy Bypass -File .\apply_v17_deletions.ps1
# Every path is listed explicitly; nothing is matched by wildcard.

$root = Join-Path $PSScriptRoot "full_throttle_flux"
$paths = @(
    "scripts\ai\ai_data_manager.gd",       "scripts\ai\ai_data_manager.gd.uid",
    "scripts\ai\ai_lap_recorder.gd",       "scripts\ai\ai_lap_recorder.gd.uid",
    "scripts\ai\ai_debug_tester.gd",       "scripts\ai\ai_debug_tester.gd.uid",
    "scripts\ai\resources",
    "scenes\ai_lap_recorder.tscn",
    "scenes\ai_debug_tester.tscn",
    "resources\ai_data\not_considered",
    "resources\ai_data\test_circuit_5_live_fast_racer_trained_line.tres",
    "resources\ai_data\test_circuit_6_live_fast_racer_trained_line.tres"
)
foreach ($p in $paths) {
    $full = Join-Path $root $p
    if (Test-Path $full) { Remove-Item $full -Recurse -Force; Write-Host "removed  $p" }
    else { Write-Host "absent   $p" }
}

# Old local recordings from the blending system (decision: discard).
$old = Join-Path $env:APPDATA "Godot\app_userdata\full_throttle_flux\ai_recordings"
if (Test-Path $old) { Remove-Item $old -Recurse -Force; Write-Host "removed  $old" }
else { Write-Host "absent   $old" }
Write-Host "Done. Open the project in the editor once so it rescans classes."
