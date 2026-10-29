package callers;

class Gapped {
	static function run(value:Int):Int {
		return switch (value) {
			case other if (other > 0): macros.Macros.items();
			case _: 0;
		};
	}
}
