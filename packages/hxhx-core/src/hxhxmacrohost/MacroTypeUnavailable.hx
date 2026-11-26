package hxhxmacrohost;

import haxe.macro.Type;

/**
	`ClassField.expr` in a project-macro plugin (`MacroTypeWire`): hxhx does not send typed
	expressions yet. A static method in its own module, passed as a method value: the Stage3
	emitter's closures cannot return a nullable value, and it cannot name a static method value
	of the class that is being emitted.
**/
class MacroTypeUnavailable {
	public static function typedExpression():Null<TypedExpr> {
		throw "macro context: unsupported: typed expressions (ClassField.expr) are not available in hxhx yet";
	}
}
