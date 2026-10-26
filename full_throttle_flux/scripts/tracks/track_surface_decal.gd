@tool
extends Resource
class_name TrackSurfaceDecal
## One resolved road decal of a Track Builder track (v38 phase 5), written by
## the Track Builder from a SurfaceDecalKey: text in one of the four decal
## fonts, or an analytic shape, painted flat on the road at a distance along
## path `path_index` of TrackSurface.paths. TrackSurface lays it out into
## glyph records for the shader.
##
## Never edit these by hand: move or change the SurfaceDecalKey and the
## builder rewrites them.

## The decal fonts' jobs (docs: Typography). Same order as the atlas roles.
enum Role {
	WORD,     ## BBH Bartle: hero road words. Caps only.
	STENCIL,  ## Alien Block: short hazard stencils.
	LABEL,    ## Audiowide: numbers and technical labels.
	SERIAL,   ## Libre Barcode 39 Extended Text: panel serials (close-up).
}

enum Shape {
	TEXT,
	CHEVRON,  ## A ^ pointing along the track.
	ARROW,    ## A shaft and head pointing along the track.
}

## Where `offset` is measured from (as BoostPadKey).
enum Anchor {
	CENTRE,
	LEFT,     ## The left edge of the driving surface; + offset moves it in.
	RIGHT,    ## The right edge; - offset moves it in.
}

## Paint, as the shader's decal colours (no orange: the boost pads own it).
enum Paint {
	WHITE,
	YELLOW,
	RED,
	BLUE,
}

@export var path_index := 0
## Metres along the path where the decal (its first copy) starts.
@export var distance := 0.0
@export var anchor: Anchor = Anchor.CENTRE
@export var offset := 0.0
@export var shape: Shape = Shape.TEXT
@export var role: Role = Role.WORD
@export var text := ""
## Text: glyph height (em) in metres. Shapes: length along the track.
@export var size := 4.0
## Shapes: width across.
@export var width := 4.0
@export var paint: Paint = Paint.WHITE
## 0..1: how strongly it glows (lit paint).
@export var glow := 0.0
## 0..1: paint opacity.
@export var opacity := 0.9
## Copies along the track, `spacing` metres apart (start to start).
@export var count := 1
@export var spacing := 10.0
## Text that reads for a ship coming the other way (upside down for us).
@export var flipped := false
## The SurfaceDecalKey this came from (for reports and the validator).
@export var key_name := ""
