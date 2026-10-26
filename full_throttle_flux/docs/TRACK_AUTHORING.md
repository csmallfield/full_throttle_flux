# Making a track with the Track Builder

How to make a new Full Throttle Flux track in the Godot editor: draw the
curve, key the banks and widths, drop in loops, rolls, jumps, forks and boost
pads, Build, Validate, dress it with greebles, drive it, train the AI. Builder Lab
(`scenes/tracks/builder_lab.tscn`) is a worked example of everything here.

The four circuits (Utopia, Swoopy, Hairpin Alley, The Drop) were made the old
way and stay as they are; see the end.

---

## 1. The rules (why there's no offset)

The circuits' road geometry nodes carry a ~1° rotation, which pivots the
whole road about the scene origin: up to 21 m off the spline 2 km away. Every
system that trusts the spline (AI lines, respawns, magnetic zones, cameras,
set dressing) was then wrong by that much. The builder makes that impossible
by following four rules. The validator checks every one.

1. **Never move or rotate a track node.** The track root, the TrackBuilder,
   the BaseSpline and everything Build generates stay at identity. To change
   the road, edit the curve or a key; never the node.
2. **The road surface is the spline.** The cross-section puts the driving
   surface at y = 0 on the centre line, so the road is exactly where the
   spline is (Builder Lab: within 1 cm everywhere).
3. **Banking comes from BankKeys only.** Never type curve tilts: Godot's
   frame twists on its own through 3D curves, so the number you'd type isn't
   the bank you get. The builder solves the tilts (to 0.02°).
4. **One source of truth.** Road, walls, zones, jumps, junctions, respawns,
   the start and the AI's route laps all come from the same curve and keys,
   in one Build.

---

## 2. The workflow

1. **Make the scene.** A Node3D root (identity) with a `TrackBuilder` child.
   Under the TrackBuilder, a `Path3D` named `BaseSpline` with a **closed**
   Curve3D. Add your environment (WorldEnvironment, sun, a fill light from
   below if you'll have loops or rolls) as ordinary nodes: the builder never
   touches them.
2. **Draw the base.** Drag BaseSpline's points and handles. The preview
   ribbon follows within a fraction of a second. Draw the shape of the lap;
   leave the straights straight where features will go.
3. **Key the banks and widths.** Drop `BankKey` and `WidthKey` nodes anywhere
   near the track (under the TrackBuilder, in any grouping you like). Each
   key's marker snaps to the nearest track point; the node stays where you
   put it. Keys stay put in the world when you edit the curve upstream.
4. **Place the start.** A `StartKey` where the start line goes, on a straight.
   The grid forms up behind it.
5. **Add features** (section 3): `RollFeature`, `LoopFeature`,
   `JumpFeature`, `BranchFeature`. Drop each where you want it. Boost pads
   (`BoostPadKey`, section 3.5) go in the same way.
6. **Build.** The Build button on the TrackBuilder writes the track the game
   runs on. Change anything and Build again: it updates the generated nodes
   in place, and building unchanged inputs leaves the scene file
   byte-identical. **Clear build** removes everything it made.
7. **Validate.** Problems are drawn on the track (red = error, amber =
   warning) and listed in the TrackBuilder's Report. Section 4 says what each
   one means.
8. **Measure the jumps** (if you have any): `measure_jumps` flies the real
   ship off each jump to find its clean landing speed (section 3.3).
9. **Dress it** (section 3.6): drop `GreebleZoneKey`s where the dressing
   should change style. It updates live; it never makes the Build out of date.
10. **Add it to the game** (section 5) and **drive it.**
11. **Train the AI** (section 6).

### The preview

The TrackBuilder's Inspector:

| Setting | What it does |
|---|---|
| `fairing_m` (40) | Smooths the curvature step at each control point over this many metres, so hand-set handles don't jolt the ship. Moves the curve by centimetres; everything else stays exactly as drawn. 0 = exactly as drawn (deliberate kinks) |
| `start_lead` (30) | The generated lap starts this far before the start line |
| `overlay` | What the ribbon's colour shows: bank, roll rate (red over 0.7°/m), cornering load at `ref_speed`, grade, width (red where it tapers too fast), how far fairing moved the curve |
| `ribbon` | The coloured ribbon on or off (Build turns it off so you see the real road) |

Purple gates mark each feature's footprint, with its length; cyan posts mark
where a fork's junctions end; orange outlines with a chevron are boost pads.

---

## 3. Features

A feature replaces a stretch of the curve you drew (its footprint) with its
own shape, fitted onto your curve like a path deformer: it starts and ends
exactly on the curve, and a gently curving or climbing stretch bends the
feature with it. Nothing outside the footprint moves. Drop the feature node
where you want the middle of it.

A footprint can't overlap another, run across the start line, or sit in a
fork's junction. Bank keys inside a loop's or jump's footprint do nothing
(the feature fades the bank out and back in); inside a roll they add to it.

### 3.1 Barrel roll (`RollFeature`)

The road turns once about the direction of travel; the centre line stays
yours. Comes with a magnetic zone that holds ships to the road.

| Setting | Default | Limit and why |
|---|---|---|
| `length` | 800 m | Peak roll rate is 1.5 × 360 / length °/m. Over 0.75°/m is an error (under ~720 m). 800 m (0.68°/m) was tested on Loop Lab; 460 m (1.2°/m) threw ships into the wall: the road 15 m off centre pitched ~24° |
| `direction`, `turns` | right, 1 | |
| `magnet_strength` | 1 | 1 = forgiving (crawl round upside down), 0 = needs speed |

It can sit on a gentle curve (the validator warns past 60° of turn under it).

### 3.2 Loop (`LoopFeature`)

Loop Lab's teardrop: a sin² pitch-curvature profile, 820 m of arc, 65 m top
radius, stepping sideways so the exit clears the entry. An S-jog before and
after moves the road out and back, so the exit lands exactly on your curve.

| Setting | Default | Notes |
|---|---|---|
| `loop_length` | 820 m | Top radius ≈ loop_length / 4π |
| `shift`, `side` | 90 m, right | How far the exit steps beside the entry |
| `jog_length` | 300 m | Each S-jog. Shorter = sharper. Footprint ≈ 2 × jog + the loop's forward travel (961 m by default) |
| `magnet_strength` | 1 | as the roll |

Put it on a straight, level stretch: the validator warns past 15° of turn or
3% grade under it. Inverted road needs light from below.

### 3.3 Jump (`JumpFeature`)

Fork Lab's jump: a climb (so the whole jump is height-neutral and the road
after it is where you drew it), a run-up, a kicker, a real gap with no road
or collision under it, a landing ramp and an outrun. A respawn trigger sits
under the gap.

| Setting | Default (Fork Lab's shared jump) |
|---|---|
| `kicker_deg` / `kicker_length` | 6° / 70 m |
| `gap` / `drop` | 55 m / 4 m |
| `landing_deg` / `landing_length` / `outrun` | 6° / 40 m / 80 m |
| `runup` | 64 m of level road before the kicker |
| `respawn_runup` | 250 m with no respawn points before the kicker |

**`clean_speed`** is the slowest lip speed that lands cleanly (hull at least
2.1 above the road, rebound at most 3.6 u/s). Don't guess it: run

```
godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/track_builder/measure_jumps_boot.gd -- --scene=res://scenes/tracks/<your_track>.tscn
```

It flies default_racer off each jump's exact shape at 40–120 u/s, stores the
result in the feature, rebuilds and saves. Change the jump's shape and the
value goes stale (the validator says so). Builder Lab's two jumps: 72 u/s
(the default shape) and 86 u/s (8°, 80 m gap, 5 m drop).

Put jumps on straight, level stretches (warnings past 10° / 3%). On a branch,
a jump is a risky shortcut: the AI judges it from `clean_speed`. On any track
with jumps, fork or not, the AI holds full throttle from 60 m before the
kicker to the lip, doesn't swerve for traffic there, and keeps its nose on
its velocity in the air.

### 3.4 Split track (`BranchFeature`)

A second route that leaves the main track and rejoins it; racers and the AI
choose. Under the BranchFeature, draw a `Path3D` named `BranchBase` (an
**open** curve) from a point on the main road to a later one. Its own
BankKeys, WidthKeys and JumpFeatures go under the BranchFeature too.

The builder:

- snaps the ends onto the main road: over the first and last
  `junction_blend` (150 m) the branch eases from the main centre line into
  what you drew;
- ends each junction where the two centre lines are 62 m apart (the inner
  walls clear of each other);
- **levels both roads across each junction** (height and bank: the junction
  road is built flat at one height), easing back to your heights at about 3%
  grade at most. The Report says how far it moved the road;
- builds the junctions (a flat Y with a splitter wedge), the branch road and
  walls, and a whole lap through the branch for the AI and the cameras.

Draw the branch well clear of the main road (it has to get 62 m away), and
make it leave and rejoin on the same side.

### 3.5 Boost pads (`BoostPadKey`)

Not a feature (it doesn't change the road): a `BoostPadKey` puts the game's
boost pad (`scenes/boost_pad.tscn`, 8 m wide, 12 m long) on the road. Drop
the node anywhere near the track, under the TrackBuilder (a `BoostPadKeys`
folder, say) or under a BranchFeature for that branch's road. The pads sit on
the road surface at the nearest point of the finished track (loops and rolls
included), facing the direction of travel, banked with the road.

| Setting | Default | What it does |
|---|---|---|
| `anchor` | centre | What `offset` is measured from: the centre line, or the left / right edge of the flat road. An edge-anchored pad stays against that edge where WidthKeys change the width |
| `offset` | 0 m | Sideways, + = right. From an edge, + / − moves the row in |
| `count` | 1 | Pads side by side (up to 5). Five need a wide road |
| `spacing` | 10 m | Centre to centre across the road (a pad is 8 m wide) |
| `strength` | 150 u/s | Added on top of the ship's speed |

What a pad does, measured on default_racer (`measure_boost`): +150 at full
speed takes a ship from ~116 to ~266 u/s, 178 u/s 80 m on, 136 u/s 160 m on,
back to normal by about 300 m. So a pad needs about 250 m of road after it
before anything tight. The validator follows that speed into the corners,
crests and jumps ahead (section 4).

The AI doesn't aim for pads: it gets the ones that are on its racing line.
On Builder Lab the field hits the centre row every lap and never the pads
against the edges.

### 3.6 Greebles (`GreebleZoneKey`)

Track dressing: lamps, wall panels, railings, light strips, pylons, gantries.
It uses the same styles, rules and greybox meshes as the Utopia, Swoopy and
Hairpin dressings (`tools/utopia`, `scenes/tracks/utopia/greebles/gb_*.tres`),
but with no survey. The greebles are placed straight from the built road, so
they follow WidthKeys, loops and rolls, and they leave gaps and junctions
bare by themselves.

**Build first.** Greebles sit on the built splines.

**Zones.** A `GreebleZoneKey` starts a zone. Drop one anywhere near the
built road, under the TrackBuilder (a `GreebleZoneKeys` folder, say). Its
style runs from there to the next key along the track. The lap wraps: the
last key's zone runs past the start line to the first key. A green gate and
label mark each zone's start in the editor.

Under a `BranchFeature`, a key dresses that branch. A branch with no key of
its own carries on with the main track's zone at the fork.

| Setting | Default | What it does |
|---|---|---|
| `preset` | None | A style from the library (`resources/greeble_presets`). None = a bare stretch |
| `style` | (from `preset`) | The style itself: drag any `UtopiaGreebleStyle` .tres here, or expand it to edit its rules |
| `mirror` | off | Swaps left and right rules. Turn chevrons belong on the outside wall: the presets put them on the right (left-hand corners), so mirror a zone of right-handers |
| `density` | 1 | Multiplies every rule's probability |
| `seed` | 1 | Reshuffles the random parts: probability, jitter and scale |
| `skip_layers` | none | Leaves layers out of this zone: ground, wall face, wall top, outside, overhead |

**Presets.** The library starts with the seven existing styles: civic,
garden, hairpin, maritime, service, skyway and sky_deck. These are copies, so
editing them doesn't touch Utopia or Swoopy.

- **Editing a preset changes every zone that uses it, on every track.** The
  TrackGreebles node picks rule edits up within half a second.
- To change one zone only, press **Make local copy**. The zone gets its own
  copy of the style (and its rules), saved in the scene. The meshes stay
  shared.
- To add a style to the library, type a name in `new_preset_name` and press
  **Save as preset**. It's saved as `style_<name>.tres`.

**Layers.** A rule's `layer` says where it sits:

| Layer | Where |
|---|---|
| ground | On the road. `lateral` scales with the flat road's half width |
| wall_face | On the inner face of the wall, 3 m up |
| wall_top | In the middle of the wall's flat top |
| outside | On the outer face of the wall, 3 m up |
| overhead | Centred between the wall tops |

Wall layers move with the road edge. Centred pieces wider than 20 m (seams,
gantries, trusses, portals) are stretched to span the road where WidthKeys
narrow or widen it. Stretched rules (`mesh_length`) fill their slot as
measured along their own rail: longer on the outside of a bend.

**Upright and surface offset.** Each rule also has these settings, in the
rule's *Upright and surface* group:

| Setting | Default | What it does |
|---|---|---|
| `upright` | 0 | 0 = the piece leans with the road (anything fixed to a surface). 1 = it stands vertical (light poles, masts, antennas). In between = part way. It turns about its attachment point. Overhead pieces ignore it, since their legs stand on both walls |
| `upright_axes` | bank and slope | What it straightens: both, the bank only (still leans along hills) or the slope only (still leans with the bank) |
| `upright_limit_deg` | 45° | Where the road tilts further than this from what `upright` aims for, the piece is left out. That covers loop walls, rolls and upside-down road. Only applies when `upright` is above 0 |
| `surface_offset` | 0 m | Along the surface's normal: + = away from it, − = into it, to hide edges. The surface is the road, the wall top, the inner face (+ = toward the track) or the outer face (+ = outward) |
| `auto_embed` | on | When `upright` tilts a piece standing on the road or a wall top, it's sunk just enough that no corner of its base floats |

The presets use it for the tall freestanding pieces:

- Lamp poles and antennas: `upright` 1.
- Masts and tall pylons outside the wall: `upright` 1 with a 30° limit and
  `surface_offset` 1.5 m. Upright, they'd otherwise clip the leaning wall
  above or below their attachment point on a steep bank.

The validator reports how many pieces the limits left out, and it flags
anything that `upright` swings into the track.

**Where pieces are left out:**

- Each piece only goes where its surface exists: ground on the road, wall
  layers on their wall, overhead where both walls stand. So jump gaps,
  junctions and the inner side of a fork stay bare.
- Overhead pieces, and any rule with `avoid_tunnels`, are left out in loops,
  rolls, from a jump's kicker to its landing end, and at the start line.
- Ground pieces stay off the boost pads and the start line.

**Live and built.** Moving a key or changing its settings re-dresses the
track about 0.2 s after you stop. That needs `greebles_live` on the
TrackBuilder. **Refresh greebles** does it by hand, and Build always does it.

The scene only saves the zones (the `TrackGreebles` node). The instances are
scattered when the track loads, so the file stays small and the greebles
always match the road. Builder Lab takes about 0.2 s to scatter 9,300
instances. Headless runs skip the scatter unless `FTF_GREEBLES=1` is set.

**Swapping in detail** works as on Utopia: overwrite a `gb_<name>.tres` with
your mesh (same pivot and axes), or point a rule at your model.

### 3.7 Road surface (`SurfaceZoneKey`)

The road's surface is drawn by the track surface shader (v38): lanes of
plate, ribbed plate and hex grate, channels with guide lights between them,
painted edge bands with LED rows, and hazard stripes on the lips. What runs
across the road is a **profile**. A `SurfaceZoneKey` picks the profile for a
stretch of track. Walls and junctions keep the grid for now.

**Build first.** Surface zones sit on the built splines, like greeble zones.
A track with no keys draws the default profile (industrial).

**Zones.** A `SurfaceZoneKey` starts a zone. Drop one anywhere near the built
road, under the TrackBuilder (a `SurfaceZoneKeys` folder, say). Its profile
runs from there to the next key, and the lap wraps. A blue gate and label
mark each zone's start in the editor; a blend also draws the blend's length
along the edges. Under a `BranchFeature` a key covers that branch, and a
branch with no key of its own carries on with the main track's profile at
the fork.

| Setting | Default | What it does |
|---|---|---|
| `preset` | industrial | A profile from the library (`resources/track_surface/profiles`) |
| `profile` | (from `preset`) | The profile itself: drag any `TrackSurfaceProfile` .tres here, or expand it to edit its bands |
| `blend_in` | 0 m | Cross-fades from the zone before over this many metres. 0 = a hard seam (with a seam line across the road) |
| `seed` | 1 | Reshuffles this zone's panel offsets, tints and vents |

At most **4 different profiles per path** (the main track, each branch): the
validator makes a 5th an error. Inside a blend the shader draws both
profiles, so keep blends to a few tens of metres.

**Profiles.** A `TrackSurfaceProfile` is a list of bands, left to right, each
a `TrackSurfaceBand`:

| Band setting | What it does |
|---|---|
| `type` | plate, channel, edge, ribbed or grate |
| `width` | Metres across (fixed bands) |
| `flex` | > 0: the band takes this share of what the fixed bands leave. Width keys only change flex bands |
| `light` | Channels: none, red dots or a blue strip |
| `vents` | Plates: vent boxes every so often |

With `mirror` on (the presets), the list runs from the left edge to the
centre band and the right half repeats it in reverse. Fixed bands stack in
from each real edge of the road, so edge bands stay on the edges where
WidthKeys change the width; a road narrower than the fixed bands squeezes
them all. At most 16 bands after mirroring. Put a **channel between two
different kinds of band**: the shader filters patterns, not switches between
them, so two lanes meeting without one can show a hard edge (the validator
warns).

The library starts with three presets: **industrial** (grates by the edges,
ribbed lanes, a wide centre with vents), **service** (plate lanes and a wide
ribbed centre) and **grate_run** (wide grates, smooth outer and centre
lanes). Editing a preset changes every zone that uses it, on every track.

**The track's own look.** The look all tracks share is the material
`shaders/track/track_surface_material.tres`. A track can deviate from it with
a `TrackSurfaceVariation` on the TrackBuilder (`surface_variation`): light,
plate, hazard, grate and vent colours, light energy, panel tint, vent
chance. A colour with alpha 0 or a number below 0 keeps the shared value.
Keep clear of orange: it's the boost pads' colour.

**Live and built.** Moving a key or changing a setting re-applies the surface
about 0.2 s after you stop (`surface_live` on the TrackBuilder). **Refresh
surface** does it by hand, and Build always does it. The scene only saves the
zones (the `TrackSurface` node). The per-path materials are made when the
track loads.

If you edit `profile_industrial.tres`, run `sync_surface_presets` (below) so
tracks without zones draw the new version too.

**Looking at it.** In game, key 9 cycles the surface debug views (bands,
panels, filter level, zones) and Shift+9 the quality tier. See
`DEBUG_KEYS.md`.

---

## 4. What the validator is telling you

Errors stop the track being right; warnings are things to look at. The limits
come from the circuits (measured with `measure_circuits`) and from Loop Lab
and Fork Lab.

| Message | What it means | What to do |
|---|---|---|
| *X has a non-identity transform* | Something moved a track node (the offset) | Reset its transform; edit the curve instead |
| *Build is out of date* | You changed something since the last Build | Build |
| *Road surface / normal off the spline* | The built road isn't where the spline says | Shouldn't happen: report it |
| *Built bank is off the keyed bank* | The tilt solve missed | Shouldn't happen: report it |
| *Roll rate over 0.7 °/m* (0.75 in a roll) | The bank changes too fast | Spread the bank keys further apart, or lengthen the roll |
| *Width changes over 0.1 m per m* | The wall cuts across the racing line | Spread the width keys |
| *Half width under 10 m* | Tight for 8 ships and respawn side-steps | Widen, or accept it as a design choice |
| *Key is more than 30 m from the track* | It may attach to the wrong stretch | Move it closer |
| *Corner over 15 g at 110 u/s* | Tighter than 99% of the circuits' corners | Open the corner or accept a hairpin |
| *Kink: curvature jumps over 1.0 g/m* | A sharp handle | Smooth the handles or raise `fairing_m` |
| *Grade over 50%* | Steeper than anything but The Drop | |
| *Crest needs over 110 u/s²* (error over 200) | The road falls away under a ship at its racing speed; past ~225 (gravity + the hover spring's pull) it launches | Soften the crest, or make it a jump |
| *Racing speed at the lip under clean_speed* | Ships arrive too slow for the jump | Move it after a straight, or make it smaller |
| *respawn_runup under 250 m* | A respawned ship can't get up to speed (Fork Lab measured 150–220 m) | Raise it |
| *Feature: the base turns / climbs under it* | The feature will be bent with your curve | Straighten that stretch, or accept it |
| *Feature starts right after the start line / runs into the grid* | | Move it |
| *Feature overlaps a junction* | The junction levels the road under it | Move it |
| *Junction isn't flat / level* | Shouldn't happen (the builder levels them) | Report it |
| *Main road isn't the standard width in a junction* | Junctions are fixed at 21.5 m | Move the WidthKeys out of the junction |
| *Branch never gets 62 m clear* | Drawn too close to the main road | Draw it further away |
| *Branch leaves on one side and rejoins on the other* | | Redraw it |
| *Only X m of clearance above the road* | Another part of the track is within 10 m overhead | Separate them |
| *The grid is on a bend / slope* | Over 1 g at 110 u/s or 3% grade | Move the StartKey to a straight |
| *Grid slot isn't over the road* | The road is too narrow there | Widen it, or move the start |
| *Respawn point with no road under it* (headless only) | | Report it |
| *Pad over the edge of the road* | Part of a pad is past the flat road (onto the lip) | Move it in, or fewer pads / less spacing |
| *Pads overlap* | | Move them apart |
| *Pad over a jump's gap* / *on a kicker* | Nothing under it / it changes the take-off (`clean_speed` is measured without a pad) | Move it off the jump |
| *Pad on the starting grid* | Ships start on or just behind it | Move it |
| *Pad: no road under part of it* / *an end sits off the road* | Seen on the built road: off the edge, or a 12 m flat pad on a tight crest or dip | Move it |
| *The boost carries X u/s into the bend* | A ship that takes the pad and doesn't brake is over what default_racer can steer there | Move the pad further from the bend, or lower `strength` |
| *Boosted, the crest needs X u/s²* | The extra speed turns a crest into a launch (thresholds as above) | Move the pad or soften the crest |
| *The boost carries X u/s to a jump's lip* | Landings are only measured up to 120 u/s | Move the pad, or measure the jump faster (`MJ_SPEEDS`) and check the landing |
| *GreebleZoneKey is more than 30 m from the track* | It may attach to the wrong stretch | Move it closer |
| *Two greeble keys start zones within 2 m* | One of them does nothing | Delete or move one |
| *Style has no enabled rule with a mesh* | The zone would be bare | Pick another preset, or None if bare is what you want |
| *Greebles are out of date* / *not built yet* | The keys changed since the zones were written (live refresh off, or a headless edit) | Build, or Refresh greebles |
| *Greebles …: reaches into the track* | A piece is inside the flat road below 10 m (the track clearance), where ships and the camera go | Fix the rule's offset, lateral or scale, or skip that layer in the zone |
| *Greebles …: X m tall on the road* | A ground piece over 0.3 m: ships hover at about 2 m, and it reads as an obstacle | Scale it down, or move it to a wall layer |

---

## 5. Adding the track to the game

1. Save the scene as `scenes/tracks/<id>.tscn` (the game finds it by id).
2. Make `resources/tracks/<id>.tres`, a TrackProfile with `track_id = "<id>"`
   and a display name (copy `builder_lab.tres`).
3. Add it to `resources/tracks/track_manifest.tres`.

---

## 6. Training the AI

On **default_racer**, from a fresh bake:

1. Add the scene to `TRACKS` in `tools/train_ai_lines.gd` (and to `ROUTES`
   as `[-1, 0, ...]` if it has branches: one line per route lap).
2. Run
   ```
   godot --headless --path full_throttle_flux res://tools/train_ai_lines.tscn -- --track=<id> --fresh
   ```
3. Race it:
   ```
   PROBE_TRACK=<id> PROBE_SECONDS=240 PROBE_SEED=1234 godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/dev/ai_race_probe_boot.gd
   ```
   Look for 0 respawns, wall contacts, (with a fork) the shortcut's take
   rate, and (with boost pads) the `BOOST` lines: pad hits per ship and wall
   contacts that began while boosted.

Retrain whenever you rebuild after changing the geometry: the trained line
is tied to the road it was driven on.

---

## 7. The four circuits keep their offset

Utopia, Swoopy, Hairpin Alley and The Drop were built with the rotated
geometry nodes. Fixing them would move their roads by up to 21 m and change
how they drive, so they stay as they are. The runtime copes: respawns,
magnetic zones and the cameras find the road by ray-casting it rather than
trusting the spline (v33), and set dressing uses `UtopiaKit.road_xf`. Builder
tracks need none of that.

---

## Running the tools

```
# build and validate headless (the editor buttons do the same)
godot --headless --path full_throttle_flux -s res://tools/track_builder/build_boot.gd -- --scene=res://scenes/tracks/<id>.tscn
godot --headless --path full_throttle_flux -s res://tools/track_builder/validate_boot.gd -- --scene=res://scenes/tracks/<id>.tscn
# measure jumps
godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/track_builder/measure_jumps_boot.gd -- --scene=res://scenes/tracks/<id>.tscn
# the validator's own self-test (on Builder Lab)
godot --headless --path full_throttle_flux -s res://tools/track_builder/validator_selftest_boot.gd
# what a boost pad does to default_racer, against the validator's model
godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/track_builder/measure_boost_boot.gd
# greebles headless: counts, pieces left out by upright limits, intrusions, a checksum
godot --headless --path full_throttle_flux -s res://tools/track_builder/greeble_stats_boot.gd -- --scene=res://scenes/tracks/<id>.tscn
# road surface: make missing preset profiles, sync the industrial preset into the material
godot --headless --path full_throttle_flux -s res://tools/track_surface/sync_surface_presets.gd
# road surface: shots, debug views and aliasing measurements (needs a display; v38 notes)
godot --path full_throttle_flux -s res://tools/dev/track_surface_shots_boot.gd
# greebles: chase-camera shots at every zone, plus scatter stats (needs a display)
TB_SCENE=res://scenes/tracks/<id>.tscn TB_OUT=/tmp/shots xvfb-run -s "-screen 0 1600x900x24" \
  godot --rendering-driver opengl3 --path full_throttle_flux -s res://tools/track_builder/greeble_shots_boot.gd
```

The full detail and the measurements behind every number are in
`FTF_v34_NOTES.md` at the repo root.
