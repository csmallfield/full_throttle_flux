@tool
extends ProfileKey
class_name BankKey
## Road bank at one point of the track (v34). Between keys the bank eases from
## one value to the next. The builder turns the profile into solved curve
## tilts; never type tilts by hand.

## Degrees. + = the road leans right (right edge low): bank into a right turn.
@export_range(-80.0, 80.0, 0.5, "suffix:°") var bank_deg: float = 0.0:
	set(v):
		bank_deg = v
		_changed()


func label_text() -> String:
	return "%+.1f°" % bank_deg
