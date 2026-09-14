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

	function copyExpression(expression:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		return switch (expression.expr) {
			case TCall(callee, []) if (TypeTools.toString(expression.t) == "Void"):
				copyCall(callee, path);
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

	/** The host must resolve an ordinary static declaration before we copy its identity. **/
	function copyCall(callee:TypedExpr, path:String):Null<OcamlTargetExpressionFact> {
		return switch (callee.expr) {
			case TField({expr: TTypeExpr(TClassDecl(receiver))}, FStatic(owner, reference)):
				final cls = owner.get();
				final field = reference.get();
				final ordinary = switch (field.kind) {
					case FMethod(MethNormal): true;
					case _: false;
				};
				final signature = switch (field.type) {
					case TFun([], result): TypeTools.toString(result) == "Void";
					case _: false;
				};
				if (sourceOwner == null || cls.module != sourceOwner.module || cls.name != sourceOwner.name || receiver.get().module != cls.module
					|| receiver.get().name != cls.name || cls.isExtern || cls.params.length != 0 || !ordinary || !signature || field.params.length != 0
					|| field.expr() == null || field.meta.get().length != 0) {
					null;
				} else {
					OcamlTargetExpressionFact.directStaticCall(path, new OcamlTargetStaticCallFact({
						moduleId: cls.module,
						sourceTypeName: cls.name,
						sourceFunctionName: field.name
					}));
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
