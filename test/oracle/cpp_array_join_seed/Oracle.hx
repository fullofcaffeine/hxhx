/** Observe native Array.join without relying on the managed backend's conversion rules. */
class Oracle {
	static var effects = "";

	static function receiver(mode:String):Array<Int> {
		effects += "r";
		if (mode == "receiver")
			throw "receiver";
		return mode == "null" ? null : [1, 2];
	}

	static function separator(mode:String):String {
		effects += "s";
		if (mode == "separator")
			throw "separator";
		return ":";
	}

	static function main():Void {
		final mode = Sys.args().length == 0 ? "values" : Sys.args()[0];
		if (mode != "values") {
			try
				Sys.println("result=" + receiver(mode).join(separator(mode)))
			catch (error:String)
				Sys.println("error=" + error);
			Sys.println("effects=" + effects);
			return;
		}
		final empty:Array<Int> = [];
		final nullable:Array<Null<Int>> = [1, null, -2];
		Sys.println("empty=" + empty.join("::"));
		Sys.println("ints=" + [1, -2, 0].join("::"));
		Sys.println("bools=" + [true, false].join("|"));
		Sys.println("strings=" + ["a", null, "", "é"].join("|"));
		Sys.println("nullable=" + nullable.join("|"));
		Sys.println("null-separator=" + ["a", "b", "c"].join(null));
		Sys.println("nested=" + [[1, 2], [], [3]].join("|"));
		Sys.println("objects=" + [new OracleItem(1), new OracleItem(2)].join("|"));
		Sys.println("object-effects=" + effects);
		// Known erased values probe the native Boolean-array recovery boundary.
		final values:Array<Dynamic> = [0, 1, null, "x"];
		final erased:Dynamic = values;
		final recovered:Array<Bool> = erased;
		Sys.println("recovered=" + recovered.join("|"));
	}

	public static function effect(value:Int):Void
		effects += Std.string(value);
}

/** A conversion with observable effects distinguishes value formatting from object dispatch. */
class OracleItem {
	final value:Int;

	public function new(value:Int)
		this.value = value;

	public function toString():String {
		Oracle.effect(value);
		return "item" + value;
	}
}
