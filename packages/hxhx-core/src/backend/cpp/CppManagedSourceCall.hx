package backend.cpp;

import backend.cpp.CppManagedCallEmitter.CppManagedCallArgument;

/** Exact source selection distinguishes callable values from already resolved static declarations. */
enum CppManagedSourceCallee {
	Value(expression:HxExpr);
	Static(target:CppManagedStaticTarget);
}

/** The enclosing expression emitter owns source operands and its allocated native symbol prefix. */
typedef CppManagedSourceCallInput = {
	final callee:CppManagedSourceCallee;
	final ?casts:CppManagedCastPlan;
	final ?classes:CppManagedClassStorage;
	final arguments:Array<HxExpr>;
	final destination:Null<String>;
	final heap:String;
	final prefix:String;
	final renderValue:(HxExpr, String, String) -> Array<String>;
	final valueType:HxExpr->TyType;
	final acceptsStoredTransfer:(HxExpr, TyType) -> Bool;
}

/**
	Prepare allocating source operands for the shared native call sequencer.
	The selected function is retained before argument effects. Every source operand
	is published into common rooted transport before native argument adaptation.
	The expression owner validates each copy, including contextual Array class
	literals and widening stored Array class handles to an erased element type.
	Shared projection has already aligned supplied operands. Trailing optional
	function-value slots enter as null; required omissions remain rejected.
	Rest packing and conversions still need their typed call plans. Callable expressions
	use their owner's selected type and are rooted before argument effects begin.
 */
function render(input:CppManagedSourceCallInput, indent:String):Array<String> {
	switch input.callee {
		case Static(Downcast(declaration)):
			return CppManagedDowncast.render(declaration, input, indent);
		case _:
	}
	final signature = switch input.callee {
		case Value(expression): new CppManagedClosureAbi(input.valueType(expression));
		case Static(target): CppManagedStaticTarget.abi(target);
	};
	final staticTarget = switch input.callee {
		case Static(target): target;
		case Value(_): null;
	};
	final parameters = signature.getParameters();
	final declared = signature.signature.getFunctionParameters();
	if (input.arguments.length > parameters.length)
		throw "managed source call requires fully adapted source arity";
	for (slot in input.arguments.length...parameters.length)
		if (!declared[slot].isOptional || declared[slot].isRest)
			throw "managed source call requires fully adapted source arity";
	if (signature.result == NoResult && input.destination != null)
		throw "Void managed source call cannot publish a value";
	if (staticTarget != null)
		switch staticTarget {
			case Output(declaration):
				return CppManagedOutput.render(declaration, input, indent);
			case RuntimePredicate(declaration):
				return CppManagedRuntimePredicate.render(declaration, input, indent);
			case StandardString(declaration):
				return CppManagedStandardString.render(declaration, input, indent);
			case Downcast(_):
				throw "downcast must use its applied native operation";
			case NativeStack(declaration, storage):
				return CppManagedNativeStack.render(declaration, storage, input, indent);
			case Source(_, _):
		}
	final prefix = "hxhx_call_" + input.prefix + (input.destination == null ? "discarded" : input.destination) + "_";
	final callee = prefix + "callee";
	final calleeSetup = new Array<String>();
	if (staticTarget == null) {
		calleeSetup.push("hxhx::managed::Root<hxhx::managed::Value> " + callee + "(" + input.heap + ");");
		final expression = switch input.callee {
			case Value(value): value;
			case Static(_): throw "static call has no value callee";
		};
		for (line in input.renderValue(expression, callee, ""))
			calleeSetup.push(line);
	}
	final arguments = new Array<CppManagedCallArgument>();
	for (parameter in parameters) {
		final expression = parameter.slot < input.arguments.length ? input.arguments[parameter.slot] : null;
		final acceptedType = declared[parameter.slot].isOptional
			&& !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type;
		if (expression != null
			&& !input.acceptsStoredTransfer(expression, acceptedType)
			&& !CppManagedValueTransfer.needsConversion(acceptedType, input.valueType(expression), input.casts))
			throw "managed source argument requires an explicit typed conversion at slot "
				+ parameter.slot
				+ ": "
				+ input.valueType(expression).getSemanticKey()
				+ " -> "
				+ acceptedType.getSemanticKey();
		final root = prefix + "value" + parameter.slot;
		final setup = ["hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"];
		// A fresh common-value root contains null for an omitted optional slot.
		if (expression != null) {
			for (line in input.renderValue(expression, root, ""))
				setup.push(line);
			for (line in CppManagedValueTransfer.convertRoot(acceptedType, input.valueType(expression), root, "", input.casts))
				setup.push(line);
		}
		arguments.push({setup: setup, value: parameter.storage == RootedParameter ? root + ".get()" : CppManagedLeaf.read(parameter.type, root + ".get()")});
	}
	final result = prefix + "returned";
	final payload = "hxhx::managed::CallablePayload<" + signature.nativeSignature() + ">";
	final lines = ["{"];
	switch signature.result {
		case RootedResult:
			lines.push("  hxhx::managed::Root<hxhx::managed::Value> " + result + "(" + input.heap + ");");
		case DirectResult:
			lines.push("  " + signature.nativeReturnType() + " " + result + "{};");
		case NoResult:
	}
	final invocation = CppManagedCallEmitter.renderAbi(signature, {heap: input.heap,
		calleeSetup: calleeSetup,
		// A null function must reach ActiveCall: invocation fails after argument effects.
		callee: staticTarget != null ? CppManagedStaticTarget.sourceSymbol(staticTarget) : callee
		+ ".get().kind() == hxhx::managed::ValueKind::Null ? hxhx::managed::Ref<"
		+ payload
		+ ">{} : "
		+ callee
		+ ".get().asManaged().as<"
		+ payload
		+ ">()",
		arguments: arguments,
		destination: signature.result == NoResult ? null : result,
		temporaryPrefix: prefix
	});
	for (line in invocation.split("\n"))
		lines.push("  " + line);
	if (input.destination != null) {
		final value = signature.result == RootedResult ? result + ".get()" : CppManagedLeaf.box(signature.signature.getFunctionReturn(), result);
		lines.push("  " + input.destination + ".set(" + value + ");");
	} else if (signature.result == DirectResult) {
		lines.push("  (void)" + result + ";");
	}
	lines.push("}");
	return [for (line in lines) indent + line];
}
