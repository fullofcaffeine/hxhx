package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodEntry;

private typedef BoundCallableEntry = {
	final target:CppManagedInstanceMethodEntry;
	final signature:TyType;
	final symbol:String;
}

/**
	Bridge stored methods to the ordinary closure transport without copying bodies.
	Haxe selects the concrete override and applied signature. Each receiver owns one
	traced callable per selection; the callable traces the live receiver, so later
	field mutations remain visible and unreachable receiver/callable cycles can die.
 */
class CppManagedBoundCallable {
	final methods:CppManagedBoundMethods;
	final classes:CppManagedClassStorage;
	final resolve:String->CppManagedInstanceMethodEntry;
	final entries = new haxe.ds.StringMap<BoundCallableEntry>();
	final ordered:Array<BoundCallableEntry> = [];
	final arrayPush:CppManagedArrayPushValue;

	public function new(classes:CppManagedClassStorage, resolve:String->CppManagedInstanceMethodEntry) {
		this.classes = classes;
		this.methods = classes.methods.bound;
		this.resolve = resolve;
		this.arrayPush = new CppManagedArrayPushValue(classes);
	}

	function select(application:CppManagedFunctionApplication, signature:TyType):BoundCallableEntry {
		application.assertCurrent();
		final target = resolve(application.identity);
		if (target == null || target.projection != application.projection || target.application.identity != application.identity)
			throw "managed bound method lacks its reachable native entry";
		final key = CompilerCacheIdentity.encode([application.identity, signature.getSemanticKey()]);
		var entry = entries.get(key);
		if (entry == null) {
			entry = {target: target, signature: signature, symbol: "hxhx_bound_" + ordered.length};
			entries.set(key, entry);
			ordered.push(entry);
		}
		return entry;
	}

	/** The caller roots the receiver before allocation and evaluates its source expression exactly once. */
	public function renderValue(input:{
		occurrence:TypedBackendMethodOccurrence,
		context:Null<CppManagedEnclosingApplication>,
		heap:String,
		destination:String,
		prefix:String,
		renderValue:(HxExpr, String, String) -> Array<String>
	}, indent:String):Array<String> {
		if (CppManagedArrayPush.selectsDeclaration(input.occurrence.getDeclaration()))
			return arrayPush.renderValue(input, indent);
		methods.application(input.occurrence, input.context);
		final cases = methods.dispatch(input.occurrence, input.context);
		final signature = CppManagedCallContext.resolveType(input.context, input.occurrence.getCallableType());
		final receiver = switch input.occurrence.getExpression() {
			case EField(value, _): value;
			case _: throw "managed bound method lost its exact receiver expression";
		};
		final root = input.prefix + "bound_receiver";
		final descriptor = input.prefix + "bound_descriptor";
		final lines = [
			indent + "{",
			indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
		];
		for (line in input.renderValue(receiver, root, indent + "  "))
			lines.push(line);
		lines.push(indent
			+ "  const auto* "
			+ descriptor
			+ " = &"
			+ root
			+ ".get().asManaged().as<hxhx::managed::InstancePayload>()->instanceDescriptor();");
		for (index in 0...cases.length) {
			final selected = select(cases[index].application, signature);
			lines.push(indent + "  " + (index == 0 ? "if" : "else if") + " (" + descriptor + " == &" + cases[index].descriptor + ") {");
			lines.push(indent + "    " + input.destination + ".set(" + selected.symbol + "_value(" + input.heap + ", " + root + ".get()));");
			lines.push(indent + "  }");
		}
		lines.push(indent
			+ "  "
			+ (cases.length == 0 ? "" : "else ")
			+ "{ throw std::invalid_argument(\"bound method received an unplanned receiver descriptor\"); }");
		lines.push(indent + "}");
		return lines;
	}

	/** Emit after body admission discovers entries, but before any body that uses them. */
	public function render():String {
		return arrayPush.render() + "\n" + [for (entry in ordered) renderEntry(entry)].join("\n");
	}

	function renderEntry(entry:BoundCallableEntry):String {
		final target = entry.target;
		target.application.assertCurrent();
		final direct = new CppManagedStoragePlan(target.projection, classes, target.application).requireFunction(Root(target.projection)).abi;
		final callable = new CppManagedClosureAbi(entry.signature);
		if (!direct.getHiddenParameters().contains(ReceiverValue)
			|| direct.getParameters().length != callable.getParameters().length
			|| (direct.result == NoResult) != (callable.result == NoResult))
			throw "managed bound method bridge requires matching receiver, arity and result contracts";
		final lines = [
			"inline " + CppManagedEntrySignature.render(callable, entry.symbol) + " {",
			"  hxhx::managed::Root<hxhx::managed::Value> hxhx_bound_receiver(hxhx_heap, hxhx::managed::Value::managed(hxhx_environment));"
		];
		final args = ["hxhx_heap", "hxhx_bound_receiver.get()"];
		if (direct.result == RootedResult) {
			lines.push("  hxhx::managed::Root<hxhx::managed::Value> hxhx_bound_result(hxhx_heap);");
			args.push("hxhx_bound_result");
		}
		final declared = direct.signature.getFunctionParameters();
		final sourceDeclared = callable.signature.getFunctionParameters();
		for (parameter in direct.getParameters()) {
			final source = callable.getParameters()[parameter.slot];
			final argument = "hxhx_arg" + parameter.slot;
			final root = "hxhx_bound_argument" + parameter.slot;
			final sourceType = sourceDeclared[parameter.slot].isOptional
				&& !source.type.isNullable() ? TyType.nullable(source.type) : source.type;
			final targetType = declared[parameter.slot].isOptional
				&& !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type;
			lines.push("  hxhx::managed::Root<hxhx::managed::Value> "
				+ root
				+ "(hxhx_heap, "
				+ (source.storage == RootedParameter ? argument : CppManagedLeaf.box(source.type, argument))
				+ ");");
			for (line in CppManagedValueTransfer.convertRoot(targetType, sourceType, root, "  ", classes.casts))
				lines.push(line);
			args.push(parameter.storage == RootedParameter ? root + ".get()" : CppManagedLeaf.read(parameter.type, root + ".get()"));
		}
		final invocation = target.symbol + "(" + args.join(", ") + ")";
		if (direct.result == NoResult)
			lines.push("  " + invocation + ";");
		else {
			if (direct.result == RootedResult)
				lines.push("  " + invocation + ";");
			else
				lines.push("  hxhx::managed::Root<hxhx::managed::Value> hxhx_bound_result(hxhx_heap, "
					+ CppManagedLeaf.box(direct.signature.getFunctionReturn(), invocation)
					+ ");");
			for (line in CppManagedValueTransfer.convertRoot(callable.signature.getFunctionReturn(), direct.signature.getFunctionReturn(),
				"hxhx_bound_result", "  ", classes.casts))
				lines.push(line);
			lines.push(callable.result == RootedResult ? "  hxhx_result.set(hxhx_bound_result.get());" : "  return "
				+ CppManagedLeaf.read(callable.signature.getFunctionReturn(), "hxhx_bound_result.get()")
				+ ";");
		}
		lines.push("}");
		lines.push("inline char " + entry.symbol + "_key;");
		lines.push("inline hxhx::managed::Value " + entry.symbol + "_value(hxhx::managed::Heap& hxhx_heap, hxhx::managed::Value receiver) {");
		lines.push("  hxhx::managed::Root<hxhx::managed::Value> owner(hxhx_heap, receiver);");
		lines.push("  const auto cached = owner.get().asManaged().as<hxhx::managed::InstancePayload>()->boundCallable(&" + entry.symbol + "_key);");
		lines.push("  if (cached.kind() != hxhx::managed::ValueKind::Null) return cached;");
		final payload = "hxhx::managed::CallablePayload<" + callable.nativeSignature() + ">";
		lines.push("  hxhx::managed::Root<hxhx::managed::Ref<" + payload + ">> value(hxhx_heap);");
		lines.push("  hxhx_heap.allocateInto(value, &" + entry.symbol + ", owner.get().asManaged());");
		lines.push("  const auto result = hxhx::managed::Value::managed(value.get());");
		lines.push("  owner.get().asManaged().as<hxhx::managed::InstancePayload>()->storeBoundCallable(&" + entry.symbol + "_key, result);");
		lines.push("  return result;\n}");
		return lines.join("\n");
	}
}
