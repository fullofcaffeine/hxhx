#if macro
import haxe.macro.Expr;
#end

/**
	A macro class whose module also holds a runtime type test (`Std.isOfType` against a class), as
	`haxe.Exception.caught` does for upstream's test builder through its `try`/`catch`.
**/
class Checks {
	static function isMarker(value:Dynamic):Bool
		return Std.isOfType(value, Marker);

	public static macro function describe(label:String):haxe.macro.Expr {
		#if macro
		final kind = isMarker(new Marker()) ? "marker" : "other";
		return macro $v{kind + " " + label};
		#else
		return null;
		#end
	}
}

class Marker {
	public function new() {}
}
