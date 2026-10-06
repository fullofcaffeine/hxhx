/**
	Adapt already-typed statements into executable control regions without losing
	local, catch or jump identities. This is used when a statement loop acquires a
	statement-valued condition. Operand objects remain unchanged, so their exact
	declaration and runtime-use facts remain valid. The authored source is untouched.
 */
class TypedStatementControl {
	public static function region(statements:Array<TypedStmt>, root:Null<TyControlTarget>, position:Null<HxPos>):TypedExpr
		return TypedExpr.controlRegion([for (statement in statements) expression(statement, root)], TyType.fromHintText("Void"), position);

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
				], voidType, position);
			case If: TypedExpr.controlBranch(values[0], body(children[0]), children.length == 1 ? null : body(children[1]), voidType, position);
			case While | DoWhile:
				TypedExpr.controlWhile(values[0], body(children[0]), position, loopTarget(statement), statement.getTag() == DoWhile ? DoWhile : Normal);
			case ForIn | ForKeyValue:
				TypedExpr.controlFor(HxForBinding.fromNames(names), values[0], body(children[0]), position, bindings, loopTarget(statement));
			case Break: TypedExpr.breakExpr(position).withControlTarget(loopTarget(statement));
			case Continue: TypedExpr.continueExpr(position).withControlTarget(loopTarget(statement));
			case Return | ReturnVoid:
				if (root == null || root.getKind() != Function)
					throw "statement return requires its selected function destination";
				TypedExpr.returnExpr(values.length == 0 ? null : values[0], TyType.noNormalCompletion(), position).withControlTarget(root);
			case Throw: TypedExpr.throwExpr(values[0], position);
			case Switch: TypedExpr.controlSwitch(values[0], statement.getPatterns(), [for (child in children) body(child)], voidType, position, bindings);
			case Try:
				final catchNames = statement.getCatchNames();
				final hints = statement.getCatchTypeHints();
				TypedExpr.controlTry([
					for (i in 0...catchNames.length)
						new HxSourceCatch(catchNames[i], hints[i], position == null ? HxPos.unknown() : position)
				], [for (child in children) body(child)], voidType,
					position, bindings).withCatchUses(statement.getCatchUses());
		};
	}
}
