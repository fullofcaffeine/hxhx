/** Observes native conversion arguments once and a same-named ordinary class. */
class Main {
	static function source():String {
		Sys.println("argument");
		return "native";
	}

	static function main():Void {
		Sys.println(new String(source()));
		final ordinary = new ordinary.String(7);
		Sys.println(ordinary.value);
	}
}
