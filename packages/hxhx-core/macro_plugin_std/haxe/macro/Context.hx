package haxe.macro;

import haxe.macro.Expr;
import hxhxmacrohost.MacroContextAbort;
import hxhxmacrohost.MacroContextWire;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWirePosition;

/**
	hxhx's `haxe.macro.Context` for project-macro plugins.

	Why
	- Upstream's `Context` sends every call to its macro interpreter (`load(...)`,
	  `std/haxe/macro/Context.hx` line 848 in Haxe 4.3.7), which a native plugin does not have.
	  The plugin build puts this class's classpath (`packages/hxhx-core/macro_plugin_std`) before
	  the standard library, so project macros compile against it instead.
	- It declares no service that returns `haxe.macro.Type` (`typeof`, `follow`), so a plugin does
	  not compile `haxe.macro.Type`. Those services come with type handles
	  (`docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md`, "Macro Context services").

	What (Context PR 1)
	- Local: `makePosition` and `getPosInfos` build and read the `{file, min, max}` record that
	  plugins use as a position; `error` stops the macro with `MacroContextAbort`.
	- Compiler services (`MacroContextWire` requests through `HxHxMacroModuleHost.call_host`):
	  `currentPos`, `defined`, `definedValue`, `parse`, and `parseInlineString`.
	- The signatures are upstream's, so project macros compile unchanged. A macro that calls a
	  service this class does not declare fails its plugin build with a missing-field error.
**/
class Context {
	/** Report `msg` at `pos` and stop the macro, as upstream does. */
	public static function error(msg:String, pos:Position, ?depth:Int = 0):Dynamic {
		throw new MacroContextAbort(msg, pos);
	}

	/** The position of the macro call. */
	public static function currentPos():Position
		return MacroContextWire.readPosition(ContextHost.call(MacroContextWire.requestCurrentPos()));

	/** A position with these facts, kept as given (upstream accepts any values). */
	public static function makePosition(inf:{min:Int, max:Int, file:String}):Position {
		final facts:MacroSyntaxWirePosition = {file: inf.file, min: inf.min, max: inf.max};
		return cast facts;
	}

	/** The facts of a position. */
	public static function getPosInfos(p:Position):{min:Int, max:Int, file:String} {
		final facts:MacroSyntaxWirePosition = cast p;
		return {min: facts.min, max: facts.max, file: facts.file};
	}

	/** Whether the compilation defines `s` (`-` in the name reads as `_`, as upstream). */
	public static function defined(s:String):Bool
		return MacroContextWire.readBool(ContextHost.call(MacroContextWire.requestDefined(s)));

	/** The value of define `key`, or `null` when it is not defined. */
	public static function definedValue(key:String):String
		return MacroContextWire.readOptionalString(ContextHost.call(MacroContextWire.requestDefinedValue(key)));

	/** Parse `expr` as one expression; its syntax gets `pos`. */
	public static function parse(expr:String, pos:Position):Expr
		return MacroContextWire.readExpr(ContextHost.call(MacroContextWire.requestParse(expr, pos, false)));

	/** Parse `expr` as one expression reported within `pos`. */
	public static function parseInlineString(expr:String, pos:Position):Expr
		return MacroContextWire.readExpr(ContextHost.call(MacroContextWire.requestParse(expr, pos, true)));
}

/** The native host call; `HxHxMacroModuleHost.call_host` passes the strings through unread. */
@:native("HxHxMacroModuleHost")
private extern class ContextHost {
	@:native("call_host")
	public static function call(request:String):String;
}
