/**
	Exercises the call shape produced by the macro-host entrypoint generator.

	The generator does not know each entrypoint's return type. It therefore uses
	`untyped` and stores the result as `Dynamic`. An exact Void call must keep its
	sealed call plan even though the typed call occurrence has a Dynamic result.
**/
class Main {
	static function afterEntrypoint(value:Dynamic):Void {
		Sys.println(value == null ? "after=null" : "after=value");
	}

	static function main():Void {
		final result:Dynamic = untyped GeneratedEntrypoint.init();
		afterEntrypoint(result);
		Sys.println(Std.isOfType(result, String) ? (cast result : String) : "ok");
	}
}
