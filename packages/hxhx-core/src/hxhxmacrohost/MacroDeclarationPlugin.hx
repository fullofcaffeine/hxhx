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
	the real macro method, and registers it under the declaration key with
	`HxHxMacroModuleHost.register_macro_declaration`. When the compiler calls the registration, the
	adapter runs through `invoke`: decode the arguments, check their count, run the macro, and
	encode its result. Any exception thrown by the macro becomes a failure payload, which the
	compiler reports at the macro call instead of crashing the compiler process.
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
		} catch (error:String) {
			return MacroSyntaxWire.encodeFailure(error);
		} catch (error:haxe.Exception) {
			return MacroSyntaxWire.encodeFailure(error.message);
		}
	}
}
