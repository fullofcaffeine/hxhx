class Refs {
	public final names:Array<String> = [];

	final findUse:Expr->Null<String>;

	public function new(findUse:Expr->Null<String>) {
		this.findUse = findUse;
	}

	public function expression(node:Null<Expr>):Void {
		if (node == null)
			return;
		final use = findUse(node);
		if (use != null)
			names.push("use:" + use);
		switch (node) {
			case EIdent(name) if (name.length > 0):
				names.push(name);
			case _:
		}
		Walk.children(node, expression);
	}
}
