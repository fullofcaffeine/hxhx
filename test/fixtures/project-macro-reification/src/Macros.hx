import haxe.macro.Expr;

/**
	A project expression macro that assembles its result with reification.

	`tally(["alpha", "beta"])` expands to a block that prints one line per label, keeps the
	labels in a local array, reports whether there are many, and evaluates to the label count.
	The block is written with `macro { ... }` and the splices `$b{}`, `$v{}` (String, Int,
	`Null<Int>`, Bool, `Array<String>`), `$i{}`, `$e{}`, `$a{}`, `$p`-free field splices
	(`seen.$field`) and `@:pos`. It calls no `haxe.macro.Context` API.
**/
class Macros {
	public static macro function tally(labels:Expr):Expr {
		return build(labels);
	}

	/** The reified result; a plain function so a probe can print it in both compilers. */
	public static function build(labels:Expr):Expr {
		final names = labelsOf(labels);
		final lines = [
			for (index in 0...names.length) {
				final text = names[index].toUpperCase();
				final some:Null<Int> = index + 1;
				final printed = macro $v{text} + ":" + $v{index} + ":" + $v{some} + ":" + $v{index > 0};
				macro @:pos(labels.pos) Sys.println($printed);
			}
		];
		final count = names.length;
		final field = "length";
		final sink = "println";
		final tail = [macro "tail", macro $v{count}];
		return macro {
			$b{lines};
			final seen = $v{names};
			Sys.println("seen=" + seen.$field);
			if ($v{count > 1})
				Sys.$sink("many")
			else
				Sys.println("few");
			Sys.println(join($a{tail}));
			$e{macro $v{count}};
		};
	}

	static function labelsOf(labels:Expr):Array<String> {
		return switch labels.expr {
			case EArrayDecl(values):
				[
					for (value in values)
						switch value.expr {
							case EConst(CString(text, _)):
								text;
							case _:
								throw "tally expects string literals";
						}
				];
			case _:
				throw "tally expects an array literal";
		};
	}
}
