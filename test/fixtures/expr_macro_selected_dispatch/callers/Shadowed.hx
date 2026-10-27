package callers;

class Shadowed {
	static function run(macros:{Macros:{items:Void->Int}}):Int {
		return macros.Macros.items();
	}
}
