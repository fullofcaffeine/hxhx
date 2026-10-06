class Main {
	static final initialized:String = Std.string(false);

	static function boolValue(value:Bool):Bool
		return value;

	static function text(value:Bool):String
		return Std.string(value);

	static function nullableText(value:Null<Bool>):String
		return Std.string(value);

	static function effect():Bool {
		Sys.println("effect");
		return true;
	}

	static function main():Void {
		Sys.println(Std.string(true));
		Sys.println(Std.string(false));
		Sys.println(Std.string(0));
		Sys.println(Std.string(1));
		final yes:Bool = true;
		final no:Bool = false;
		Sys.println(Std.string(yes));
		Sys.println(Std.string(no));
		Sys.println(Std.string(1 < 2));
		Sys.println(Std.string(1 > 2));
		Sys.println(Std.string(boolValue(false)));
		Sys.println(text(true));
		Sys.println(text(false));
		var dynamicValue:Dynamic = true;
		Sys.println(Std.string(dynamicValue));
		dynamicValue = false;
		Sys.println(Std.string(dynamicValue));
		final zero:Dynamic = 0;
		Sys.println(Std.string(zero));
		Sys.println(Std.string(null));
		Sys.println(Std.string("done"));
		Sys.println(Std.string(effect()));
		Sys.println(initialized);
		Sys.println(nullableText(null));
		Sys.println(nullableText(true));
		Sys.println(nullableText(false));
	}
}
