/** Observes the generated registry after upstream startup without depending on its implementation. */
class Main {
	static function main():Void {
		Sys.println(untyped (neko.Boot.__classes.Int == Int));
		Sys.println(untyped (neko.Boot.__classes.Main == Main));
		Sys.println(untyped (neko.Boot.__classes.haxe.Exception == haxe.Exception));
		// Intentional unchecked writes observe the target's mutable class-binding boundary.
		var original:Dynamic = Int;
		untyped Int = {tag: "replaced"};
		Sys.println(untyped (neko.Boot.__classes.Int == Int));
		Sys.println(untyped (neko.Boot.__classes.Int == original));
		untyped Int = original;
	}
}
