class Main {
	static function main() {
		final ex = new haxe.ValueException("boom");
		Sys.println("message=" + ex.message + ",value=" + ex.value);
	}
}
