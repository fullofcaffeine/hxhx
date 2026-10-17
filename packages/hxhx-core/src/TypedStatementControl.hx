/**
	Adapt already-typed statements into executable control regions without losing
	local, catch or jump identities. This is used when a statement loop acquires a
	statement-valued condition. Operand objects remain unchanged, so their exact
	declaration and runtime-use facts remain valid. The authored source is untouched.
 */
class TypedStatementControl {
	/** An unconditional exit stays abrupt when a statement list becomes an expression region. */
	public static function region(statements:Array<TypedStmt>, root:Null<TyControlTarget>, position:Null<HxPos>):TypedExpr {
		final expressions = [for (statement in statements) expression(statement, root)];
		var type = TyType.fromHintText("Void");
		for (entry in expressions)
			if (entry.getType().isNoNormalCompletion())
				type = TyType.noNormalCompletion();
		return TypedExpr.controlRegion(expressions, type, position);
	}

	static function loopTarget(statement:TypedStmt):TyControlTarget {
		final target = statement.getControlTarget();
		if (target == null || target.getKind() != Loop)
			throw "statement control requires its selected loop destination";
		return target;
	}

	static function expression(statement:TypedStmt, root:Null<TyControlTarget>):TypedExpr {
		final position = statement.getPosition();
		final values = statement.getExpressions();
		final children = statement.getStatements();
		final names = statement.getNames();
		final bindings = statement.getLocalBindings();
		final voidType = TyType.fromHintText("Void");
		function body(child:TypedStmt):TypedExpr
			return region([child], root, child.getPosition());
		return switch statement.getTag() {
			case Expression: values[0];
			case Block: region(children, root, position);
			case Var:
				if (bindings.length != 1 || statement.getMetadata().length != 0)
					throw "statement control requires an ordinary exact local declaration";
				TypedExpr.variableDeclarations([
					TypedExpr.variableDeclaration(names[0], names[1], values.length == 0 ? null : values[0], false, false, bindings[0].getType(), position,
						bindings[0])
						.withControlTarget(statement.getControlTarget())], voidType, position);
			case If:
				final yes = body(children[0]);
				final no = children.length == 1 ? null : body(children[1]);
				final type = no != null
					&& yes.getType().isNoNormalCompletion()
					&& no.getType().isNoNormalCompletion() ? TyType.noNormalCompletion() : voidType;
				TypedExpr.controlBranch(values[0], yes, no, type, position);
			case While | DoWhile:
				TypedExpr.controlWhile(values[0], body(children[0]), position, loopTarget(statement), statement.getTag() == DoWhile ? DoWhile : Normal);
			case ForIn | ForKeyValue:
				if (values.length != 1)
					throw "statement control requires iterator protocols to be lowered first";
				TypedExpr.controlFor(HxForBinding.fromNames(names), values[0], body(children[0]), position, bindings, loopTarget(statement));
			case Break: TypedExpr.breakExpr(position).withControlTarget(loopTarget(statement));
			case Continue: TypedExpr.continueExpr(position).withControlTarget(loopTarget(statement));
			case Return | ReturnVoid:
				if (root == null || root.getKind() != Function)
					throw "statement return requires its selected function destination";
				TypedExpr.returnExpr(values.length == 0 ? null : values[0], TyType.noNormalCompletion(), position).withControlTarget(root);
			case Throw: TypedExpr.throwExpr(values[0], position);
			case Switch:
				if (statement.getSwitchGuards().length != 0)
					throw "statement control requires switch guards to be lowered first";
				final branches = [for (child in children) body(child)];
				var abrupt = statement.getSwitchHasExhaustiveCoverage();
				for (pattern in statement.getPatterns())
					if (pattern.match(PWildcard))
						abrupt = true;
				for (branch in branches)
					abrupt = abrupt && branch.getType().isNoNormalCompletion();
				TypedExpr.controlSwitch(values[0], statement.getPatterns(), branches, abrupt ? TyType.noNormalCompletion() : voidType, position, bindings,
					statement.getSwitchHasExhaustiveCoverage())
					.withSwitchPatterns(statement.getSwitchPatterns());
			case Try:
				final catchNames = statement.getCatchNames();
				final hints = statement.getCatchTypeHints();
				final branches = [for (child in children) body(child)];
				var abrupt = branches.length != 0;
				for (branch in branches)
					abrupt = abrupt && branch.getType().isNoNormalCompletion();
				TypedExpr.controlTry([
					for (i in 0...catchNames.length)
						new HxSourceCatch(catchNames[i], hints[i], position == null ? HxPos.unknown() : position)
				], branches,
					abrupt ? TyType.noNormalCompletion() : voidType, position, bindings).withCatchUses(statement.getCatchUses());
		};
	}
}
