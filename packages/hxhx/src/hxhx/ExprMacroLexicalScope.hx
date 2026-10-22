package hxhx;

import hxhx.ExprMacroDeclarationSelector.ExprMacroSelectionScope;

/** One source boundary whose names or recursive syntax this pass cannot prove. */
typedef ExprMacroLexicalGap = {
	final filePath:String;
	final reason:String;
}

/**
	Own source-visible names while syntax is traversed before typing.
	A child copies definition-time visibility. Declarations affect subsequent
	siblings in that scope, without leaking from blocks or nested functions.
	No types, symbol identities, receiver inference, or runtime values live here.
	Children share one request-owned gap list. Unmodeled syntax invalidates the
	local visibility proof without changing the existing text adapter's traversal.
**/
class ExprMacroLexicalScope {
	final names:Array<String>;
	final gaps:Array<ExprMacroLexicalGap>;
	var unavailableReason:Null<String>;
	final isStaticContext:Bool;

	public function new(isStaticContext:Bool, names:Array<String>, gaps:Array<ExprMacroLexicalGap>, ?unavailableReason:String) {
		this.isStaticContext = isStaticContext;
		this.names = names.copy();
		this.gaps = gaps;
		this.unavailableReason = unavailableReason;
	}

	public function child(?bindings:Array<String>):ExprMacroLexicalScope
		return new ExprMacroLexicalScope(isStaticContext, names.concat(bindings == null ? [] : bindings), gaps, unavailableReason);

	/** Preserve old syntax traversal while preventing a declaration caller from trusting partial names. */
	public function markUnavailable(filePath:String, reason:String):Void {
		unavailableReason = reason;
		gaps.push({filePath: filePath, reason: reason});
	}

	public function declare(name:String):Void
		names.push(name);

	public function snapshot():ExprMacroSelectionScope
		return {visibility: unavailableReason == null ? Known(names.copy()) : Unavailable(unavailableReason), isStaticContext: isStaticContext};
}
