/**
	Chooses one focused section of a large M14 smoke test.

	The normal test commands leave `HXHX_M14_SMOKE_GROUP` unset and therefore run
	every section. Focused package scripts set the variable to one documented group
	name so contributors can retry only the area they are changing.
**/
class M14SmokeGroupSelection {
	public static function selected(available:Array<String>):String {
		final requested = Sys.getEnv("HXHX_M14_SMOKE_GROUP");
		if (requested == null || requested.length == 0 || requested == "all")
			return "all";
		if (available.indexOf(requested) < 0)
			throw 'unknown M14 smoke group `${requested}`; choose one of: all, ${available.join(", ")}';
		return requested;
	}
}
