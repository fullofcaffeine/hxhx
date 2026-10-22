/** Makes both literal-bearing modules reachable through ordinary Haxe calls. */
class Main {
	static function main() {
		Sys.println(CycleLeft.value(3));
	}
}
