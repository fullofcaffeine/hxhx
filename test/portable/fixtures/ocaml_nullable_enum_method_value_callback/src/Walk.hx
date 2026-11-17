class Walk {
	public static function children(node:Expr, onChild:Expr->Void):Void {
		function visit(child:Null<Expr>):Void {
			if (child != null)
				onChild(child);
		}
		switch (node) {
			case ECall(callee, args):
				visit(callee);
				for (arg in args)
					visit(arg);
			case _:
		}
	}

	/** Refs and Walk refer to each other, so the backend emits them as one recursive module group. */
	public static function names(node:Expr):String {
		final refs = new Refs(_ -> null);
		refs.expression(node);
		return refs.names.join("+");
	}
}
