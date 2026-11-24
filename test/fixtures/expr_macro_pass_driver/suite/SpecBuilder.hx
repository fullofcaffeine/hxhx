package suite;

/**
	Macro owner for `SuiteMain`. Each body has a nested block whose local ends an
	object-literal initializer with `}` and no `;`. Before the parser accepted that
	(haxe_ocaml-2oi7y), this module failed to load and the calls in `SuiteMain`
	were silently typed as ordinary calls.
**/
class SpecBuilder {
	public static macro function names(basePath:String):haxe.macro.Expr {
		final found = [];
		function add(name:String) {
			final spec = {
				name: name,
				count: 1
			}
			found.push(spec.name);
		}
		add(basePath);
		return macro $v{found};
	}

	macro static public function register(dir:String, pack:String):haxe.macro.Expr {
		final parts = [];
		for (part in [dir, pack]) {
			final entry = {
				text: part
			}
			parts.push(entry.text);
		}
		return macro Sys.println($v{parts.join(":")});
	}
}
