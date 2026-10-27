import TyIndexedUpdateSelection.TyIndexedUpdateQuery;

/** Source positions, selected declaration orientation and conversion objects must agree together. */
private function validateInputs(input:{
	query:TyIndexedUpdateQuery,
	binding:TyBoundAbstractBinaryOperator,
	sources:Array<HxExpr>,
	types:Array<TyType>,
	plans:Array<TyAbstractBinaryConversion>
}):Void {
	final right = switch input.query.source {
		case EBinop(_, EArrayAccess(_, _), right): right;
		case _: throw "indexed binary input proof requires its compound source";
	};
	final binding = input.binding;
	final sources = binding.getReverseArguments() ? [right, input.query.getterSource] : [input.query.getterSource, right];
	final plans = binding.getReverseArguments() ? [binding.getSourceRightConversion(), binding.getSourceLeftConversion()] : [binding.getSourceLeftConversion(), binding.getSourceRightConversion()];
	final info = binding.getOperatorInfo();
	if (input.sources.length != 2 || input.types.length != 2 || input.plans.length != 2)
		throw "indexed operator lost its two selected input positions";
	for (offset in 0...2) {
		final expected = offset == 0 ? info.getLeftType() : info.getRightType();
		if (input.sources[offset] != sources[offset]
			|| input.plans[offset] != plans[offset]
			|| input.plans[offset].getActualType().getSemanticKey() != input.types[offset].getSemanticKey()
			|| input.plans[offset].getExpectedType().getSemanticKey() != expected.getSemanticKey())
			throw "selected indexed operator input belongs to another source position";
	}
}

/**
	Check one operation over retained getter/RHS facts inside the update candidate.
	Indexed unary steps follow the measured getter/setter contract and do not call
	a declared increment helper. Compound overloads keep the shared binary selector.
 */
function select(input:{
	query:TyIndexedUpdateQuery,
	trial:TyIndexedUpdateTrial,
	getterType:TyType,
	right:Null<HxExpr>,
	rightType:Null<TyType>,
	environment:TyFunctionEnv,
	index:TyperIndex,
	filePath:String,
	position:HxPos
}):{
	computed:TyIndexedComputedResult,
	binary:Null<TyBoundAbstractBinaryOperator>
} {
	final query = input.query;
	final scope = input.environment;
	final inference = scope.getInference();
	var left = inference.expressionType(query.getterSource, input.getterType, scope);
	var right = input.rightType;
	function fail(message:String):TyperError
		return new TyperError(input.filePath, input.position, message + " (haxe_ocaml-rgmu4)");
	var result:TyType;
	var bound:Null<TyBoundAbstractBinaryOperator> = null;
	var numericStep:Null<{
		final owner:TyAbstractInfo;
		final applied:TyType;
		final storage:TyType;
		final index:TyperIndex;
	}> = null;
	switch query.kind {
		case Unary(_, _):
			final integer = TyNullableIntegerResult.isInteger(left);
			if (!integer && !left.unwrapNull().isNumeric()) {
				final identity = left.getNominalIdentity();
				final owner = identity == null ? null : input.index.getAbstractByFullName(identity.getCanonicalName());
				if (owner == null)
					throw fail("Indexed increment/decrement requires a complete numeric getter");
				final storage = TyNominalApplication.applyType(input.index, owner, left, owner.getUnderlyingType());
				if (!storage.isNumeric())
					throw fail("Indexed increment/decrement requires a complete numeric abstract representation");
				numericStep = {
					owner: owner,
					applied: left,
					storage: storage,
					index: input.index
				};
			}
			result = integer ? TyType.fromHintText("Int") : left;
		case Compound(compound):
			final op = HxBinaryOperatorTools.baseOperator(compound);
			if (op == "+") {
				final operands = TyAdditionOperandInference.constrain({
					left: query.getterSource,
					right: input.right,
					leftType: left,
					rightType: right,
					scope: scope,
					index: input.index,
					filePath: input.filePath,
					position: input.position
				});
				left = operands.left;
				right = operands.right;
			}
			bound = TyAbstractBinaryBinding.select(input.index, left, right, compound, input.filePath, input.position);
			if (bound != null) {
				final info = bound.getOperatorInfo();
				final declaration = info.getDeclaration();
				final sources = bound.getReverseArguments() ? [input.right, query.getterSource] : [query.getterSource, input.right];
				final types = bound.getReverseArguments() ? [right, left] : [left, right];
				final plans = bound.getReverseArguments() ? [bound.getSourceRightConversion(), bound.getSourceLeftConversion()] : [bound.getSourceLeftConversion(), bound.getSourceRightConversion()];
				validateInputs({
					query: query,
					binding: bound,
					sources: sources,
					types: types,
					plans: plans
				});
				if (!declaration.getIsStatic()) {
					sources.shift();
					types.shift();
					plans.shift();
				}
				final signature = declaration.getSignature();
				final order = TyMethodArgumentOrder.select(signature, sources, (source, parameter, _) -> {
					if (source != parameter || source >= plans.length)
						return Incompatible;
					return Compatible;
				});
				if (order == null)
					throw fail("Selected indexed operator lost its declared argument order");
				result = inference.inferDirectCall({
					expression: query.computedSource,
					declaration: declaration,
					callable: TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType(),
					signature: signature,
					order: order,
					arguments: sources,
					actual: types,
					environment: scope,
					index: input.index,
					accepts: (_, _) -> false,
					acceptsAt: (source, expected,
						actual) -> source < plans.length
							&& order.parameterIndex(source) < signature.getArgs().length
							&& signature.getArgs()[order.parameterIndex(source)].getSemanticKey() == expected.getSemanticKey()
							&& plans[source].getExpectedType().getSemanticKey() == expected.getSemanticKey()
							&& plans[source].getActualType().getSemanticKey() == actual.getSemanticKey()});
			} else {
				if (["&", "|", "^", "<<", ">>", ">>>"].indexOf(op) >= 0) {
					TyBitwiseOperandInference.constrain({
						sources: [query.getterSource, input.right],
						types: [left, right],
						scope: scope,
						index: input.index,
						filePath: input.filePath,
						position: input.position
					});
					left = inference.expressionType(query.getterSource, left, scope);
					right = inference.expressionType(input.right, right, scope);
					if (left.unwrapNull().getSemanticKey() != "primitive:Int" || right.unwrapNull().getSemanticKey() != "primitive:Int")
						throw fail("Indexed bitwise operation requires Int operands");
					result = TyType.fromHintText("Int");
				} else if (op == "+"
					&& (left.unwrapNull().getSemanticKey() == "primitive:String"
						|| right.unwrapNull().getSemanticKey() == "primitive:String")) {
					result = TyType.fromHintText("String");
				} else {
					if ((!TyNullableIntegerResult.isInteger(left) && !left.unwrapNull().isNumeric())
						|| (!TyNullableIntegerResult.isInteger(right) && !right.unwrapNull().isNumeric()))
						throw fail("Indexed arithmetic requires complete numeric operands");
					result = op == "/" ? TyType.fromHintText("Float") : TyNullableIntegerResult.result(left, right);
					if (result == null)
						result = TyType.unify(left, right);
					if (result == null)
						throw fail("Indexed arithmetic operands are incompatible");
				}
			}
	}
	final operands = input.right == null ? [{source: query.getterSource, type: left}] : [
		{source: query.getterSource, type: left},
		{
			source: input.right,
			type: right
		}
	];
	final computed = bound == null ? TyIndexedComputedResult.builtin(query, result, operands,
		numericStep) : TyIndexedComputedResult.selected(query, bound, result, operands);
	computed.register(input.trial, scope);
	return {computed: computed, binary: bound};
}
