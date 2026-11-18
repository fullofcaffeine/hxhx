import hxhx.Stage3SetupSupport;

/**
	hxhx must set the `target.*` defines that upstream Haxe 4.3.7 sets, because the Haxe 4.3
	standard library selects code with them (`haxe.Timer`, `sys.thread`, `haxe.MainLoop`,
	string and Unicode helpers). The expected values were observed from upstream Haxe 4.3.7 with
	`haxe.macro.Context.getDefines()`: `--js` for JavaScript, and stock Haxe with `-lib
	reflaxe.ocaml` for the OCaml routes, so both OCaml hosts see the same defines.
**/
class M14TargetDefinesTest {
	static function expectDefines(label:String, defines:haxe.ds.StringMap<String>, expected:Map<String, String>, absent:Array<String>):Void {
		for (name => value in expected)
			if (defines.get(name) != value)
				throw label + ": " + name + " should be '" + value + "', got '" + defines.get(name) + "'";
		for (name in absent)
			if (defines.exists(name))
				throw label + ": " + name + " must not be defined";
	}

	static function main():Void {
		expectDefines("js", Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), [
			"target.name" => "js",
			"target.unicode" => "1",
			"target.utf16" => "1",
			"target.atomics" => "1"
		], ["target.static", "target.threaded"]);
		expectDefines("ocaml", Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml-native"), [
			"target.name" => "cross",
			"target.static" => "1",
			"target.sys" => "1",
			"target.threaded" => "1",
			"target.unicode" => "1",
			"target.utf16" => "1"
		], ["target.atomics"]);
		expectDefines("explicit define wins", Stage3SetupSupport.buildDefinesMap(["target.name=custom"], "js", "js-native"), ["target.name" => "custom"], []);
		Sys.println("M14_TARGET_DEFINES:PASS");
	}
}
