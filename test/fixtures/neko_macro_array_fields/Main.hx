import haxe.macro.Expr;

/** Public arrays inside quoted syntax retain the same identity and methods as ordinary arrays. */
class Main {
	static function main():Void {
		final array = macro [1, 2];
		switch array.expr {
			case EArrayDecl(items):
				Sys.println(Type.getClass(items) == Array);
				Sys.println(items.length);
				Sys.println(items.push(macro 3));
				switch items[2].expr {
					case EConst(CInt(value, _)): Sys.println(value);
					case _: throw "unexpected appended quote";
				}
			case _:
				throw "unexpected array quote";
		}

		final block = macro {1; 2;};
		switch block.expr {
			case EBlock(statements):
				Sys.println(Type.getClass(statements) == Array);
				Sys.println(statements.length);
			case _:
				throw "unexpected block quote";
		}

		final call = macro call(1, 2);
		switch call.expr {
			case ECall(_, arguments):
				Sys.println(Type.getClass(arguments) == Array);
				Sys.println(arguments.length);
			case _:
				throw "unexpected call quote";
		}

		final path = macro :demo.pkg.Widget;
		switch path {
			case TPath(typePath):
				Sys.println(Type.getClass(typePath.pack) == Array);
				Sys.println(typePath.pack.join("."));
				Sys.println(Type.getClass(typePath.params) == Array);
				Sys.println(typePath.params.length);
			case _:
				throw "unexpected type path";
		}

		final arrow = macro :Int->String;
		switch arrow {
			case TFunction(parameters, _):
				Sys.println(Type.getClass(parameters) == Array);
				Sys.println(parameters.length);
			case _:
				throw "unexpected function type";
		}
	}
}
