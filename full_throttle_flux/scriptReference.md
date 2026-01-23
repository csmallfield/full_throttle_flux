# Full Throttle Flux - Script Reference

Quick reference guide for all scripts in the project. Use Ctrl+F to search for specific functionality.

---

## Autoload System (`scripts/autoload/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `game_manager.gd` | `GameManager` | Central manager for game state: selected ship, track, mode; discovers available profiles on startup | `res://scripts/autoload/game_manager.gd` |

---

## Game Modes (`scripts/modes/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `mode_base.gd` | `ModeBase` | Abstract base class for game modes handling track loading, ship spawning, camera and HUD setup | `res://scripts/modes/mode_base.gd` |
| `time_trial_mode.gd` | `TimeTrialMode` | Time trial mode implementation: solo racing with lap timing and best lap tracking | `res://scripts/modes/time_trial_mode.gd` |
| `endless_mode.gd` | `EndlessMode` | Endless mode implementation: continuous racing with manual session end via pause menu | `res://scripts/modes/endless_mode.gd` |
| `race_mode.gd` | `RaceMode` | Race mode implementation: player vs AI opponents with position tracking and difficulty levels | `res://scripts/modes/race_mode.gd` |

---

## AI System (`scripts/ai/`)

### Core AI Components

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ai_ship_controller.gd` | `AIShipController` | Main AI orchestrator that coordinates all AI components and applies inputs to ships | `res://scripts/ai/ai_ship_controller.gd` |
| `ai_line_follower.gd` | `AILineFollower` | Determines optimal racing line and target positions using spline data and recorded laps | `res://scripts/ai/ai_line_follower.gd` |
| `ai_control_decider.gd` | `AIControlDecider` | Calculates throttle, brake, steering, and airbrake inputs based on racing line and skill level | `res://scripts/ai/ai_control_decider.gd` |
| `ai_ship_avoidance.gd` | `AIShipAvoidance` | Provides collision avoidance adjustments for ship-to-ship racing with position-based aggression | `res://scripts/ai/ai_ship_avoidance.gd` |
| `track_spline_helper.gd` | `TrackSplineHelper` | Utility for world-to-spline conversions, curvature analysis, and lateral offset calculations | `res://scripts/ai/track_spline_helper.gd` |

### AI Data Recording & Management

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ai_lap_recorder.gd` | `AILapRecorder` | Records player racing data for AI training, validates laps, and saves to TrackAIData resources | `res://scripts/ai/ai_lap_recorder.gd` |
| `ai_data_manager.gd` | `AIDataManager` | Static utility for loading/saving AI data, baking user recordings to bundled resources | `res://scripts/ai/ai_data_manager.gd` |
| `ai_debug_tester.gd` | `AIDebugTester` | Development tool for testing AI (F1-F7 hotkeys) with skill cycling and data management | `res://scripts/ai/ai_debug_tester.gd` |

### AI Resource Classes (`scripts/ai/resources/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ai_racing_sample.gd` | `AIRacingSample` | Single recorded sample point containing position, speed, and control data | `res://scripts/ai/resources/ai_racing_sample.gd` |
| `ai_recorded_lap.gd` | `AIRecordedLap` | Complete lap recording with metadata and array of AIRacingSamples | `res://scripts/ai/resources/ai_recorded_lap.gd` |
| `track_ai_data.gd` | `TrackAIData` | Container for all recorded laps on a track with skill tier organization and interpolation | `res://scripts/ai/resources/track_ai_data.gd` |

---

## Ship System (`scripts/ships/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ship_controller.gd` | `ShipController` | WipEout 2097-style anti-gravity ship physics with hover, thrust, steering, airbrakes, and collision handling | `res://scripts/ships/ship_controller.gd` |
| `ship_collision_profile.gd` | `ShipCollisionProfile` | Resource defining ship-to-ship collision parameters (velocity retain, push force, spin effects) | `res://scripts/ships/ship_collision_profile.gd` |
| `ship_audio_controller.gd` | `ShipAudioController` | *(Referenced - needs documentation)* Manages ship engine, boost, and collision audio | `res://scripts/ship_audio_controller.gd` |

---

## Resource Definitions (`scripts/resources/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ship_profile.gd` | `ShipProfile` | Resource defining ship characteristics: speed, handling, hover, collision, and visual parameters | `res://scripts/resources/ship_profile.gd` |
| `track_profile.gd` | `TrackProfile` | Resource defining track metadata: scene reference, laps, difficulty, mode support, and display info | `res://scripts/resources/track_profile.gd` |

---

## Race System (`scripts/race/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `race_position_tracker.gd` | `RacePositionTracker` | Calculates real-time race positions based on lap progress and spline offset for all ships | `res://scripts/race/race_position_tracker.gd` |

---

## Track Elements (`scripts/tracks/`, `scripts/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `starting_grid.gd` | `StartingGrid` | *(Referenced - needs documentation)* Manages starting positions for races | `res://scripts/tracks/starting_grid.gd` |
| `start_finish_line.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Detects lap completion and triggers race events | `res://scripts/start_finish_line.gd` |
| `boost_pad.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Applies speed boost when ships enter trigger area | `res://scripts/boost_pad.gd` |
| `respawn_trigger.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Detects out-of-bounds ships and triggers respawn | `res://scripts/respawn_trigger.gd` |

---

## Race Management (`scripts/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `race_controller.gd` | `RaceController` | *(Referenced - needs documentation)* Main race flow controller for time trials | `res://scripts/race_controller.gd` |
| `race_launcher.gd` | `RaceLauncher` | *(Referenced - needs documentation)* Initializes and launches race sessions | `res://scripts/race_launcher.gd` |

---

## UI & Menus (`scripts/ui/`, `scripts/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `main_menu.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Main menu navigation and game mode selection | `res://scripts/main_menu.gd` |
| `ship_select.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Ship selection screen UI controller | `res://scripts/ui/ship_select.gd` |
| `track_select.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Track selection screen UI controller | `res://scripts/ui/track_select.gd` |
| `difficulty_select.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Difficulty/AI skill selection UI | `res://scripts/ui/difficulty_select.gd` |
| `hud_race.gd` | *(Unnamed)* | *(Referenced - needs documentation)* In-race HUD displaying speed, lap time, position | `res://scripts/hud_race.gd` |
| `debug_hud.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Developer debug information overlay | `res://scripts/debug_hud.gd` |
| `pause_menu.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Pause menu functionality and navigation | `res://scripts/pause_menu.gd` |
| `results_screen.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Post-race results display with lap times | `res://scripts/results_screen.gd` |
| `leaderboard_screen.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Displays saved lap times and leaderboards | `res://scripts/leaderboard_screen.gd` |
| `now_playing_display.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Shows currently playing music track | `res://scripts/now_playing_display.gd` |

---

## Camera & Audio (`scripts/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `ag_camera_2097.gd` | *(Unnamed)* | *(Referenced - needs documentation)* Anti-gravity racing camera with FOV and follow behavior | `res://scripts/ag_camera_2097.gd` |

---

## Testing & Debug (`scripts/test/`)

| Script | Class | Description | Path |
|--------|-------|-------------|------|
| `race_mode_test.gd` | `RaceModeTest` | *(Referenced - needs documentation)* Test scene for race mode with AI opponents | `res://scripts/test/race_mode_test.gd` |

---

## Usage Guide

### When Working On...

**Game Mode System:**
- `mode_base.gd` - Base mode functionality
- `time_trial_mode.gd` - Time trial implementation
- `endless_mode.gd` - Endless mode implementation
- `race_mode.gd` - Race vs AI implementation
- `game_manager.gd` - Mode/track/ship selection

**AI Racing Line & Behavior:**
- `ai_line_follower.gd` - Racing line calculation
- `ai_control_decider.gd` - Control outputs
- `track_spline_helper.gd` - Track geometry
- `track_ai_data.gd` - Recorded data

**AI Opponent Spawning & Racing:**
- `race_mode.gd` - AI spawning and setup
- `ai_ship_controller.gd` - AI instance management
- `ai_ship_avoidance.gd` - Collision prevention
- `race_position_tracker.gd` - Position calculations
- `starting_grid.gd` - Spawn positions

**Recording AI Training Data:**
- `ai_lap_recorder.gd` - Recording system
- `ai_data_manager.gd` - Data persistence
- `ai_debug_tester.gd` - Testing tools

**Ship Physics & Handling:**
- `ship_controller.gd` - Main physics
- `ship_profile.gd` - Configuration
- `ship_collision_profile.gd` - Ship collision settings

**Ship-to-Ship Collisions:**
- `ship_controller.gd` - Collision handling (`_handle_ship_collision()`)
- `ship_collision_profile.gd` - Tuning parameters
- `ai_ship_avoidance.gd` - AI avoidance behavior
- `race_mode.gd` - Avoidance initialization

**Track & Race Setup:**
- `track_profile.gd` - Track configuration
- `mode_base.gd` - Track loading
- `starting_grid.gd` - Grid positions
- `game_manager.gd` - Track discovery

**Race Position & Rankings:**
- `race_position_tracker.gd` - Position calculations
- `race_mode.gd` - Integration
- `hud_race.gd` - Position display

---

## Architecture Notes

### Mode System
- **ModeBase** provides common functionality (track loading, ship spawn, camera, HUD)
- **Modes** extend ModeBase and implement specific game loop (time trial, endless, race)
- Modes create UI inline (not from PackedScenes) for flexibility

### AI System
Three-component architecture:
1. **AILineFollower** - "Where should I go?"
2. **AIControlDecider** - "How should I control the ship?"
3. **AIShipAvoidance** - "How do I avoid other ships?"

### Resource-Driven Design
- **ShipProfile** - All ship physics/handling parameters
- **TrackProfile** - Track metadata and scene reference
- **ShipCollisionProfile** - Ship-to-ship collision tuning
- **TrackAIData** - Recorded lap data with skill tiers

### Collision Layers
- **Layer 1** - Ground/track
- **Layer 2** - Ships (player + AI)
- **Layer 4** - Walls/obstacles

Ship collision mask: `7` (1 + 2 + 4 = ground + ships + walls)

---

## Key Systems

### Respawn System
Ships save "safe positions" every 0.3s while grounded. Fall below Y threshold → respawn at last safe position.

### Hover Physics
Spring-based hover using RayCast3D. Applies forces to maintain target height above track surface with damping.

### Grip System
`grip` parameter controls how quickly velocity aligns with ship facing direction. Higher = tighter turns, lower = more drift.

### Airbrake System
- Reduces grip (increases drift)
- Adds rotation input
- Applies drag to slow down
- Opposite airbrake + steering = even lower grip (drift boost)

### AI Skill Tiers
TrackAIData organizes recorded laps into 5 tiers (fast/good/median/slow/safe). AI interpolates between tiers based on skill level (0.0-1.0).

### Position Tracking
Progress = `(lap - 1) + spline_offset`. Ships sorted by progress descending. Updates every 0.1s with change detection.

---

## Notes

- This is **Batch 2** of the script reference
- Scripts marked *(Referenced - needs documentation)* exist but weren't provided in detail
- AI system is fully documented
- Mode system is fully documented
- Ship physics system is fully documented
- Use this as navigation starting point; expand as needed

---

**Last Updated:** 2026-01-23  
**Coverage:** AI system, modes, ship physics, resources, race system - COMPLETE  
**Remaining:** UI, camera, audio, track elements, race management