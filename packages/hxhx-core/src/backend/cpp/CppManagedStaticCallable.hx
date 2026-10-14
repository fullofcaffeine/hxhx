package backend.cpp;

/** Select a static method value from typed evidence, never from its projected name. */
function declaration(source:Null<TypedExpr>):Null<TyDeclarationInfo> {
	if (source == null || !source.getType().isFunction() || (source.getTag() != NameRead && source.getTag() != FieldRead))
		return null;
	final selected = source.getDeclaration();
	return selected != null && selected.getIsStatic() && !selected.getIsEnumConstructor() ? selected : null;
}

/** Match the occurrence to the exact authored declaration in this native program. */
function requireTarget(source:TypedExpr, resolve:String->CppManagedStaticTarget):CppManagedStaticTarget {
	final selected = declaration(source);
	if (selected == null || resolve == null)
		throw "managed static function value requires its exact program declaration";
	for (qualifier in source.getExpressions())
		if (!typeQualifier(qualifier))
			throw "managed static method value requires explicit receiver-effect lowering";
	final target = resolve(selected.getIdentity().getCanonicalKey());
	switch target {
		case Source(projection, _):
			if (projection.requireSemanticDeclaration() != selected)
				throw "managed static function value belongs to another typed program";
		case _:
			throw "managed native operation requires an explicit function-value entry";
	}
	if (selected.getIsDynamic())
		throw "managed dynamic method value requires replaceable method storage";
	final signature = CppManagedStaticTarget.abi(target).signature;
	if (signature.getSemanticKey() != source.getType().getSemanticKey())
		throw "managed static function value requires its exact applied signature";
	return target;
}

/** Class qualification has no runtime effects; ordinary value receivers need explicit lowering. */
private function typeQualifier(source:TypedExpr):Bool {
	return switch source.getTag() {
		case RuntimeTypeValue: true;
		case NameRead: source.getFieldInfo() == null && source.getDeclaration() == null;
		case FieldRead:
			source.getFieldInfo() == null
			&& source.getDeclaration() == null
			&& source.getExpressions().length == 1
			&& typeQualifier(source.getExpressions()[0]);
		case _: false;
	};
}

/** One heap-owned value per declaration preserves repeated reads and survives collection. */
function renderValue(source:TypedExpr, resolve:String->CppManagedStaticTarget, storage:CppManagedStaticStorage, heap:String, destination:String,
		indent:String):Array<String> {
	if (storage == null)
		throw "managed static function value requires program storage";
	final target = requireTarget(source, resolve);
	final selected = declaration(source);
	storage.callableMember(selected);
	return [
		indent + destination + ".set(" + CppManagedStaticTarget.sourceSymbol(target) + "_value(" + heap + "));"
	];
}

/**
	Bridge the existing direct entry to function-value transport without a second body.
	The caller roots incoming managed arguments. The direct entry roots its own
	parameters before effects. Scalar arguments/results cross the same explicit
	boxing boundary as ordinary closures. Optional arguments remain null until the
	authored method applies its default. Each heap owns its memoized callable.
 */
function renderEntry(target:CppManagedStaticTarget, storage:CppManagedStaticStorage):String {
	final selected = switch target {
		case Source(projection, _): projection.requireSemanticDeclaration();
		case _: throw "managed static callable bridge requires an authored entry";
	};
	final direct = CppManagedStaticTarget.abi(target);
	final callable = new CppManagedClosureAbi(direct.signature);
	final symbol = CppManagedStaticTarget.sourceSymbol(target);
	final entry = symbol + "_callable";
	final args = ["hxhx_heap"];
	final ingress = new Array<String>();
	if (direct.result == RootedResult)
		args.push("hxhx_result");
	for (parameter in direct.getParameters()) {
		final value = "hxhx_arg" + parameter.slot;
		if (parameter.storage == DirectParameter && callable.getParameters()[parameter.slot].storage == RootedParameter) {
			final root = "hxhx_bridge_arg" + parameter.slot;
			ingress.push("  hxhx::managed::Root<hxhx::managed::Value> " + root + "(hxhx_heap, " + value + ");");
			for (line in CppManagedValueTransfer.convertRoot(parameter.type, TyType.nullable(parameter.type), root, "  "))
				ingress.push(line);
			args.push(CppManagedLeaf.read(parameter.type, root + ".get()"));
		} else {
			args.push(value);
		}
	}
	final invocation = symbol + "(" + args.join(", ") + ")";
	final lines = [
		"inline " + CppManagedEntrySignature.render(callable, entry) + " {",
		"  (void)hxhx_environment;"
	];
	for (line in ingress)
		lines.push(line);
	switch direct.result {
		case NoResult | RootedResult:
			lines.push("  " + invocation + ";");
		case DirectResult:
			lines.push(callable.result == RootedResult ? "  hxhx_result.set("
				+ CppManagedLeaf.box(direct.signature.getFunctionReturn(), invocation)
				+ ");" : "  return "
				+ invocation
				+ ";");
	}
	lines.push("}");
	final cell = "hxhx_heap.requireStatic<" + storage.nativeName + ">()->" + storage.callableMember(selected);
	final payload = "hxhx::managed::CallablePayload<" + callable.nativeSignature() + ">";
	lines.push("inline hxhx::managed::Value " + symbol + "_value(hxhx::managed::Heap& hxhx_heap) {");
	lines.push("  if (" + cell + ".assigned()) return " + cell + ".read();");
	lines.push("  hxhx::managed::Root<hxhx::managed::Ref<" + payload + ">> value(hxhx_heap);");
	lines.push("  hxhx_heap.allocateInto(value, &" + entry + ", hxhx::managed::ErasedRef{});");
	lines.push("  const auto result = hxhx::managed::Value::managed(value.get());");
	lines.push("  " + cell + ".write(result);");
	lines.push("  return result;\n}");
	return lines.join("\n");
}
