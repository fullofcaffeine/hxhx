/** A host supplies mixed values so array checks cannot depend on their written Haxe types. */
@:native("Probe")
extern class Probe {
	public static function value(slot:Int):Dynamic;
	public static function observe(value:Bool):Void;
	public static function sameType(type:Class<Array<Dynamic>>):Bool;
	public static function done():Void;
}

/** Core type values remain native Array even inside closures and shadowing scopes. */
class Main {
	static final startup:Class<Array<Dynamic>> = Array;

	static function shadow(value:Dynamic, Array:Int):Bool {
		return value is Array;
	}

	static function selected():Class<Array<Dynamic>> {
		return Array;
	}

	static function main():Void {
		Probe.observe(Probe.sameType(startup));
		Probe.observe(Probe.sameType(selected()));
		Probe.observe(shadow(Probe.value(0), 7));
		final test = () -> (Probe.value(1) is Array);
		Probe.observe(test());
		Probe.observe(Probe.value(2) is Array);
		Probe.observe(Probe.value(3) is Array);
		Probe.observe(Probe.value(4) is Array);
		Probe.observe(Probe.value(5) is Array);
		Probe.observe(Probe.value(6) is Array);
		Probe.observe(Probe.value(7) is Array);
		Probe.observe(Probe.value(8) is Array);
		Probe.observe(Probe.value(9) is Array);
		Probe.observe(Probe.sameType(selected()));
		Probe.done();
	}
}
