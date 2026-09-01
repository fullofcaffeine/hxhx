/**
	Describes what Stage3 can prove about one source argument and one declared
	parameter.

	`Unknown` is intentionally different from `Compatible`: incomplete bootstrap
	typing must not justify skipping an optional parameter. The caller can still
	place an unknown argument in its current positional slot.
**/
enum EmitterCallArgCompatibility {
	Compatible;
	Incompatible;
	Unknown;
}
