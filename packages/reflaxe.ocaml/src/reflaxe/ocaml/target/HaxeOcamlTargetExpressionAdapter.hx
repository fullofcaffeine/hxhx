package reflaxe.ocaml.target;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;
#end

/** Copies the admitted original typed-Haxe expression family into target facts. **/
class HaxeOcamlTargetExpressionAdapter {
	#if (macro || reflaxe_runtime)
	final ownerIdentity:String;
	final sourceOwner:Null<ClassType>;
	final bindingsByHostId:Map<Int, OcamlTargetBindingFact>;

	function new(ownerIdentity:String, ?sourceOwner:ClassType) {
		this.ownerIdentity = requiredOwner(ownerIdentity);
		this.sourceOwner = sourceOwner;
		bindingsByHostId = new Map<Int, OcamlTargetBindingFact>();
	}

	/**
		Copy admitted expressions before target preprocessors can introduce unmarked TVars.

		A null result rejects the whole expression. The optional source owner admits
		resolved calls inside functions; field initializers omit that context.
	**/
	public static function fromSourceBeforePreprocessing(ownerIdentity:String, expression:TypedExpr, ?sourceOwner:ClassType):Null<OcamlTargetExpressionFact> {
		if (expression == null)
			throw "standalone OCaml expression adapter requires a typed expression";
		final fact = new HaxeOcamlTargetExpressionAdapter(ownerIdentity, sourceOwner).copyExpression(expression, OcamlTargetExpressionPath.ROOT);
		if (fact != null)
			fact.validateClosedBindings();
		return fact;
	}

	/** Copy function control without interpreting a host return node as a runtime value. **/
	public static function fromFunctionBody(ownerIdentity:String, body:TypedExpr, sourceOwner:ClassType, locals:Array<TVar>,
			parameters:Array<OcamlTargetBindingFact>):Null<OcamlTargetStatementFact> {
		if (locals.length != parameters.length)
			throw "stock OCaml function parameter inventory mismatch";
		final adapter = new HaxeOcamlTargetExpressionAdapter(ownerIdentity, sourceOwner);
		for (index in 0...locals.length) {
			if (adapter.bindingsByHostId.exists(locals[index].id))
				throw "stock OCaml function repeats a parameter identity";
			adapter.bindingsByHostId.set(locals[index].id, parameters[index]);
		}
		final statements = switch (body.expr) {
			case TBlock(items): items;
			case _: [body];
		};
		return adapter.copyStatements(statements, OcamlTargetExpressionPath.ROOT);
	}

	function copyStatements(statements:Array<TypedExpr>, path:String):Null<OcamlTargetStatementFact> {
		final children = new Array<OcamlTargetStatementFact>();
		for (index in 0...statements.length) {
			final statement = statements[index];
			final childPath = OcamlTargetExpressionPath.indexed(path, "block-item", index);
			final child = switch (statement.expr) {
				case TIf(condition, whenTrue, whenFalse):
					whenFalse == null ? null : copyReturningConditional(condition, whenTrue, whenFalse, childPath);
				case TBlock(items): copyStatements(items, childPath);
				case TReturn(null): OcamlTargetStatementFact.returnValue(childPath, null);
				case TReturn(value):
					final copied = copyExpression(value, OcamlTargetExpressionPath.child(childPath, "return-value"));
					copied == null ? null : OcamlTargetStatementFact.returnValue(childPath, copied);
				case _:
					final copied = copyExpression(statement, childPath);
					copied == null ? null : OcamlTargetStatementFact.evaluate(copied);
			};
			if (child == null)
				return null;
			children.push(child);
		}
		return OcamlTargetStatementFact.block(path, children);
	}

	/** Match native terminal If statements without admitting partial or early returns. **/
	function copyReturningConditional(condition:TypedExpr, whenTrue:TypedExpr, whenFalse:TypedExpr, path:String):Null<OcamlTargetStatementFact> {
		final valuePath = OcamlTargetExpressionPath.child(path, "return-value");
		final copiedCondition = copyExpression(condition, OcamlTargetExpressionPath.child(valuePath, "condition"));
		final copiedTrue = copyReturningBranch(whenTrue, OcamlTargetExpressionPath.child(valuePath, "then"));
		final copiedFalse = copyReturningBranch(whenFalse, OcamlTargetExpressionPath.child(valuePath, "else"));
		if (copiedCondition == null
			|| copiedTrue == null
			|| copiedFalse == null
			|| copiedCondition.semanticTypeDisplay != "Bool"
			|| copiedTrue.semanticTypeDisplay != copiedFalse.semanticTypeDisplay)
			return null;
		return OcamlTargetStatementFact.returnValue(path,
			OcamlTargetExpressionFact.conditional(valuePath, copiedTrue.semanticTypeDisplay, copiedCondition, copiedTrue, copiedFalse));
	}

	/** Preserve preceding branch effects; only its final return supplies the value. **/
	function copyReturningBranch(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final statements = switch (expression.expr) {
			case TBlock(items): items;
			case _: [expression];
		};
		if (statements.length == 0)
			return null;
		final children = new Array<OcamlTargetExpressionFact>();
		for (index in 0...statements.length) {
			final childPath = OcamlTargetExpressionPath.indexed(path, "block-item", index);
			final child = switch (statements[index].expr) {
				case TReturn(value) if (value != null && index == statements.length - 1):
					copyExpression(value, childPath);
				case _ if (index != statements.length - 1):
					copyExpression(statements[index], childPath);
				case _: null;
			};
			if (child == null)
				return null;
			children.push(child);
		}
		return OcamlTargetExpressionFact.block(path, children[children.length - 1].semanticTypeDisplay, children);
	}

	function copyExpression(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		return switch (expression.expr) {
			case TIf(condition, whenTrue, whenFalse) if (whenFalse != null):
				final copiedCondition = copyExpression(condition, OcamlTargetExpressionPath.child(path, "condition"));
				final copiedTrue = copyBranch(whenTrue, OcamlTargetExpressionPath.child(path, "then"));
				final copiedFalse = copyBranch(whenFalse, OcamlTargetExpressionPath.child(path, "else"));
				final resultType = TypeTools.toString(expression.t);
				copiedCondition == null
				|| copiedTrue == null
				|| copiedFalse == null
				|| copiedCondition.semanticTypeDisplay != "Bool"
				|| copiedTrue.semanticTypeDisplay != resultType
				|| copiedFalse.semanticTypeDisplay != resultType ? null : OcamlTargetExpressionFact.conditional(path, resultType, copiedCondition, copiedTrue,
					copiedFalse);
			case TParenthesis(inner):
				// Match native grouping without inventing a target-owned binding path.
				TypeTools.toString(inner.t) == TypeTools.toString(expression.t) ? copyExpression(inner, path) : null;
			case TCall(callee, arguments):
				copyCall(callee, arguments, TypeTools.toString(expression.t), path);
			case TConst(constant): final literal = HaxeOcamlTargetLiteralAdapter.fromConstant(constant,
					expression.t); literal == null || !isDirectLiteral(literal) ? null : OcamlTargetExpressionFact.literalExpression(path, literal);
			case TLocal(local): final binding = bindingsByHostId.get(local.id); final readType = TypeTools.toString(expression.t); binding == null || binding.semanticTypeDisplay != readType ? null : OcamlTargetExpressionFact.localRead(path,
					readType, binding);
			case TVar(local, initializer):
				if (initializer == null) {
					null;
				} else {
					final binding = HaxeOcamlTargetBindingAdapter.fromSourceLocalBeforePreprocessing(ownerIdentity,
						OcamlTargetExpressionPath.child(path, "binding"), OcamlTargetBindingRole.Variable, local);
					bindingsByHostId.set(local.id, binding);
					final copiedInitializer = copyExpression(initializer, OcamlTargetExpressionPath.child(path, "initializer"));
					copiedInitializer == null
					|| copiedInitializer.semanticTypeDisplay != binding.semanticTypeDisplay ? null : OcamlTargetExpressionFact.variableDeclaration(path,
						binding, copiedInitializer);
				}
			case TBlock(expressions):
				copyBlock(expression, expressions, path);
			case _:
				null;
		};
	}

	function copyBlock(expression:TypedExpr, expressions:Array<TypedExpr>, path:String):Null<OcamlTargetExpressionFact> {
		final children = new Array<OcamlTargetExpressionFact>();
		for (index in 0...expressions.length) {
			final child = copyExpression(expressions[index], OcamlTargetExpressionPath.indexed(path, "block-item", index));
			if (child == null)
				return null;
			children.push(child);
		}
		final blockType = TypeTools.toString(expression.t);
		final resultType = children.length == 0 ? "Void" : children[children.length - 1].semanticTypeDisplay;
		return blockType == resultType ? OcamlTargetExpressionFact.block(path, blockType, children) : null;
	}

	/**
		Both hosts publish a lexical block for each alternative. Stock Haxe may
		already wrap a single branch value; keep real declarations inside that scope.
	**/
	function copyBranch(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		return switch (expression.expr) {
			case TParenthesis(inner) if (TypeTools.toString(inner.t) == TypeTools.toString(expression.t)):
				copyBranch(inner, path);
			case TBlock(items): copyBlock(expression, items, path);
			case _:
				final child = copyExpression(expression, OcamlTargetExpressionPath.indexed(path, "block-item", 0));
				child == null ? null : OcamlTargetExpressionFact.block(path, child.semanticTypeDisplay, [child]);
		};
	}

	/** The host must resolve an ordinary static declaration before we copy its identity. **/
	function copyCall(callee:TypedExpr, arguments:Array<TypedExpr>, returnType:String, path:String):Null<OcamlTargetExpressionFact> {
		return switch (callee.expr) {
			case TField({expr: TTypeExpr(TClassDecl(receiver))}, FStatic(owner, reference)):
				final cls = owner.get();
				final field = reference.get();
				final ordinary = switch (field.kind) {
					case FMethod(MethNormal): true;
					case _: false;
				};
				final argumentTypes:Null<Array<String>> = switch (field.type) {
					case TFun(args, result) if (TypeTools.toString(result) == returnType
						&& OcamlTargetFunctionFact.admitsResult(returnType)):
						var valid = args.length == arguments.length;
						for (arg in args)
							if (arg.opt || !OcamlTargetFunctionFact.admitsValue(TypeTools.toString(arg.t)))
								valid = false;
						valid ? [for (arg in args) TypeTools.toString(arg.t)] : null;
					case _: null;
				};
				if (sourceOwner == null || cls.module != sourceOwner.module || cls.name != sourceOwner.name || receiver.get().module != cls.module
					|| receiver.get().name != cls.name || cls.isExtern || cls.params.length != 0 || !ordinary || argumentTypes == null
					|| field.params.length != 0 || field.expr() == null || field.meta.get().length != 0) {
					null;
				} else {
					final copied = new Array<OcamlTargetExpressionFact>();
					for (index in 0...arguments.length) {
						final argument = copyExpression(arguments[index], OcamlTargetExpressionPath.indexed(path, "argument", index));
						if (argument == null || argument.semanticTypeDisplay != argumentTypes[index])
							return null;
						copied.push(argument);
					}
					OcamlTargetExpressionFact.directStaticCall(path, new OcamlTargetStaticCallFact({
						moduleId: cls.module,
						sourceTypeName: cls.name,
						sourceFunctionName: field.name,
						argumentTypeDisplays: argumentTypes,
						returnTypeDisplay: returnType
					}), copied);
				}
			case _: null;
		};
	}

	static function isDirectLiteral(literal:OcamlTargetLiteralFact):Bool {
		return switch (literal.kind) {
			case IntValue: literal.semanticTypeDisplay == "Int";
			case BoolValue: literal.semanticTypeDisplay == "Bool";
			case StringValue: literal.semanticTypeDisplay == "String";
			case NullValue | ThisValue | SuperValue: false;
		};
	}

	static function requiredOwner(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "standalone OCaml expression adapter requires an owner identity";
		return normalized;
	}
	#end
}
