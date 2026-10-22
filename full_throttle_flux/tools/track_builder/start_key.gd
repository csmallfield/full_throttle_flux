@tool
extends ProfileKey
class_name StartKey
## Where the start/finish line goes (v34). Drop it anywhere near the track;
## the line sits on the nearest track point, facing the direction of travel,
## and the grid forms up behind it. One per track. No StartKey = the line is
## at the first point of the BaseSpline.
##
## The generated MainSpline starts `start_lead` metres (TrackBuilder, default
## 30) before the line, as on Fork Lab, so distance 0 is just behind the line.


func label_text() -> String:
	return "START"
