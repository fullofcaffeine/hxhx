/**
	Turn an applied multi-type constructor into its exact authored factory call.
	Haxe passes a null backing-storage argument before the constructor operands.
	The selected callable validates those operands without evaluating or reordering
	them. The outer abstract view preserves the factory's runtime representation.
 */
class TypedMultiTypeConstruction {
	final selection:TyMultiTypeSelection;
	final binding:TypedNamedCallBinding;

	public function new(selection:TyMultiTypeSelection, index:TyperIndex, sources:Array<HxExpr>, types:Array<TyType>) {
		selection.assertCurrent(index, selection.getConstructedType());
		this.selection = selection;
		final callable = selection.getCallableType();
		final arguments = [HxExpr.ENull].concat(sources);
		final argumentTypes = [callable.getFunctionArguments()[0]].concat(types);
		binding = new TypedNamedCallBinding(selection.getDeclaration(), null,
			TyCallbackArgumentContext.publish(TyCallableSignature.fromFunctionValue(callable), arguments, argumentTypes, index));
	}

	/** A copied construction cannot borrow the selected declaration with changed operands or result type. */
	public function apply(arguments:Array<TypedExpr>, result:TyType, position:Null<HxPos>):TypedExpr {
		if (result.getSemanticKey() != selection.getConstructedType().getSemanticKey())
			throw "multi-type construction belongs to another applied result";
		final declaration = selection.getDeclaration();
		final callable = selection.getCallableType();
		final operands = [TypedExpr.nullValue(callable.getFunctionArguments()[0], position)].concat(arguments);
		final kinds = TypedExpr.operandKinds(operands);
		binding.assertCurrent(declaration, null, TypedExpr.operandTypes(operands, kinds), kinds, selection.getStorageType());
		final callee = TypedExpr.staticMethodRead(declaration.getSignature().getName(), declaration, callable, position, true);
		final call = TypedExpr.call(callee, operands, declaration, selection.getStorageType(), position, true).withNamedArguments(binding);
		return TypedExpr.castValue(call, "", result, position, true);
	}

	public function getSemanticKey():String
		return CompilerCacheIdentity.encode([selection.getConstructedType().getSemanticKey(), binding.getSemanticKey()]);
}
