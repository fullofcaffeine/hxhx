package hxhxmacrohost;

import haxe.macro.Expr.Position;

/**
	A macro stopped with a compile error at a position: `haxe.macro.Context.error`, or a Context
	request the compiler answered with an `error` (`MacroContextWire`).

	Upstream Haxe 4.3.7 reports the message at the position and aborts the macro
	(`src/macro/macroApi.ml`, lines 1714-1719). In a project-macro plugin,
	`MacroDeclarationPlugin.invoke` catches this value and sends the message and position back
	in the failure envelope (`MacroSyntaxWire.encodeFailure`). The compiler prints them as
	upstream does: `<file>:<line>: characters <a>-<b> : <message>`.

	It is not a `haxe.Exception`, so macro code that catches `haxe.Exception` does not stop it.
**/
class MacroContextAbort {
	public final message:String;
	public final position:Position;

	public function new(message:String, position:Position) {
		this.message = message == null ? "" : message;
		this.position = position;
	}
}
