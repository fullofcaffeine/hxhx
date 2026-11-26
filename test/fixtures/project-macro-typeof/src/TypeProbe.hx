#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
	Project macros that read types, as upstream's test builder does.

	Like upstream's `tests/unit/src/unit/UnitBuilder.hx`, each macro parses source text with
	`Context.parseInlineString` and types the result. `isFloat` has the shape of `mkEq`'s helper
	there: `Context.follow(Context.typeof(e))`, a `TAbstract(tr, _)` case, and `tr.get().name`, with
	a typing failure caught. `describe` prints the type of an expression and the type it follows
	to. Anonymous field names are sorted, so the order of a structure's fields does not matter.
**/
class TypeProbe {
	public static macro function isFloat(code:String):haxe.macro.Expr {
		#if macro
		final e = Context.parseInlineString(code, Context.currentPos());
		function isFloat(e) {
			try
				return switch (Context.follow(Context.typeof(e))) {
					case TAbstract(tr, _):
						tr.get().name == "Float";
					case _:
						false;
				} catch (e:Dynamic) {
				return false;
			}
		}
		return macro $v{isFloat(e)};
		#else
		return null;
		#end
	}

	public static macro function describe(code:String):haxe.macro.Expr {
		#if macro
		final t = Context.typeof(Context.parseInlineString(code, Context.currentPos()));
		final shown = show(t) + " => " + show(Context.follow(t)) + " | once " + show(Context.follow(t, true));
		return macro $v{shown};
		#else
		return null;
		#end
	}

	#if macro
	static function show(t:Type):String {
		return switch t {
			case TInst(c, params):
				final value = c.get();
				"TInst "
				+ c.toString()
				+ " name="
				+ value.name
				+ " module="
				+ value.module
				+ " pack="
				+ value.pack.join(".")
				+ " params="
				+ list(params);
			case TAbstract(a, params):
				final value = a.get();
				"TAbstract "
				+ a.toString()
				+ " name="
				+ value.name
				+ " module="
				+ value.module
				+ " params="
				+ list(params);
			case TEnum(en, params):
				final value = en.get();
				"TEnum "
				+ en.toString()
				+ " module="
				+ value.module
				+ " names="
				+ value.names.join(",")
				+ " params="
				+ list(params);
			case TType(td, params):
				final value = td.get();
				"TType " + td.toString() + " module=" + value.module + " params=" + list(params);
			case TFun(args, ret):
				"TFun(" + [for (arg in args) arg.name + (arg.opt ? "?" : "") + ":" + show(arg.t)].join(", ") + ") -> " + show(ret);
			case TAnonymous(a):
				final names = [for (field in a.get().fields) field.name];
				names.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
				"TAnonymous " + names.join(",");
			case TDynamic(_):
				"TDynamic";
			case TMono(_):
				"TMono";
			case TLazy(_):
				"TLazy";
		}
	}

	static function list(params:Array<Type>):String
		return "[" + [for (param in params) show(param)].join("; ") + "]";
	#end
}
