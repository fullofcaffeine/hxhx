package;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	A tiny build-macro used as an acceptance/QA signal for the compiler “plugin system”.

	Why:
	- Real Haxe projects frequently depend on build macros (`@:build` / `@:autoBuild`) to generate fields.
	- Even before `hxhx` can execute macros itself, we want `reflaxe.ocaml` to be able to compile
	  the *result* of those macros reliably, and we want a runnable example to prevent regressions.

	What:
	- Adds a `public static function generated():String` method to the class being built.

	How:
	- Uses `Context.getBuildFields()` to obtain existing fields and appends a new `Field` with `FFun`.
**/
class BuildMacro {
	#if macro
	public static function addGeneratedField():Array<Field> {
		final fields = Context.getBuildFields();
		fields.push({
			name: "generated",
			access: [APublic, AStatic],
			kind: FFun({
				args: [],
				ret: macro :String,
				expr: macro return "from_build_macro"
			}),
			pos: Context.currentPos()
		});
		return fields;
	}
	#end
}
