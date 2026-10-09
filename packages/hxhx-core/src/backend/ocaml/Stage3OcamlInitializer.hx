package backend.ocaml;

/** A lowered initializer runs statements in one scope, then reads its selected value. */
typedef InitializerStatements = {
	final statements:Array<HxStmt>;
	final value:Null<HxExpr>;
}

/**
	Adapt shared control instructions to the existing OCaml statement renderer.
	The shared lowerer has already chosen scopes, temporaries, and branch order.
	This adapter preserves the original operand nodes so storage facts stay exact;
	it never introduces a callable or a synthetic return destination.
 */
function plan(projection:TypedBackendFieldInitializerProjection, expression:HxExpr):InitializerStatements {
	if (projection == null || projection.getExpression() != expression)
		throw "OCaml initializer requires its exact projected root";
	projection.assertCurrent();
	return switch expression {
		case ELoweredControl(Initializer(hasValue), owner, entries, _):
			if (owner != projection.getStableIdentity() || (hasValue && entries.length == 0))
				throw "OCaml initializer lost its owner or final value";
			final count = entries.length - (hasValue ? 1 : 0);
			{statements: statements(entries.slice(0, count)), value: hasValue ? entries[count] : null};
		case _: throw "OCaml initializer statement plan requires shared control lowering";
	};
}

private function statements(entries:Array<HxExpr>):Array<HxStmt> {
	final result = new Array<HxStmt>();
	for (entry in entries)
		switch entry {
			case EVars(declarations):
				for (declaration in declarations) {
					if (HxExprVarDecl.getIsStatic(declaration))
						throw "OCaml initializer local requires shared static storage lowering";
					result.push(SVar(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration), HxExprVarDecl.getInitializer(declaration),
						HxExprVarDecl.getPosition(declaration), []));
				}
			case ELoweredControl(Scope, "", children, position):
				result.push(SBlock(statements(children), position));
			case ELoweredControl(Branch, "", children, position):
				if (children.length != 2 && children.length != 3)
					throw "OCaml initializer branch requires its shared condition and scopes";
				result.push(SIf(children[0], SBlock(statements([children[1]]), position),
					children.length == 3 ? SBlock(statements([children[2]]), position) : null, position));
			case ELoweredControl(Switch(patterns, exhaustive), "", children, position):
				if (children.length != patterns.length + 1)
					throw "OCaml initializer switch requires aligned cases";
				result.push(SSwitch(children[0], patterns, [for (child in children.slice(1)) SBlock(statements([child]), position)], position, exhaustive));
			case ELoweredControl(_, _, _, _):
				throw "OCaml initializer requires an executable adapter for this shared control instruction";
			case _:
				result.push(SExpr(entry, HxPos.unknown()));
		}
	return result;
}
