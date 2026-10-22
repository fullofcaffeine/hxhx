import backend.cpp.CppManagedClosureAbi;
import backend.cpp.CppManagedCallableRepresentation.compatible;
import backend.cpp.CppManagedValueTransfer.accepts;
import backend.cpp.CppManagedValueTransfer.conditionalStorage;

/** Function-value storage preserves null without widening unrelated source types or calling conventions. */
class M14CppManagedCallableRepresentationTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		for (name in ["Int", "Bool"]) {
			final scalar = TyType.fromHintText(name);
			final direct = TyType.functionType([scalar], scalar);
			final nullable = TyType.functionType([TyType.nullable(scalar)], TyType.nullable(scalar));
			check(conditionalStorage(scalar, scalar).getSemanticKey() == scalar.getSemanticKey(), "equal branches changed storage");
			check(conditionalStorage(scalar, TyType.nullable(scalar)).getSemanticKey() == "nullable:" + scalar.getSemanticKey(),
				"conditional discarded null from its second branch");
			check(conditionalStorage(TyType.nullable(scalar), scalar).getSemanticKey() == "nullable:" + scalar.getSemanticKey(),
				"conditional discarded null from its first branch");
			final valueAbi = new CppManagedClosureAbi(direct);
			check(valueAbi.result == RootedResult
				&& valueAbi.getParameters()[0].storage == RootedParameter, "function value lost common scalar transport");
			check(valueAbi.nativeSignature() == new CppManagedClosureAbi(nullable).nativeSignature(), "generic view changed native calling convention");
			check(accepts(direct, nullable) && accepts(nullable, direct), "generic function view requires a new allocation");
			final declared = new CppManagedClosureAbi(direct, false);
			check(declared.result == DirectResult
				&& declared.getParameters()[0].storage == DirectParameter, "direct declaration lost scalar transport");
			final optional = TyType.functionSignature([
				{
					name: "value",
					type: scalar,
					isOptional: true,
					isRest: false,
					metadata: []
				}
			], scalar);
			check(!compatible(direct, optional), "storage view changed optional argument presence");
			final rest = TyType.functionSignature([
				{
					name: "values",
					type: scalar,
					isOptional: false,
					isRest: true,
					metadata: []
				}
			], scalar);
			check(!compatible(direct, rest), "storage view changed rest argument packing");
			check(!compatible(direct, TyType.functionType([], scalar)), "storage view changed source arity");
		}
		final ints = TyType.functionType([], TyType.fromHintText("Int"));
		final bools = TyType.functionType([], TyType.fromHintText("Bool"));
		check(!accepts(ints, bools), "common native storage erased Int/Bool source distinction");
		check(!accepts(ints, TyType.functionType([], TyType.fromHintText("Dynamic"))), "callable transfer silently admitted erased results");
		final number = TyType.fromHintText("Float");
		final floats = TyType.functionType([number], number);
		final floatAbi = new CppManagedClosureAbi(floats);
		check(floatAbi.result == DirectResult
			&& floatAbi.getParameters()[0].storage == DirectParameter, "Float calling convention changed");
		check(!compatible(floats, TyType.functionType([TyType.nullable(number)], TyType.nullable(number))), "Float null policy changed");
		var rejected = false;
		try
			compatible(ints, TyType.functionType([], TyType.unknown()))
		catch (_:haxe.Exception)
			rejected = true;
		check(rejected, "incomplete callback storage was admitted");
		for (pair in [
			[TyType.fromHintText("Int"), TyType.fromHintText("Bool")],
			[TyType.fromHintText("Int"), TyType.fromHintText("String")],
			[number, TyType.nullable(number)],
			[TyType.fromHintText("Int"), TyType.unknown()]
		]) {
			var invalidConditional = false;
			try
				conditionalStorage(pair[0], pair[1])
			catch (_:haxe.Exception)
				invalidConditional = true;
			check(invalidConditional, "conditional admitted unrelated or incomplete branch storage");
		}
		Sys.println("CPP_MANAGED_CALLABLE_REPRESENTATION:PASS");
	}
}
