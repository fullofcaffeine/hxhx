package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionPath;

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
		Copy a typed function's statement tree using the existing expression contract.

		One adapter owns the whole body so local reads keep their exact declaration
		identity across nested blocks. The shared target validates lexical visibility
		and owns lowering. Unsupported statements reject the complete body.
	**/
	public static function fromFunctionBody(ownerIdentity:String, nativeFunctionIdentity:String, body:TypedFunctionBody,
			sourceOwner:TyNominalInfo):Null<OcamlTargetExpressionFact> {
		if (body == null)
			throw "native OCaml expression adapter requires a typed function body";
		final adapter = new HxhxOcamlTargetExpressionAdapter(ownerIdentity, requiredOwner(nativeFunctionIdentity), sourceOwner);
		final fact = adapter.copyStatements(body.getStatements(), OcamlTargetExpressionPath.ROOT);
		if (fact != null)
			fact.validateClosedBindings();
		return fact;
	}

	/** Preserve source order and block nesting without adding target lowering decisions. **/
	function copyStatements(statements:Array<TypedStmt>, path:String):Null<OcamlTargetExpressionFact> {
		final children = new Array<OcamlTargetExpressionFact>();
		for (index in 0...statements.length) {
			final statement = statements[index];
			final childPath = OcamlTargetExpressionPath.indexed(path, "block-item", index);
			final expressions = statement.getExpressions();
			final child = switch (statement.getTag()) {
				case Var: final bindings = statement.getLocalBindings(); bindings.length == 1 && expressions.length == 1 ? copyDeclaration(bindings[0],
						expressions[0], childPath) : null;
				case Expression:
					expressions.length == 1 ? copyExpression(expressions[0], childPath) : null;
				case Block:
					copyStatements(statement.getStatements(), childPath);
				case _:
					null;
			};
			if (child == null)
				return null;
			children.push(child);
		}
		final resultType = children.length == 0 ? "Void" : children[children.length - 1].semanticTypeDisplay;
		return OcamlTargetExpressionFact.block(path, resultType, children);
	}

	function copyExpression(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final literal = HxhxOcamlTargetLiteralAdapter.fromExpression(expression);
		if (literal != null)
			return isDirectLiteral(literal) ? OcamlTargetExpressionFact.literalExpression(path, literal) : null;
		return switch (expression.getTag()) {
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
			case Block:
				copyNativeBlock(expression, path);
			case _:
				null;
		};
	}

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

	/** Copy only a resolved bare static call; computed receivers must retain their effects. **/
	function copyCall(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		final declaration = expression.getDeclaration();
		final children = expression.getExpressions();
		if (sourceOwner == null
			|| declaration == null
			|| children.length != 1
			|| children[0].getTag() != NameRead
			|| children[0].getExpressions().length != 0
			|| expression.getExtensionProvider() != null
			|| expression.getType().getCanonicalDisplay() != "Void"
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
		if (!signature.getIsStatic() || signature.getArgs().length != 0 || signature.getReturnType().getCanonicalDisplay() != "Void")
			return null;
		return OcamlTargetExpressionFact.directStaticCall(path, new reflaxe.ocaml.target.OcamlTargetStaticCallFact({
			moduleId: sourceOwner.getModulePath(),
			sourceTypeName: sourceOwner.getShortName(),
			sourceFunctionName: signature.getName()
		}));
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
