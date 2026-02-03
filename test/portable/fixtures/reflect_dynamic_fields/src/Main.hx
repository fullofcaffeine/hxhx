class Main {
	static function main() {
		var o:{} = {};
		Reflect.setField(o, "x", 123);
		final has = Reflect.hasField(o, "x");
		final v:Dynamic = Reflect.field(o, "x");

		var d:Dynamic = {};
		d.y = 456;

		final missing = Reflect.field(o, "nope");

		Sys.println("has=" + has + ",val=" + v + ",dyn=" + d.y + ",missing=" + missing);
	}
}
