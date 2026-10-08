/**
	Project shared function control as statements without inventing a callable.
	Shared lowering already selected each return and loop destination. This adapter
	checks those identities before using the ordinary statement emitter. It keeps
	operand objects intact so runtime-type and method-use facts remain valid.
	The optional observer records each exact try expression and its new statement,
	so consumers can retain handler ownership through this syntax adaptation.
	An append consumer must explicitly validate each original operation before
	adaptation. Targets without that consumer retain the unsupported-operation guard.
**/
function functionBody(body:HxExpr, ?onTry:(HxExpr, HxStmt) -> Void, ?onArrayAppend:HxExpr->Void):Array<HxStmt> {
	return switch body {
		case ELoweredControl(FunctionBody, target, entries, _) if (target.length > 0):
			statements(entries, target, "", onTry, onArrayAppend);
		case _: throw "closure requires a named shared function region";
	};
}

/** Statements execute before the optional final value; absent values preserve abrupt completion. */
typedef InitializerStatements = {
	final statements:Array<HxStmt>;
	final value:Null<HxExpr>;
}

/** Preserve field ownership and operand objects without giving an initializer a return destination. */
function initializerBody(body:HxExpr, owner:String, ?onTry:(HxExpr, HxStmt) -> Void, ?onArrayAppend:HxExpr->Void):InitializerStatements {
	if (owner.length == 0)
		throw "initializer statements require their field owner";
	return switch body {
		case ELoweredControl(Initializer(hasValue), identity, entries, _) if (identity == owner && (!hasValue || entries.length > 0)):
			final count = entries.length - (hasValue ? 1 : 0);
			{statements: statements(entries.slice(0, count), "", "", onTry, onArrayAppend), value: hasValue ? entries[count] : null};
		case ELoweredControl(_, _, _, _): throw "initializer region has an invalid owner or layout";
		case _: {statements: [], value: body};
	};
}

/** Adapt an already lowered region within its exact declared method, retaining return and loop checks. */
function methodStatement(expression:HxExpr, target:String, ?onTry:(HxExpr, HxStmt) -> Void, ?onArrayAppend:HxExpr->Void):HxStmt {
	if (target.length == 0)
		throw "lowered statement requires its owning method destination";
	return statement(expression, target, "", onTry, onArrayAppend);
}

/** Nested lambdas establish their own destination when their expression is emitted. */
private function statement(expression:HxExpr, target:String, loop:String, onTry:Null<(HxExpr, HxStmt) -> Void>, onArrayAppend:Null<HxExpr->Void>):HxStmt {
	final result:HxStmt = switch expression {
		case ELoweredControl(Scope, "", entries, position):
			SBlock(statements(entries, target, loop, onTry, onArrayAppend), position);
		case ELoweredControl(TargetScope(kind), "", [body], position):
			STargetScope(kind, block(body, target, loop, onTry, onArrayAppend), position);
		case ELoweredControl(Return, destination, values, position) if (target.length > 0 && destination == target && values.length <= 1):
			values.length == 0 ? SReturnVoid(position) : SReturn(values[0], position);
		case ELoweredControl(Branch, "", children, position) if (children.length == 2 || children.length == 3):
			SIf(children[0], block(children[1], target, loop, onTry, onArrayAppend),
				children.length == 3 ? block(children[2], target, loop, onTry, onArrayAppend) : null, position);
		case ELoweredControl(Throw, "", [value], position):
			SThrow(value, position);
		case ELoweredControl(While(kind), destination, [condition, body], position) if (destination.length > 0):
			final nested = block(body, target, destination, onTry, onArrayAppend);
			kind == DoWhile ? SDoWhile(nested, condition, position) : SWhile(condition, nested, position);
		case ELoweredControl(For(binding), destination, [iterable, body], position) if (destination.length > 0):
			final nested = block(body, target, destination, onTry, onArrayAppend);
			switch binding {
				case Value(name): SForIn(name, iterable, nested, position);
				case KeyValue(key, value): SForKeyValue(key, value, iterable, nested, position);
			}
		case ELoweredControl(Break, destination, [], position) if (loop.length > 0 && destination == loop):
			SBreak(position);
		case ELoweredControl(Continue, destination, [], position) if (loop.length > 0 && destination == loop):
			SContinue(position);
		case ELoweredControl(Switch(patterns, exhaustive), "", children, position) if (children.length == patterns.length + 1):
			SSwitch(children[0], patterns, [
				for (index in 1...children.length)
					block(children[index], target, loop, onTry, onArrayAppend)
			], position, exhaustive);
		case ELoweredControl(Try(catches), "", children, position) if (children.length == catches.length + 1):
			STry(block(children[0], target, loop, onTry, onArrayAppend), [
				for (index in 0...catches.length)
					{
						name: catches[index].getName(),
						typeHint: catches[index].getTypeHint(),
						body: block(children[index + 1], target, loop, onTry, onArrayAppend)
					}
			], position);
		case EVars(declarations):
			final statements = new Array<HxStmt>();
			for (declaration in declarations) {
				if (HxExprVarDecl.getIsStatic(declaration))
					throw "source static locals require shared storage lowering";
				statements.push(SVar(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration), HxExprVarDecl.getInitializer(declaration),
					HxExprVarDecl.getPosition(declaration)));
			}
			SBlock(statements, HxPos.unknown());
		case ELoweredControl(ArrayAppend, "", [_, _], position) if (onArrayAppend != null):
			// Preserve the original operation for a target's checked append consumer.
			onArrayAppend(expression);
			SExpr(expression, position);
		case ELoweredControl(_, _, _, _):
			throw "control region has an unsupported layout or destination";
		case _:
			SExpr(expression, HxPos.unknown());
	};
	if (onTry != null && expression.match(ELoweredControl(Try(_), _, _, _)))
		onTry(expression, result);
	return result;
}

/** Branch and loop bodies must retain the lexical scopes selected by shared lowering. */
private function block(expression:HxExpr, target:String, loop:String, onTry:Null<(HxExpr, HxStmt) -> Void>, onArrayAppend:Null<HxExpr->Void>):HxStmt {
	return switch expression {
		case ELoweredControl(Scope, "", _, _): statement(expression, target, loop, onTry, onArrayAppend);
		case _: throw "control body requires a shared lexical scope";
	};
}

/** A declaration group shares its enclosing scope; only an explicit Scope creates a block. */
private function statements(entries:Array<HxExpr>, target:String, loop:String, onTry:Null<(HxExpr, HxStmt) -> Void>,
		onArrayAppend:Null<HxExpr->Void>):Array<HxStmt> {
	final result = new Array<HxStmt>();
	for (entry in entries) {
		final projected = statement(entry, target, loop, onTry, onArrayAppend);
		switch entry {
			case EVars(_):
				switch projected {
					case SBlock(declarations, _): for (declaration in declarations)
							result.push(declaration);
					case _: throw "declaration projection lost its statement group";
				}
			case _:
				result.push(projected);
		}
	}
	return result;
}
