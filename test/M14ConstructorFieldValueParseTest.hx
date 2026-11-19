/**
	Haxe 4.3.7 accepts a constructor as a function value: `A.new`, `[A.new, B.new]`, and
	`Name.new.bind("hey")`. After `.`, the keyword `new` is a field name.

	The hxhx parser accepted only identifiers after `.`, so it failed with "Expected field name".
	Six upstream unit-suite modules failed for this reason (haxe_ocaml-rsbh4). `new A()` must keep
	its meaning.
**/
class M14ConstructorFieldValueParseTest {
	static function bodyOf(statements:String):Array<HxStmt> {
		final source = "class Main {\n\tstatic function main() {\n" + statements + "\n\t}\n}\n";
		final decl = try ParserStage.parse(source, "Main.hx").getDecl() catch (e:haxe.Exception) throw "parse failed: " + e.message;
		final main = HxClassDecl.getFunctions(HxModuleDecl.getClasses(decl)[0])[0];
		return HxFunctionDecl.getBody(main);
	}

	static function initializer(statement:HxStmt):HxExpr {
		return switch statement {
			case SVar(_, _, init, _, _) if (init != null): init;
			case _: throw "expected a variable with an initializer, got " + statement;
		};
	}

	static function check(label:String, condition:Bool):Void {
		if (!condition)
			throw label;
	}

	static function main():Void {
		final body = bodyOf("\t\tfinal make = A.new;\n\t\tfinal makers = [A.new, B.new];\n\t\tfinal named = Name.new.bind(\"hey\");\n\t\tfinal made = new A(1);");
		check("four statements", body.length == 4);

		final make = initializer(body[0]);
		check("A.new is a field read: " + make, switch make {
			case EField(EIdent("A"), "new"): true;
			case _: false;
		});

		final makers = initializer(body[1]);
		check("[A.new, B.new]: " + makers, switch makers {
			case EArrayDecl([EField(EIdent("A"), "new"), EField(EIdent("B"), "new")]): true;
			case _: false;
		});

		final named = initializer(body[2]);
		check("Name.new.bind: " + named, switch named {
			case ECall(EField(EField(EIdent("Name"), "new"), "bind"), [_]): true;
			case _: false;
		});

		final made = initializer(body[3]);
		check("new A(1) is a construction: " + made, !made.match(EField(_, _)) && !made.match(ECall(EField(_, "new"), _)));

		Sys.println("M14_CONSTRUCTOR_FIELD_VALUE_PARSE:PASS");
	}
}
