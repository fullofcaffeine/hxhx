package backend.vm;

/**
	Owns one prepared plan for each try occurrence in an exact projected executable.

	Source node identity proves membership; names and structurally identical
	clauses cannot import a handler from another body. The preorder ordinal joins
	the executable and body revision to give each occurrence a deterministic key.
**/
class NekoCatchCatalog {
	final statements = new Array<{
		node:HxStmt,
		plan:NekoCatchPlan,
		?source:HxExpr,
		?fingerprint:String
	}>();
	final program:NekoTypedProgramProjection;
	final selected:NekoExecutableProjection;
	final expressions = new Array<{node:HxExpr, plan:NekoCatchPlan, fingerprint:String}>();
	final plans = new Array<NekoCatchPlan>();
	final executableIdentity:String;
	final bodyRevision:String;

	public function new(program:NekoTypedProgramProjection, selected:NekoExecutableProjection) {
		this.program = program;
		this.selected = selected;
		final owner = switch (selected) {
			case FunctionBody(fn): {identity: fn.body.getStableIdentity(), revision: fn.body.getBodyRevision()};
			case FieldInitializer(initializer): {identity: initializer.getStableIdentity(), revision: initializer.getBodyRevision()};
		};
		executableIdentity = owner.identity;
		bodyRevision = owner.revision;
		function expression(node:HxExpr):Void {
			switch (node) {
				case ELoweredControl(Try(clauses), "", children, _):
					if (Lambda.exists(expressions, entry -> entry.node == node))
						throw "Neko catch source shares an expression occurrence";
					final plan = NekoCatchPlan.prepareLowered(program, selected, clauses, children, plans.length);
					expressions.push({node: node, plan: plan, fingerprint: TypedBodyFingerprint.exactExpression(node)});
					plans.push(plan);
				case ECall(EIdent("__hxhx_try"), [ELambda([], _), EArrayDecl(entries), _]):
					if (Lambda.exists(expressions, entry -> entry.node == node))
						throw "Neko catch source shares an expression occurrence";
					final plan = NekoCatchPlan.prepareExpression(program, selected, entries, plans.length);
					expressions.push({node: node, plan: plan, fingerprint: TypedBodyFingerprint.exactExpression(node)});
					plans.push(plan);
				case ECall(EIdent("__hxhx_try"), _):
					throw "Neko catch source contains a malformed try expression";
				case _:
			}
		}
		function statement(node:HxStmt):Void {
			switch (node) {
				case STry(_, clauses, _):
					if (Lambda.exists(statements, entry -> entry.node == node))
						throw "Neko catch source shares a statement occurrence";
					final plan = NekoCatchPlan.prepareStatement(program, selected, clauses, plans.length);
					statements.push({node: node, plan: plan});
					plans.push(plan);
				case _:
			}
		}
		switch (selected) {
			case FunctionBody(fn):
				for (node in fn.body.getBody())
					TypedBackendSourceWalk.statement(node, expression, statement);
			case FieldInitializer(initializer):
				TypedBackendSourceWalk.expression(initializer.getExpression(), expression);
		}
	}

	/** Only the shared adapter can register a statement derived from an owned lowered try. */
	@:allow(backend.vm.NekoControlStatements)
	function recordAdaptation(source:HxExpr, statement:HxStmt):Void {
		final original = forExpression(source);
		final clauses = switch statement {
			case STry(_, entries, _): entries;
			case _: throw "Neko try adaptation did not produce a try statement";
		};
		final plan = NekoCatchPlan.prepareStatement(program, selected, clauses, plans.indexOf(original));
		statements.push({
			node: statement,
			plan: plan,
			source: source,
			fingerprint: TypedBodyFingerprint.exactStatements([statement])
		});
	}

	public function getPlans():Array<NekoCatchPlan>
		return plans.copy();

	/** A changed revision cannot reuse plans prepared from the previous body. */
	public function assertOwner(identity:String, revision:String):Void {
		if (identity != executableIdentity || revision != bodyRevision)
			throw "Neko catch catalog belongs to another executable or body revision";
	}

	/** A structurally identical or foreign source node is not an owned occurrence. */
	public function forStatement(node:HxStmt):NekoCatchPlan {
		for (entry in statements)
			if (entry.node == node) {
				if (entry.source != null) {
					forExpression(entry.source);
					if (entry.fingerprint != TypedBodyFingerprint.exactStatements([node]))
						throw "Neko catch occurrence changed after preparation";
				}
				entry.plan.assertStatement(node);
				return entry.plan;
			}
		throw "Neko catch plan requires an owned statement occurrence";
	}

	public function forExpression(node:HxExpr):NekoCatchPlan {
		for (entry in expressions)
			if (entry.node == node) {
				if (entry.fingerprint != TypedBodyFingerprint.exactExpression(node))
					throw "Neko catch occurrence changed after preparation";
				entry.plan.assertExpression(node);
				return entry.plan;
			}
		throw "Neko catch plan requires an owned expression occurrence";
	}
}
