/** A module function belongs to its module even when a secondary class holds it internally. */
function moduleOnly():Bool
	return true;

/** Explicitly importing this type must not import the module function. */
class Secondary {}
