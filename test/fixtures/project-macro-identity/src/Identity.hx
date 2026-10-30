import haxe.macro.Expr;

/**
	A project expression macro that returns its argument unchanged.

	Before returning, it checks that it received the authored function: the written
	signature, the nested brace group, both explicit returns, and the statements that
	follow the group. Any difference fails compilation instead of producing a program
	whose behavior silently changed. The checks use only the public `haxe.macro.Expr`
	tree; they call no `haxe.macro.Context` API.
**/
class Identity {
	public static macro function preserve(value:Expr):Expr {
		final fn:Function = functionOf(value);
		final args:Array<FunctionArg> = fn.args;
		require(args.length == 1, "expected one parameter");
		final parameter:FunctionArg = args[0];
		require(parameter.name == "label", "parameter name changed");
		require(parameter.opt != true, "parameter became optional");
		require(typeName(parameter.type) == "String", "parameter type changed");
		require(typeName(fn.ret) == "String", "return type changed");

		final body:Array<Expr> = blockOf(fn.expr, "function body");
		require(body.length == 3, "function body statement count changed");
		final group:Array<Expr> = blockOf(body[0], "nested group");
		require(group.length == 2, "nested group statement count changed");
		final guarded:Expr = ifBranchOf(group[0]);
		final guardedBody:Array<Expr> = blockOf(guarded, "guarded branch");
		require(guardedBody.length == 1, "guarded branch statement count changed");
		require(identOf(returnedOf(guardedBody[0])) == "label", "guarded return changed");
		require(pushedOf(group[1]) == "inner-fallthrough", "group fallthrough changed");
		require(pushedOf(body[1]) == "after-group", "statement after the group changed");
		require(stringOf(returnedOf(body[2])) == "unreachable", "final return changed");
		return value;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw "Identity.preserve: " + message;
	}

	static function functionOf(value:Expr):Function {
		return switch value.expr {
			case EFunction(FAnonymous, f): f;
			case _: throw "Identity.preserve: expected an anonymous function";
		}
	}

	static function typeName(type:Null<ComplexType>):String {
		return switch type {
			case null: "<none>";
			case TPath(path): path.pack.length == 0 && path.sub == null ? path.name : "<qualified>";
			case _: "<other>";
		}
	}

	static function blockOf(value:Null<Expr>, label:String):Array<Expr> {
		if (value == null)
			throw "Identity.preserve: missing " + label;
		return switch value.expr {
			case EBlock(entries): entries;
			case _: throw "Identity.preserve: " + label + " lost its braces";
		}
	}

	static function ifBranchOf(value:Expr):Expr {
		return switch value.expr {
			case EIf(_, whenTrue, null): whenTrue;
			case _: throw "Identity.preserve: expected an if without else";
		}
	}

	static function returnedOf(value:Expr):Expr {
		return switch value.expr {
			case EReturn(returned) if (returned != null): returned;
			case _: throw "Identity.preserve: expected an explicit return with a value";
		}
	}

	static function identOf(value:Expr):String {
		return switch value.expr {
			case EConst(CIdent(name)): name;
			case _: "<not an identifier>";
		}
	}

	static function stringOf(value:Expr):String {
		return switch value.expr {
			case EConst(CString(text, _)): text;
			case _: "<not a string>";
		}
	}

	static function pushedOf(value:Expr):String {
		return switch value.expr {
			case ECall(callee, callArgs) if (callArgs.length == 1):
				switch callee.expr {
					case EField(owner, "push", _) if (identOf(owner) == "events"): stringOf(callArgs[0]);
					case _: "<not events.push>";
				}
			case _: "<not a call>";
		}
	}
}
