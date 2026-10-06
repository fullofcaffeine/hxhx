package backend.cpp;

import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodEntry;

/** One admitted allocation selects an authored conversion or its ordinary class name. */
private typedef ManagedStringCase = {
	final descriptor:String;
	final name:String;
	final method:Null<CppManagedFunctionApplication>;
}

/**
	Retain implicit toString calls before the program freezes its reachable bodies.
	Std.string receives erased values, so each reached allocation selects its most
	derived declaration through the shared class graph. Native code only dispatches
	on the descriptor chosen by that allocation. This plan does not invent source
	call occurrences, copy method bodies, or treat an unknown layout as printable.
 */
class CppManagedStringMethods {
	final program:CppTypedProgramProjection;
	final classes:CppManagedClassStorage;
	var enabled:Bool = false;
	var sealed:Bool = false;
	var cases:Array<ManagedStringCase> = [];

	public function new(program:CppTypedProgramProjection, classes:CppManagedClassStorage) {
		this.program = program;
		this.classes = classes;
	}

	/** Only an admitted standard declaration enables this implicit call family. */
	public function enable():Void {
		if (sealed)
			throw "managed string conversion discovered after reachability was sealed";
		enabled = true;
	}

	public function isEnabled():Bool
		return enabled;

	/** A newly reached conversion body may itself allocate another printable class. */
	public function discover():Array<CppManagedFunctionApplication> {
		if (!enabled)
			return [];
		if (sealed)
			throw "managed string targets cannot change after reachability was sealed";
		program.assertCurrent();
		final selected = new Array<ManagedStringCase>();
		for (allocation in classes.methods.stringAllocations()) {
			var method:Null<CppManagedFunctionApplication> = null;
			for (node in program.getClassGraph().requireLineage(allocation.getNominalIdentity().getCanonicalName())) {
				final owner = program.requireClass(program.requireClassIdentity(node.classIdentity));
				if (owner.requireSemanticFacts()
					.copyFields()
					.filter(field -> !field.isStatic && field.name == "toString")
					.length != 0)
					throw "managed string conversion requires function-valued field dispatch (haxe_ocaml-hcnk8)";
				final matches = owner.getFunctions()
					.filter(fn -> !fn.requireSemanticDeclaration().getIsStatic()
						&& fn.requireSemanticDeclaration().getSignature().getName() == "toString");
				if (matches.length > 1)
					throw "managed string conversion requires an exact overload plan";
				if (matches.length == 0)
					continue;
				method = classes.methods.ordinaryMethodApplication(matches[0], allocation);
				if (method.parameterTypes().length != 0 || method.resultType().getSemanticKey() != "primitive:String")
					throw "managed string conversion requires its parameterless String method contract";
				break;
			}
			final descriptor = classes.requireType(allocation).symbol;
			final existing = selected.filter(entry -> entry.descriptor == descriptor);
			if (existing.length != 0) {
				final previous = existing[0].method;
				if ((previous == null) != (method == null) || (method != null && previous.identity != method.identity))
					throw "managed string conversion requires distinct generic receiver applications (haxe_ocaml-hcnk8)";
				continue;
			}
			final facts = program.requireClass(program.requireClassIdentity(allocation.getNominalIdentity().getCanonicalName())).requireSemanticFacts();
			selected.push({descriptor: descriptor, name: facts.getDeclaredName(), method: method});
		}
		cases = selected;
		return [for (entry in cases) if (entry.method != null) entry.method];
	}

	/** The program calls this only after implicit and explicit call discovery converges. */
	public function seal():Void {
		program.assertCurrent();
		if (sealed)
			throw "managed string targets were already sealed";
		sealed = true;
	}

	/**
		Method declarations precede this function; definitions may call it recursively.
		Keep the receiver rooted across user code and pass the existing result root
		directly, preserving null returns and exceptions without another conversion.
	 */
	public function render(resolve:CppManagedFunctionApplication->CppManagedInstanceMethodEntry):String {
		if (!enabled)
			return "";
		if (!sealed)
			throw "managed string dispatch requires sealed reachability";
		program.assertCurrent();
		final lines = [
			"inline void hxhx_standard_string(hxhx::managed::Heap& heap, hxhx::managed::Value input, hxhx::managed::Root<hxhx::managed::Value>& result) {",
			"  hxhx::managed::Root<hxhx::managed::Value> value(heap, input);",
			"  if (value.get().kind() == hxhx::managed::ValueKind::Managed && value.get().asManaged().hasLayout<hxhx::managed::InstancePayload>()) {"
		];
		if (cases.length != 0)
			lines.push("    const auto descriptor = &value.get().asManaged().as<hxhx::managed::InstancePayload>()->descriptor();");
		for (entry in cases) {
			lines.push("    if (descriptor == &" + entry.descriptor + ") {");
			if (entry.method == null) {
				lines.push("      result.set(hxhx::managed::Value::string(" + CppManagedText.quotedBytes(entry.name) + "));");
			} else {
				entry.method.assertCurrent();
				final target = resolve(entry.method);
				if (target == null || target.application.identity != entry.method.identity || target.projection != entry.method.projection)
					throw "managed string conversion lost its exact linked method";
				final abi = new CppManagedClosureAbi(CppManagedFunctionSignature.resolve(target.projection, target.application.resolveStorageType), false,
					ReceiverValue);
				if (abi.result != RootedResult || abi.getParameters().length != 0)
					throw "managed string conversion changed its native method transport";
				lines.push("      " + target.symbol + "(heap, value.get(), result);");
			}
			lines.push("      return;\n    }");
		}
		lines.push('    throw std::invalid_argument("managed string conversion received an unplanned instance descriptor");');
		lines.push("  }");
		for (line in CppManagedStringConversion.render(TyType.fromHintText("Dynamic"), "value.get()", "bytes"))
			lines.push("  " + line);
		lines.push("  result.set(hxhx::managed::Value::string(bytes));\n}");
		return lines.join("\n");
	}
}
