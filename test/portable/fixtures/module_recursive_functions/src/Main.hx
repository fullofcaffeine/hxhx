/** Both original module paths must remain callable after recursive grouping. */
class Main {
	static function main() {
		Sys.println(CycleLeft.value(3));
		Sys.println(CycleRight.value(4));
	}
}
