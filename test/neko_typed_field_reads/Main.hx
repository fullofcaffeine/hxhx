/** Observes ordinary field access and null failures through typed Haxe expressions. */
class Main {
	static function main():Void {
		var present:{value:String} = {value: "present"};
		Sys.println(present.value);
		var missing:{value:String} = null;
		var result = try {
			missing.value;
		} catch (error:Dynamic) {
			"NPE";
		};
		Sys.println(result);
		Sys.println(present.value);
	}
}
