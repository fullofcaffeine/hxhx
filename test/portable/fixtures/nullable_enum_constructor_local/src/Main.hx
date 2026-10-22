enum Statement {
	Empty(position:Int);
	Branch(condition:Bool, yes:Statement, no:Null<Statement>);
}

typedef MaybeStatement = Null<Statement>;

/** Observes nullable payload arguments without relying on compiler parser code. */
class Main {
	static function build(present:Bool):Statement {
		final branch:Null<Statement> = present ? Empty(7) : null;
		return Branch(true, Empty(1), branch);
	}

	static function optimized():Statement {
		final branch:Null<Statement> = true ? Empty(9) : null;
		return Branch(true, Empty(1), branch);
	}

	static function aliased():Statement {
		final branch:MaybeStatement = true ? Empty(11) : null;
		return Branch(true, Empty(1), branch);
	}

	static function describe(value:Statement):String {
		return switch value {
			case Branch(_, _, null): "null";
			case Branch(_, _, Empty(position)): 'empty:$position';
			case _: "other";
		};
	}

	static function main():Void {
		Sys.println(describe(build(false)));
		Sys.println(describe(build(true)));
		Sys.println(describe(optimized()));
		Sys.println(describe(aliased()));
	}
}
