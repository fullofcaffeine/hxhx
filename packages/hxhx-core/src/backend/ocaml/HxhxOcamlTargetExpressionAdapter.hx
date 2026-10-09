package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionPath;
import reflaxe.ocaml.target.OcamlTargetStatementFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;

/** Copies the admitted native typed-expression family into target-owned facts. **/
class HxhxOcamlTargetExpressionAdapter {
	final ownerIdentity:String;
	final nativeFunctionIdentity:Null<String>;
	final sourceOwner:Null<TyNominalInfo>;
	final bindingsByNativeKey:Map<String, OcamlTargetBindingFact>;

	function new(ownerIdentity:String, ?nativeFunctionIdentity:String, ?sourceOwner:TyNominalInfo) {
		this.ownerIdentity = requiredOwner(ownerIdentity);
		this.nativeFunctionIdentity = nativeFunctionIdentity;
		this.sourceOwner = sourceOwner;
		bindingsByNativeKey = new Map<String, OcamlTargetBindingFact>();
	}

	public static function fromExpression(ownerIdentity:String, expression:TypedExpr):Null<OcamlTargetExpressionFact> {
		if (expression == null)
			throw "native OCaml expression adapter requires a typed expression";
		final fact = new HxhxOcamlTargetExpressionAdapter(ownerIdentity).copyExpression(expression, OcamlTargetExpressionPath.ROOT);
		if (fact != null)
			fact.validateClosedBindings();
		return fact;
	}

	/**
		Copy source statements and the exact immutable parameter bindings.

		One adapter owns the whole body so local reads keep their exact declaration
		identity across nested blocks. The shared target validates lexical visibility
		and owns lowering. Unsupported statements reject the complete body.
	**/
	public static function fromFunctionBody(ownerIdentity:String, nativeFunctionIdentity:String, body:TypedFunctionBody, sourceOwner:TyNominalInfo,
			nativeParameters:Array<TyLocalBinding>, parameters:Array<OcamlTargetBindingFact>):Null<OcamlTargetStatementFact> {
		if (body == null)
			throw "native OCaml expression adapter requires a typed function body";
		final adapter = new HxhxOcamlTargetExpressionAdapter(ownerIdentity, requiredOwner(nativeFunctionIdentity), sourceOwner);
		if (nativeParameters.length != parameters.length)
			throw "native OCaml function parameter inventory mismatch";
		for (index in 0...nativeParameters.length) {
			final identity = nativeParameters[index].getIdentity();
			if (identity.getOwnerIdentity() != nativeFunctionIdentity || adapter.bindingsByNativeKey.exists(identity.getCanonicalKey()))
				throw "native OCaml function has a foreign or repeated parameter";
			adapter.bindingsByNativeKey.set(identity.getCanonicalKey(), parameters[index]);
		}
		return adapter.copyStatements(body.getStatements(), OcamlTargetExpressionPath.ROOT);
	}

	/** Preserve source order and block nesting without adding target lowering decisions. **/
	function copyStatements(statements:Array<TypedStmt>, path:String):Null<OcamlTargetStatementFact> {
		final children = new Array<OcamlTargetStatementFact>();
		for (index in 0...statements.length) {
			final statement = statements[index];
			final childPath = OcamlTargetExpressionPath.indexed(path, "block-item", index);
			final expressions = statement.getExpressions();
			final child = switch (statement.getTag()) {
				case If:
					copyReturningConditional(statement, childPath);
				case Var:
					final bindings = statement.getLocalBindings();
					final copied = bindings.length == 1
						&& expressions.length == 1 ? copyDeclaration(bindings[0], expressions[0], childPath) : null;
					copied == null ? null : OcamlTargetStatementFact.evaluate(copied);
				case Expression:
					final copied = expressions.length == 1 ? copyExpression(expressions[0], childPath) : null;
					copied == null ? null : OcamlTargetStatementFact.evaluate(copied);
				case ReturnVoid:
					expressions.length == 0 ? OcamlTargetStatementFact.returnValue(childPath, null) : null;
				case Return:
					if (expressions.length == 1) {
						final copied = copyExpression(expressions[0], OcamlTargetExpressionPath.child(childPath, "return-value"));
						copied == null ? null : OcamlTargetStatementFact.returnValue(childPath, copied);
					} else null;
				case Block:
					copyStatements(statement.getStatements(), childPath);
				case _:
					null;
			};
			if (child == null)
				return null;
			children.push(child);
		}
		return OcamlTargetStatementFact.block(path, children);
	}

	/**
		The native parser represents a returned if-expression as two returning
		statement branches. Copy that exact terminal shape as one conditional value,
		matching stock Haxe. A missing return or an early return still rejects it.
	**/
	function copyReturningConditional(statement:TypedStmt, path:String):Null<OcamlTargetStatementFact> {
		final expressions = statement.getExpressions();
		final branches = statement.getStatements();
		if (expressions.length != 1 || branches.length != 2)
			return null;
		final valuePath = OcamlTargetExpressionPath.child(path, "return-value");
		final condition = copyExpression(expressions[0], OcamlTargetExpressionPath.child(valuePath, "condition"));
		final whenTrue = copyReturningBranch(branches[0], OcamlTargetExpressionPath.child(valuePath, "then"));
		final whenFalse = copyReturningBranch(branches[1], OcamlTargetExpressionPath.child(valuePath, "else"));
		if (condition == null
			|| whenTrue == null
			|| whenFalse == null
			|| condition.semanticTypeDisplay != "Bool"
			|| whenTrue.semanticTypeDisplay != whenFalse.semanticTypeDisplay)
			return null;
		return OcamlTargetStatementFact.returnValue(path,
			OcamlTargetExpressionFact.conditional(valuePath, whenTrue.semanticTypeDisplay, condition, whenTrue, whenFalse));
	}

	/** Only a final payload return becomes a branch value; preceding effects keep source order. **/
	function copyReturningBranch(statement:TypedStmt, path:String):Null<OcamlTargetExpressionFact> {
		final statements = statement.getTag() == Block ? statement.getStatements() : [statement];
		if (statements.length == 0 || statements[statements.length - 1].getTag() != Return)
			return null;
		final children = new Array<OcamlTargetExpressionFact>();
		for (index in 0...statements.length) {
			final current = statements[index];
			final expressions = current.getExpressions();
			final childPath = OcamlTargetExpressionPath.indexed(path, "block-item", index);
			final child = switch (current.getTag()) {
				case Return if (index == statements.length - 1 && expressions.length == 1):
					copyExpression(expressions[0], childPath);
				case Expression if (expressions.length == 1):
					copyExpression(expressions[0], childPath);
				case Var: final bindings = current.getLocalBindings(); bindings.length == 1 && expressions.length == 1 ? copyDeclaration(bindings[0],
						expressions[0], childPath) : null;
				case _: null;
			};
			if (child == null)
				return null;
			children.push(child);
		}
		return OcamlTargetExpressionFact.block(path, children[children.length - 1].semanticTypeDisplay, children);
	}

	function copyExpression(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final literal = HxhxOcamlTargetLiteralAdapter.fromExpression(expression);
		if (literal != null)
			return isDirectLiteral(literal) ? OcamlTargetExpressionFact.literalExpression(path, literal) : null;
		return switch (expression.getTag()) {
			case Ternary | SourceIf:
				final children = expression.getExpressions();
				if (children.length != 3) {
					null;
				} else {
					final condition = copyExpression(children[0], OcamlTargetExpressionPath.child(path, "condition"));
					final whenTrue = copyBranch(children[1], OcamlTargetExpressionPath.child(path, "then"));
					final whenFalse = copyBranch(children[2], OcamlTargetExpressionPath.child(path, "else"));
					final resultType = expression.getType().getCanonicalDisplay();
					condition == null
					|| whenTrue == null
					|| whenFalse == null
					|| condition.semanticTypeDisplay != "Bool"
					|| whenTrue.semanticTypeDisplay != resultType
					|| whenFalse.semanticTypeDisplay != resultType ? null : OcamlTargetExpressionFact.conditional(path, resultType, condition, whenTrue,
						whenFalse);
				}
			case Parenthesized: // Grouping adds no binding or runtime operation to the shared target facts.
				final children = expression.getExpressions(); children.length == 1 && children[0].getType()
					.getSemanticKey() == expression.getType()
					.getSemanticKey() ? copyExpression(children[0], path) : null;
			case Call:
				copyCall(expression, path);
			case LocalRead:
				final nativeBindings = expression.getLocalBindings();
				if (nativeBindings.length != 1) {
					null;
				} else {
					final binding = bindingsByNativeKey.get(nativeBindings[0].getIdentity().getCanonicalKey());
					final readType = expression.getType().getCanonicalDisplay();
					binding == null
					|| binding.semanticTypeDisplay != readType ? null : OcamlTargetExpressionFact.localRead(path, readType, binding);
				}
			case VariableDeclaration:
				copyVariable(expression, path);
			case Temporary:
				// Conservative expression-block recovery still uses this structural tag
				// for source locals. copyVariable delegates identity validation to the
				// binding adapter, which rejects every real compiler temporary.
				copyVariable(expression, path);
			case VariableDeclarations:
				copyBlock(expression, expression.getExpressions(), path);
			case Block | SourceGroup:
				copyNativeBlock(expression, path);
			case _:
				null;
		};
	}

	/**
		Copy authored braces and rebuilt blocks without flattening nested scopes.
		Only declaration lists expand within their existing scope; the target facts
		still validate each local read against its visible declaration.
	**/
	function copyNativeBlock(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final flattened = new Array<TypedExpr>();
		for (child in expression.getExpressions()) {
			if (child.getTag() == VariableDeclarations) {
				for (declaration in child.getExpressions())
					flattened.push(declaration);
			} else {
				flattened.push(child);
			}
		}
		return copyBlock(expression, flattened, path);
	}

	/** Normalize bare alternatives to blocks without flattening authored local scopes. **/
	function copyBranch(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		return switch (expression.getTag()) {
			case Parenthesized: final children = expression.getExpressions(); children.length == 1 && children[0].getType()
					.getSemanticKey() == expression.getType()
					.getSemanticKey() ? copyBranch(children[0], path) : null;
			case Block | SourceGroup: copyNativeBlock(expression, path);
			case _:
				final child = copyExpression(expression, OcamlTargetExpressionPath.indexed(path, "block-item", 0));
				child == null ? null : OcamlTargetExpressionFact.block(path, child.semanticTypeDisplay, [child]);
		};
	}

	/** Copy only a resolved bare static call; computed receivers must retain their effects. **/
	function copyCall(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final declaration = expression.getDeclaration();
		final children = expression.getExpressions();
		if (sourceOwner == null
			|| declaration == null
			|| children.length == 0
			|| children[0].getTag() != NameRead
			|| children[0].getExpressions().length != 0
			|| expression.getExtensionProvider() != null
			|| !declaration.getOwner().equals(sourceOwner.getIdentity())
			|| declaration.getModulePath() != sourceOwner.getModulePath()
			|| !declaration.getIsStatic()
			|| declaration.getIsInline()
			|| declaration.getIsDynamic()
			|| declaration.getIsEnumConstructor()
			|| !declaration.getHasBody()
			|| declaration.getTypeParameterIds().length != 0
			|| declaration.getMetadata().length != 0)
			return null;
		final signature = declaration.getSignature();
		final argumentTypes = [for (type in signature.getArgs()) type.getCanonicalDisplay()];
		final returnType = signature.getReturnType().getCanonicalDisplay();
		if (!signature.getIsStatic()
			|| argumentTypes.length != children.length - 1
			|| !OcamlTargetFunctionFact.admitsResult(returnType)
			|| returnType != expression.getType().getCanonicalDisplay())
			return null;
		final arguments = new Array<OcamlTargetExpressionFact>();
		for (index in 0...argumentTypes.length) {
			if (!OcamlTargetFunctionFact.admitsValue(argumentTypes[index])
				|| signature.getArgOptional()[index]
				|| signature.getArgRest()[index])
				return null;
			final argument = copyExpression(children[index + 1], OcamlTargetExpressionPath.indexed(path, "argument", index));
			if (argument == null || argument.semanticTypeDisplay != argumentTypes[index])
				return null;
			arguments.push(argument);
		}
		return OcamlTargetExpressionFact.directStaticCall(path, new reflaxe.ocaml.target.OcamlTargetStaticCallFact({
			moduleId: sourceOwner.getModulePath(),
			sourceTypeName: sourceOwner.getShortName(),
			sourceFunctionName: signature.getName(),
			argumentTypeDisplays: argumentTypes,
			returnTypeDisplay: returnType
		}), arguments);
	}

	function copyBlock(expression:TypedExpr, expressions:Array<TypedExpr>, path:String):Null<OcamlTargetExpressionFact> {
		final children = new Array<OcamlTargetExpressionFact>();
		for (index in 0...expressions.length) {
			final child = copyExpression(expressions[index], OcamlTargetExpressionPath.indexed(path, "block-item", index));
			if (child == null)
				return null;
			children.push(child);
		}
		final blockType = expression.getType().getCanonicalDisplay();
		final resultType = children.length == 0 ? "Void" : children[children.length - 1].semanticTypeDisplay;
		return blockType == resultType ? OcamlTargetExpressionFact.block(path, blockType, children) : null;
	}

	function copyVariable(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		if (expression.getVariableIsStatic())
			return null;
		final nativeBindings = expression.getLocalBindings();
		final initializers = expression.getExpressions();
		if (nativeBindings.length != 1 || initializers.length != 1)
			return null;
		return copyDeclaration(nativeBindings[0], initializers[0], path);
	}

	/** Reserve each declaration once; whole-tree validation rejects reads before initialization. **/
	function copyDeclaration(nativeBinding:TyLocalBinding, initializerExpression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final identity = nativeBinding.getIdentity();
		if (nativeFunctionIdentity != null && identity.getOwnerIdentity() != nativeFunctionIdentity)
			throw "native OCaml function body contains a local from another function";
		if (bindingsByNativeKey.exists(identity.getCanonicalKey()))
			throw "native OCaml expression contains a repeated local declaration identity";
		final binding = HxhxOcamlTargetBindingAdapter.fromBinding(ownerIdentity, nativeBinding, OcamlTargetExpressionPath.child(path, "binding"));
		if (nativeBinding.getKind() != Variable)
			return null;
		bindingsByNativeKey.set(identity.getCanonicalKey(), binding);
		final initializer = copyExpression(initializerExpression, OcamlTargetExpressionPath.child(path, "initializer"));
		return initializer == null
			|| initializer.semanticTypeDisplay != binding.semanticTypeDisplay ? null : OcamlTargetExpressionFact.variableDeclaration(path, binding,
				initializer);
	}

	static function isDirectLiteral(literal:reflaxe.ocaml.target.OcamlTargetLiteralFact):Bool {
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
			throw "native OCaml expression adapter requires a target owner identity";
		return normalized;
	}
}
