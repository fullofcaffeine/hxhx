package hxhxmacrohost;

import haxe.macro.Expr.Position;

/** One `hxhx-macro-context.v1` response's failure facts (`MacroContextWire.failureOf`). */
class MacroContextFailure {
	public final failed:Bool;
	public final kind:String;
	public final message:String;
	public final position:Null<Position>;

	public function new(failed:Bool, kind:String, message:String, position:Null<Position>) {
		this.failed = failed;
		this.kind = kind;
		this.message = message;
		this.position = position;
	}
}
