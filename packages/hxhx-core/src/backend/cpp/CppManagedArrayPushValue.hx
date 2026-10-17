package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

private typedef ArrayPushEntry = {
	final signature:TyType;
	final symbol:String;
}

/**
	Bind the standard Array.push declaration to its existing native storage operation.
	The exact executable occurrence supplies receiver and callable types. Each array
	retains one traced callable per applied signature, matching native C++ method
	equality. The callable traces its original array after a source variable changes;
	the managed heap can collect the cycle when neither value remains reachable.
 */
class CppManagedArrayPushValue {
	final classes:CppManagedClassStorage;
	final entries = new haxe.ds.StringMap<ArrayPushEntry>();
	final ordered:Array<ArrayPushEntry> = [];

	public function new(classes:CppManagedClassStorage) {
		this.classes = classes;
	}

	/** Native bindings require owned typed selections, never fabricated ordinary method bodies. */
	public static function require(occurrence:TypedBackendMethodOccurrence, context:Null<CppManagedEnclosingApplication>,
			classes:CppManagedClassStorage):TyType {
		classes.methods.bound.requireOwned(occurrence, context);
		CppManagedArrayPush.requireDeclaration(occurrence.getDeclaration());
		final signature = CppManagedCallContext.resolveType(context, occurrence.getCallableType());
		CppManagedClosureAbi.assertComplete(signature);
		final parameters = signature.getFunctionParameters();
		if (!signature.isFunction()
			|| parameters.length != 1
			|| parameters[0].isOptional
			|| parameters[0].isRest
			|| signature.getFunctionReturn().getSemanticKey() != "primitive:Int")
			throw "managed Array.push value requires its exact applied callable signature";
		var receiver = CppManagedCallContext.resolveType(context, occurrence.getReceiverType());
		CppManagedArrayAppend.requireTypes(receiver, signature.getFunctionArguments()[0], classes.casts);
		while (receiver.getNullableInner() != null)
			receiver = receiver.getNullableInner();
		if (receiver.getTypeArguments()[0].getSemanticKey() != signature.getFunctionArguments()[0].getSemanticKey())
			throw "managed Array.push value changed its applied element type";
		return signature;
	}

	/** Evaluate and root the selected receiver before allocating its callable. */
	public function renderValue(input:{
		occurrence:TypedBackendMethodOccurrence,
		context:Null<CppManagedEnclosingApplication>,
		heap:String,
		destination:String,
		prefix:String,
		renderValue:(HxExpr, String, String) -> Array<String>
	}, indent:String):Array<String> {
		final signature = require(input.occurrence, input.context, classes);
		final key = signature.getSemanticKey();
		var entry = entries.get(key);
		if (entry == null) {
			entry = {signature: signature, symbol: "hxhx_array_push_value_" + ordered.length};
			entries.set(key, entry);
			ordered.push(entry);
		}
		final receiver = switch input.occurrence.getExpression() {
			case EField(value, _): value;
			case _: throw "managed Array.push value lost its exact receiver expression";
		};
		final root = input.prefix + "array_receiver";
		final lines = [
			indent + "{",
			indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
		];
		for (line in input.renderValue(receiver, root, indent + "  "))
			lines.push(line);
		lines.push(indent + "  " + input.destination + ".set(" + entry.symbol + "_value(" + input.heap + ", " + root + ".get()));");
		lines.push(indent + "}");
		return lines;
	}

	/** Emit the entries discovered during body rendering before any generated body uses them. */
	public function render():String {
		return [for (entry in ordered) renderEntry(entry)].join("\n");
	}

	function renderEntry(entry:ArrayPushEntry):String {
		final abi = new CppManagedClosureAbi(entry.signature);
		final parameter = abi.getParameters()[0];
		if (abi.result != RootedResult)
			throw "managed Array.push value requires the ordinary callable Int result transport";
		final value = parameter.storage == RootedParameter ? "hxhx_arg0" : CppManagedLeaf.box(parameter.type, "hxhx_arg0");
		final lines = [
			"inline " + CppManagedEntrySignature.render(abi, entry.symbol) + " {",
			"  hxhx::managed::Root<hxhx::managed::Value> owner(hxhx_heap, hxhx::managed::Value::managed(hxhx_environment));",
			"  hxhx::managed::Root<hxhx::managed::Value> element(hxhx_heap, " + value + ");"
		];
		// Function values share the same required-scalar ingress as authored closures.
		if (parameter.storage == RootedParameter && CppManagedCallableRepresentation.scalar(parameter.type))
			for (line in CppManagedValueTransfer.convertRoot(parameter.type, TyType.nullable(parameter.type), "element", "  ", classes.casts))
				lines.push(line);
		for (line in CppManagedArrayAppend.publish({
			array: "owner",
			element: "element",
			payload: "array",
			destination: "hxhx_result"
		}, "  "))
			lines.push(line);
		lines.push("}");
		lines.push("inline char " + entry.symbol + "_key;");
		lines.push("inline hxhx::managed::Value " + entry.symbol + "_value(hxhx::managed::Heap& hxhx_heap, hxhx::managed::Value receiver) {");
		lines.push("  hxhx::managed::Root<hxhx::managed::Value> owner(hxhx_heap, receiver);");
		lines.push("  const auto cached = owner.get().asManaged().as<hxhx::managed::ArrayPayload>()->boundCallable(&" + entry.symbol + "_key);");
		lines.push("  if (cached.kind() != hxhx::managed::ValueKind::Null) return cached;");
		final payload = "hxhx::managed::CallablePayload<" + abi.nativeSignature() + ">";
		lines.push("  hxhx::managed::Root<hxhx::managed::Ref<" + payload + ">> value(hxhx_heap);");
		lines.push("  hxhx_heap.allocateInto(value, &" + entry.symbol + ", owner.get().asManaged());");
		lines.push("  const auto result = hxhx::managed::Value::managed(value.get());");
		lines.push("  owner.get().asManaged().as<hxhx::managed::ArrayPayload>()->storeBoundCallable(&" + entry.symbol + "_key, result);");
		lines.push("  return result;\n}");
		return lines.join("\n");
	}
}
