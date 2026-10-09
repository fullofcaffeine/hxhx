import TyNestedFunctionId.TyNestedFunctionKind;

/** Same-spelled nested declarations must keep different local and generic owners. */
class M14NestedFunctionIdentityTest {
	static function identity(parent:String, ordinal:Int, kind:TyNestedFunctionKind = FunctionExpression):TyNestedFunctionId {
		return new TyNestedFunctionId({
			ownerIdentity: parent,
			sourceOrdinal: ordinal,
			form: Ordinary,
			origin: Authored,
			kind: kind
		});
	}

	static function main():Void {
		final first = identity("method:Main.run", 0);
		final replay = identity("method:Main.run", 0);
		final sibling = identity("method:Main.run", 1);
		final otherOwner = identity("method:Main.other", 0);
		final child = identity(first.getCanonicalKey(), 0);
		final local = identity("method:Main.run", 0, LocalDeclaration);
		final arrow = new TyNestedFunctionId({
			ownerIdentity: "method:Main.run",
			sourceOrdinal: 0,
			form: Arrow,
			origin: Authored,
			kind: FunctionExpression
		});
		final generated = new TyNestedFunctionId({
			ownerIdentity: "method:Main.run",
			sourceOrdinal: 0,
			form: Ordinary,
			origin: Generated,
			kind: FunctionExpression
		});
		if (!first.equals(replay))
			throw "replay changed the nested function owner";
		for (different in [sibling, otherOwner, child, local, arrow, generated])
			if (first.equals(different))
				throw "distinct nested functions share an owner";
		final firstT = TyTypeParameterId.nestedFunction(first, 0, "T");
		final siblingT = TyTypeParameterId.nestedFunction(sibling, 0, "T");
		final childT = TyTypeParameterId.nestedFunction(child, 0, "T");
		if (!firstT.equals(TyTypeParameterId.nestedFunction(replay, 0, "T")))
			throw "replay changed generic ownership";
		for (different in [siblingT, childT])
			if (TyType.typeParameter(firstT).getSemanticKey() == TyType.typeParameter(different).getSemanticKey())
				throw "same-named nested generic types were conflated";
		final firstParameter = TyLocalId.forSourceDeclaration(first.getCanonicalKey(), 0, Parameter, "value");
		final childParameter = TyLocalId.forSourceDeclaration(child.getCanonicalKey(), 0, Parameter, "value");
		if (firstParameter.equals(childParameter))
			throw "a nested parameter borrowed its parent's identity";
		final declaration = TyLocalId.forSourceDeclaration("method:Main.run", 0, NamedFunction, "f");
		final variable = TyLocalId.forSourceDeclaration("method:Main.run", 0, Variable, "f");
		if (declaration.equals(variable))
			throw "local function declaration became an ordinary variable";
		Sys.println("NESTED_FUNCTION_IDENTITY:PASS");
	}
}
