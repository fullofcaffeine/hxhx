/** Exercises valid Haxe names that overlap with OCaml keywords and escaped names. */
class Main {
	public function new() {}

	public function effect():Int
		return 11;

	public function effect_():Int
		return 22;

	public function hx_effect():Int
		return 55;

	static function main():Void {
		final instance = new Main();
		Sys.println(instance.effect());
		Sys.println(instance.effect_());
		final effect = 33;
		final effect_ = 44;
		Sys.println(effect);
		Sys.println(effect_);
		Sys.println(instance.hx_effect());
		final hx_effect = 66;
		Sys.println(hx_effect);
	}
}
