/** Keeps an enum declaration in the same program as a recursive module group. */
enum Marker {
	Ready;
}

/** Both original module paths must remain callable after recursive grouping. */
class Main {
	static function main() {
		final marker = Marker.Ready;
		switch (marker) {
			case Ready:
				Sys.println(CycleLeft.value(3));
				Sys.println(CycleRight.value(4));
				Sys.println(CycleLeft.tag);
		}
		final left = new TypeLeft();
		final right = new TypeRight();
		left.other = right;
		right.other = left;
		if (left.other != right || right.other != left)
			throw "mutually referential record identity changed";
		Sys.println(TypeLeft.tag + ":" + TypeRight.tag);
	}
}
