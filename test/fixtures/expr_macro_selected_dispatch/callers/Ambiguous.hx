package callers;

class Ambiguous {
	static function run():Int {
		return macros.Overloaded.pick("text");
	}
}
