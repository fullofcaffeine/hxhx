package projectmacro;

import haxe.macro.Expr;

/** A tiny real project macro used as the upstream Haxe behavior oracle. **/
class ProjectMacro {
	public static macro function message():Expr {
		return macro $v{ProjectMacroValue.value()};
	}
}
