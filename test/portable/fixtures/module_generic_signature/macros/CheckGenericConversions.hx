import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing as genericValueCrossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.matchInstantiation as genericValueMatchInstantiation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.parameterId as genericValueParameterId;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shape as genericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.PROOF_ID as genericCallProofId;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;

/** Checks conversion direction on the actual typed calls, before native generation. */
class CheckGenericConversions {
	public static function install():Void {
		Context.onAfterTyping(types -> {
			var count = 0;
			for (type in types)
				switch (type) {
					case TClassDecl(reference) if (reference.get().name == "First"):
						for (field in reference.get().statics.get()) {
							final expression = field.expr();
							if (expression == null)
								continue;
							function visit(current:TypedExpr):Void {
								switch (current.expr) {
									case TCall({expr: TField(_, FInstance(_, _, method)), t: callable}, _) if (method.get().params.length > 0):
										checkCall(field.name, method.get(), callable);
										count++;
									case _:
								}
								TypedExprTools.iter(current, visit);
							}
							visit(expression);
						}
					case _:
				}
			if (count != 14)
				throw 'expected 14 typed generic calls, found $count';
			checkRejections();
			Sys.println("GENERIC_CALL_CONVERSION_DIRECTION:PASS");
		});
	}

	static function checkCall(caller:String, method:ClassField, callable:Type):Void {
		final declared = genericValueShape(method.type);
		final instantiated = genericValueShape(callable);
		final owned = method.params.map(parameter -> genericValueParameterId(parameter.t));
		if (declared == null || instantiated == null || !genericValueMatchInstantiation(declared, instantiated, owned, new Map()))
			throw 'generic call lost its coherent instantiation: $caller';
		switch ([declared, instantiated]) {
			case [FunctionValue(parameters, result), FunctionValue(actualParameters, actualResult)]:
				final resultCrossing = Std.string(genericValueCrossing(result, actualResult));
				final nullableScalar = caller == "nullableNumber";
				final expectedResult = caller == "nullableFlag" ? "UnboxNullableBoolean" : method.name == "describe" ? "Identity" : nullableScalar ? "Identity" : (caller == "flag"
					|| caller == "nested" ? "UnboxBoolean" : "UnboxValue");
				if (resultCrossing != expectedResult)
					throw 'wrong result direction: $caller/$resultCrossing';
				final argumentCrossing = Std.string(genericValueCrossing(actualParameters[0], parameters[0]));
				final expectedArgument = caller == "nullableFlag" ? "AdaptFunction([],BoxNullableBoolean)" : method.name == "describe" ? "BoxNullableBoolean" : method.name == "fail" ? "Identity" : (nullableScalar ? "AdaptFunction([],Identity)" : (caller == "flag"
					|| caller == "nested" ? "AdaptFunction([],BoxBoolean)" : "AdaptFunction([],BoxValue)"));
				if (argumentCrossing != expectedArgument)
					throw 'wrong callback direction: $caller/$argumentCrossing';
				if (method.name == "skip" && Std.string(genericValueCrossing(actualParameters[1], parameters[1])) != "BoxValue")
					throw "concrete fallback did not cross into the generic parameter";
			case _:
				throw "generic method has no function boundary";
		}
	}

	static function checkRejections():Void {
		if (genericCallProofId.length == 0)
			throw "missing generic call contract version";
		final erased = Erased("Scope|within|T");
		final owned = ["Scope|within|T"];
		if (genericValueMatchInstantiation(erased, Integer, ["Scope|fail|T"], new Map()))
			throw "another method acquired the type parameter";
		final substitutions = new Map();
		if (!genericValueMatchInstantiation(erased, Integer, owned, substitutions)
			|| genericValueMatchInstantiation(erased, Text(false), owned, substitutions))
			throw "one generic parameter acquired inconsistent concrete types";
		if (genericValueMatchInstantiation(ArrayValue(erased), ArrayValue(Integer), owned, new Map()))
			throw "a container element changed storage without a container proof";
		if (genericValueCrossing(Integer, Text(false)) != null)
			throw "unrelated native types acquired a generic conversion";
		for (type in [
			Context.resolveType(macro :Dynamic, Context.currentPos()),
			Context.makeMonomorph(),
			Context.resolveType(macro :(?value:Int) -> Int, Context.currentPos())
		])
			if (genericValueShape(type) != null)
				throw "unsupported storage acquired a shape";
		final reverseArguments = genericValueCrossing(FunctionValue([Integer], Integer), FunctionValue([erased], erased));
		if (Std.string(reverseArguments) != "AdaptFunction([UnboxValue],BoxValue)")
			throw "callback inputs did not reverse conversion direction";
		if (Std.string(genericValueCrossing(FunctionValue([erased], erased), FunctionValue([Integer], Integer))) != "AdaptFunction([BoxValue],UnboxValue)")
			throw "returned callback did not reverse conversion direction";
	}
}
