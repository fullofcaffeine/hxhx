package hxhx;

/**
	One exact declaration selected before visiting its authored arguments.
	This request-local capture retains original child nodes and returns copied
	argument collections. It is not a runtime registration, typed call, or cache.
**/
@:allow(hxhx.ExprMacroDeclarationSelector)
class SelectedExprMacroCall {
	final declaration:TyDeclarationInfo;
	final call:HxExpr;
	final arguments:Array<HxExpr>;

	private function new(declaration:TyDeclarationInfo, call:HxExpr, arguments:Array<HxExpr>) {
		this.declaration = declaration;
		this.call = call;
		this.arguments = arguments.copy();
	}

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getCall():HxExpr
		return call;

	public function getArguments():Array<HxExpr>
		return arguments.copy();
}
