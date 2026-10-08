package reflaxe.ocaml.lowered;

import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;

/** One raw OCaml representation operation, owned by a validated callback occurrence and role. */
typedef CallableViewUnsafeOperation = {
	final id:String;
	final decisionId:String;
	final role:String;
	final operation:String;
	final input:String;
	final output:String;
};

/**
	Enumerate raw operations from the typed adapter rather than generated text.

	Arguments reverse the input/output direction. Nullable Boolean adapters only
	unwrap the non-null branch; their private helper uses are accounted separately.
	The origin operation stores a fresh token or a stable declaration identity.
**/
function unsafeOperations(decision:OcamlCallableViewLocalDecision):Array<CallableViewUnsafeOperation> {
	requireDecision(decision);
	return valueUnsafeOperations(reflaxe.ocaml.lowered.OcamlCallableViewContract.operation(decision));
}

/** Writes, arguments, returns and comparison operands enumerate the same selected native mechanisms. */
function valueUnsafeOperations(operation:OcamlCallableValueOperation):Array<CallableViewUnsafeOperation> {
	reflaxe.ocaml.lowered.OcamlCallableValueOperation.requireOperation(operation);
	final result:Array<CallableViewUnsafeOperation> = [];
	function add(role:String, mechanism:String, input:String, output:String):Void {
		result.push({
			id: '${operation.id}:unsafe:$role',
			decisionId: operation.id,
			role: role,
			operation: mechanism,
			input: input,
			output: output
		});
	}
	switch (operation.origin) {
		case FreshLiteral:
			add("origin-identity", "Obj.repr", "fresh-identity-cell", "identity-token");
		case StaticDeclaration(_):
			add("origin-identity", "Obj.repr", "static-declaration-closure", "identity-token");
		case null:
	}
	function visit(conversion:OcamlGenericValueConversion, input:OcamlGenericValueShape, output:OcamlGenericValueShape, role:String):Void {
		switch (conversion) {
			case BoxValue:
				add(role, "Obj.repr", shapeId(input), shapeId(output));
			case UnboxValue:
				add(role, "Obj.obj", shapeId(input), shapeId(output));
			case BoxNullableBoolean:
				add('$role/non-null', "Obj.obj", "non-null-Null<Bool>", "Bool");
			case UnboxNullableBoolean:
				add('$role/non-null', "Obj.repr", "Bool", "Null<Bool>");
			case AdaptFunction(arguments, conversionResult):
				switch ([input, output]) {
					case [FunctionValue(inputs, inputResult), FunctionValue(outputs, outputResult)]:
						for (index in 0...arguments.length)
							visit(arguments[index], outputs[index], inputs[index], '$role/argument:$index');
						visit(conversionResult, inputResult, outputResult, '$role/result');
					case _: throw "Callback unsafe evidence lost its validated function layout.";
				}
			case Identity, BoxBoolean, UnboxBoolean:
		}
	}
	visit(operation.conversion, operation.inputLayout.shape, operation.outputLayout.shape, operation.role);
	return result;
}
