package probe;

import haxe.macro.Expr;

class PosInfosView {
	public static macro function located(e:Expr, ?pos:haxe.PosInfos):Expr {
		return macro null;
	}
}
