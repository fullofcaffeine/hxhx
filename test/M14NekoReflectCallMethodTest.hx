/**
	Typed methods, static functions and local functions passed as
	`haxe.Constraints.Function` (as in `Reflect.callMethod`) must run on the
	Neko route exactly as upstream Haxe runs them (haxe_ocaml-6zeuc).
**/
class M14NekoReflectCallMethodTest {
	static function main():Void {
		NekoRuntimeFixture.exercise("test/fixtures/reflect_call_method", false);
	}
}
