package hxhxmacrohost;

import haxe.macro.Expr;

/**
	Plugin-side entry for project expression macros.

	A project macro plugin is an OCaml library that hxhx's Stage3 emitter builds from the
	project's macro classes. Compile it with this class as `-main` and name the macro
	declarations to expose:

	```
	hxhx --hxhx-stage3 --hxhx-no-run -cp <hxhx-core>/src -cp src \
	  -main hxhxmacrohost.MacroDeclarationPlugin \
	  -D ocaml_dune_layout=plugin \
	  -D ocaml_plugin_register_macro=<plugin id> \
	  -D ocaml_plugin_macro_declarations=Identity.preserve
	```

	For each declaration the emitter generates a typed adapter `Array<Expr> -> Expr` that calls
	the real macro method (passing a constant parameter's value through `stringArgument`,
	`intArgument`, `floatArgument`, or `boolArgument`), and registers it under the declaration key with
	`HxHxMacroModuleHost.register_macro_declaration`. When the compiler calls the registration, the
	adapter runs through `invoke`: decode the arguments, check their count, run the macro, and
	encode its result. Any exception thrown by the macro becomes a failure payload, which the
	compiler reports at the macro call instead of crashing the compiler process. A
	`MacroContextAbort` (`haxe.macro.Context.error`) also carries its position, and the compiler
	reports the message there.
**/
class MacroDeclarationPlugin {
	/** The plugin's load-time entry; registration happens in the generated entry module. */
	public static function main():Void {}

	/** Run one generated adapter on an encoded argument payload and encode its outcome. */
	public static function invoke(payload:String, arity:Int, adapter:Array<Expr>->Expr):String {
		try {
			final arguments:Array<Expr> = MacroSyntaxWire.decodeArguments(payload);
			if (arguments.length != arity)
				return MacroSyntaxWire.encodeFailure("expected " + arity + " macro arguments, received " + arguments.length);
			final result:Expr = adapter(arguments);
			if (result == null)
				return MacroSyntaxWire.encodeFailure("the macro returned null instead of an expression");
			return MacroSyntaxWire.encodeResult(result);
		} catch (abort:MacroContextAbort) {
			// `Context.error` (or a Context request the compiler rejected): report at its position.
			return MacroSyntaxWire.encodeFailure(abort.message, abort.position);
		} catch (error:haxe.macro.Expr.Error) {
			// A typing error the macro did not catch (`Context.typeof`): upstream reports it at its position.
			return MacroSyntaxWire.encodeFailure(error.message, error.pos);
		} catch (error:String) {
			return MacroSyntaxWire.encodeFailure(error);
		} catch (error:haxe.Exception) {
			return MacroSyntaxWire.encodeFailure(error.message);
		}
	}

	/*
		Constant arguments. A generated adapter passes a `String`, `Int`, `Float`, or `Bool`
		parameter through one of these functions. The compiler checked the call argument against
		the parameter type before it sent the call, and sent the constant as `EConst`; any other
		shape here means the payload does not match the declaration, so it fails the call.
		Each switch has one level, because the Stage3 emitter does not keep nested pattern
		decisions yet (haxe_ocaml-yhvzj).
	 */
	/** The value of a checked `String` constant argument. */
	public static function stringArgument(argument:Expr):String {
		switch constantOf(argument, "String") {
			case CString(value, _):
				return value;
			case _:
				throw unexpectedConstant("String");
		}
	}

	/** The value of a checked `Int` constant argument (decimal text). */
	public static function intArgument(argument:Expr):Int {
		switch constantOf(argument, "Int") {
			case CInt(value, _):
				final parsed = Std.parseInt(value);
				if (parsed == null)
					throw unexpectedConstant("Int");
				return parsed;
			case _:
				throw unexpectedConstant("Int");
		}
	}

	/** The value of a checked `Float` constant argument; an `Int` constant is accepted, as upstream unifies Int with Float. */
	public static function floatArgument(argument:Expr):Float {
		switch constantOf(argument, "Float") {
			case CFloat(value, _):
				return Std.parseFloat(value);
			case CInt(value, _):
				return Std.parseFloat(value);
			case _:
				throw unexpectedConstant("Float");
		}
	}

	/** The value of a checked `Bool` constant argument (`true` or `false`). */
	public static function boolArgument(argument:Expr):Bool {
		switch constantOf(argument, "Bool") {
			case CIdent(value):
				if (value == "true")
					return true;
				if (value == "false")
					return false;
				throw unexpectedConstant("Bool");
			case _:
				throw unexpectedConstant("Bool");
		}
	}

	static function constantOf(argument:Expr, type:String):Constant {
		if (argument == null)
			throw unexpectedConstant(type);
		switch argument.expr {
			case EConst(constant):
				return constant;
			case _:
				throw unexpectedConstant(type);
		}
	}

	static function unexpectedConstant(type:String):String
		return "the call sent a " + type + " parameter something other than a " + type + " constant";
}
