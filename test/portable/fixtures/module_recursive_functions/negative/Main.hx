/** Keeps the eager initializer reachable in the rejected recursive program. */
class Main {
	static function main() {
		Sys.println(CycleLeft.boot + CycleLeft.value(3));
	}
}
