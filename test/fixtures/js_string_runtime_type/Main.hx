/** Mixed host values exercise primitive versus boxed String behavior at the typed extern boundary. */
@:native("Probe") extern class Probe {
	public static function value(slot:Int):Dynamic;
	public static function observe(value:Bool):Void;
	public static function sameType(type:Class<String>):Bool;
	public static function done():Void;
}

/** String type values follow the host binding; primitive instance tests do not. */
class Main {
	static final startup:Class<String> = String;

	static function selected():Class<String> {
		return String;
	}

	static function shadow(value:Dynamic, String:Int):Bool {
		return value is String;
	}

	static function main():Void {
		Probe.observe(Probe.sameType(startup));
		Probe.observe(Probe.sameType(selected()));
		Probe.observe(shadow(Probe.value(0), 7));
		Probe.observe(Probe.value(1) is String);
		Probe.observe(Probe.value(2) is String);
		Probe.observe(Probe.value(3) is String);
		Probe.observe(Probe.value(4) is String);
		Probe.observe(Probe.value(5) is String);
		Probe.observe(Probe.value(6) is String);
		Probe.observe(Probe.value(7) is String);
		Probe.observe(Probe.value(8) is String);
		Probe.observe(Probe.sameType(selected()));
		Probe.observe(Probe.sameType(startup));
		Probe.observe(Probe.value(9) is String);
		Probe.done();
	}
}
