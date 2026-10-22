package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/** The selected provider reference and a temporary that cannot shadow authored names. */
typedef NekoArrayFactory = {
	final reference:String;
	final storage:String;
}

/** Bind allocation to this program's exact provider and reserved local namespace. */
function boundFactory(context:NekoEmitContext):NekoArrayFactory {
	return {
		reference: @:privateAccess NekoTargetCore.renderStaticFunctionValue(context, factory(context.typedProgram)),
		storage: context.typedProgram.runtimeHelperName("__hxhx_array_values")
	};
}

/**
	Evaluate elements once in source order before wrapping their fresh storage.
	Neko's $array builtin evaluates operands in reverse order; indexed writes keep
	the Haxe order without allocating a helper closure around each literal.
 */
function fromValues(factory:Null<NekoArrayFactory>, values:Array<String>):String {
	if (factory == null)
		throw "Neko public arrays require the authored Array.new1 provider";
	if (values.length == 0)
		return factory.reference + "($array(), 0)";
	final storage = factory.storage;
	final parts = ["({ var " + storage + " = $amake(" + values.length + ");"];
	for (index in 0...values.length)
		parts.push(storage + "[" + index + "] = " + values[index] + ";");
	parts.push(factory.reference + "(" + storage + ", " + values.length + "); })");
	return parts.join(" ");
}

/** Exact core String methods producing arrays retain the ordinary Array provider. */
function methodReturnsArray(declaration:TyDeclarationInfo):Bool {
	return declaration.getOwner().getCanonicalName() == "String"
		&& !declaration.getIsStatic()
		&& declaration.getSignature().getName() == "split";
}

/** Native API implementations returning public arrays retain the same provider factory as literals. */
function wrapsNativeResult(owner:String, name:String):Bool {
	return switch [owner, name] {
		case ["Type", "getInstanceFields" | "getClassFields"] | ["Reflect", "fields"] | ["Sys", "args"]: true;
		case _: false;
	};
}

/**
	Public API results own their backing storage. Evaluate the native source once
	and copy it before calling the authored factory, so writes cannot change cached
	type metadata or the VM argument list seen by a later call.
 */
function fromNative(context:NekoEmitContext, native:String):String {
	final storage = context.typedProgram.runtimeHelperName("__hxhx_array_storage");
	final selected = factory(context.typedProgram);
	final reference = @:privateAccess NekoTargetCore.renderStaticFunctionValue(context, selected);
	return "({ var "
		+ storage
		+ " = "
		+ native
		+ "; "
		+ reference
		+ "($asub("
		+ storage
		+ ", 0, $asize("
		+ storage
		+ ")), $asize("
		+ storage
		+ ")); })";
}

/** Patterns inspect the logical container, never its spare backing capacity or a replaced public type binding. */
function matchesLength(program:NekoTypedProgramProjection, value:String, length:Int):String {
	return program.runtimeHelperName("__hxhx_type_get_class")
		+ "("
		+ value
		+ ") == "
		+ program.runtimeHelperName("__hxhx_runtime_type_definition")
		+ "(\"core:Array\") && "
		+ value
		+ ".length == "
		+ length;
}

/**
	Select the authored Array factory for a literal's fixed-size backing storage.
	The standard Neko provider owns resizing, indexing, and instance methods.
	Both reachability and emission use this exact declaration, so an array literal
	retains the same ordinary class implementation as an explicit constructor.
 */
function factory(program:NekoTypedProgramProjection):NekoProjectedFunction {
	final owner = program.requireClass("Array");
	for (body in owner.getFunctions()) {
		final signature = body.requireSemanticDeclaration().getSignature();
		if (signature.getName() != "new1" || !signature.getIsStatic())
			continue;
		final arguments = signature.getArgs();
		final result = signature.getReturnType();
		if (arguments.length != 2
			|| arguments[0].getNominalIdentity() == null
			|| arguments[0].getNominalIdentity().getCanonicalName() != "neko.NativeArray"
			|| arguments[1].getSemanticKey() != "primitive:Int"
			|| result.getNominalIdentity() == null
			|| result.getNominalIdentity().getCanonicalName() != "Array"
			|| !signature.acceptsArity(2)
			|| signature.acceptsArity(1)
			|| signature.acceptsArity(3))
			throw "Neko Array.new1 requires native backing storage and an explicit logical length";
		final inputTypes = arguments[0].getTypeArguments();
		final outputTypes = result.getTypeArguments();
		if (inputTypes.length != 1 || outputTypes.length != 1 || inputTypes[0].getSemanticKey() != outputTypes[0].getSemanticKey())
			throw "Neko Array.new1 must preserve its backing storage element type";
		return program.requireDeclaredFunction(body.getDeclaration());
	}
	throw "Neko array literals require the authored Array.new1 provider";
}
