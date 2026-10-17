/** Calls precede both declarations so the shared typer must refine their body results. */
class Main {
	static function main():Void {
		consume(7);
		Sys.println(answer("ignored"));
	}

	static function consume<T>(value:T) {
		Sys.println("effect");
	}

	static function answer<T>(value:T) {
		return 9;
	}
}
