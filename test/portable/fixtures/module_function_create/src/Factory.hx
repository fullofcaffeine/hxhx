/** A module-level factory must not acquire a synthetic class constructor. */
function create(value:Int):Int {
	return value + 1;
}
