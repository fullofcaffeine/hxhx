package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/**
	Select the standard predicate by its complete typed declaration identity.

	Aliases retain this identity; same-spelled user methods do not. Both call
	emission and executable reachability use this decision, because the native
	predicate replaces the selected provider body while preserving its arguments.
**/
function ownsPredicate(selected:Null<NekoProjectedFunction>):Bool {
	return selected != null
		&& selected.body.getStableIdentity() == "Std#static:isOfType(required:dynamic,required:dynamic)->primitive:Bool#0";
}

/** Runtime representations supported by this target's class-object registry. */
private enum abstract RegistryKind(String) {
	var NominalClass = "class";
	var NominalInterface = "interface";
	var NativeArray = "array";
	var NativeString = "string";
}

private typedef RegistryEntry = {
	final identity:String;
	final name:String;
	final kind:RegistryKind;
	final assignable:Array<String>;
}

/** Null denotes an extern interface with no Neko runtime type object; other targets require an exact registry entry. */
function requireTarget(program:NekoTypedProgramProjection, target:TypedRuntimeTypeTarget):Null<String> {
	switch (target.getKind()) {
		case ArrayCore:
			return "core:Array";
		case StringCore:
			return "core:String";
		case IntCore | FloatCore | BoolCore:
			throw "Neko primitive runtime predicate is not implemented: " + target.getSemanticKey();
		case Nominal(_):
	}
	final identity = target.requireDeclarationIdentity().getCanonicalName();
	if (identity == "Array" || identity == "String")
		throw "Neko core runtime target cannot use a nominal representation: " + identity;
	final owner = program.requireClass(identity);
	if (owner.requireSemanticFacts().getIsExtern() && owner.requireSemanticFacts().getIsInterface())
		return null;
	if (!owner.requireSemanticFacts().getNominalKind().match(ClassInstance))
		throw "Neko runtime type target is not an admitted class or interface: " + identity;
	program.classGraph.requireAssignableTypes(identity, hasRuntimeMembership);
	return "nominal:" + identity;
}

/** Extern interfaces constrain typing but have no generated Neko membership object. */
function hasRuntimeMembership(facts:TypedBackendClassSemanticFacts):Bool {
	return !(facts.getIsExtern() && facts.getIsInterface());
}

/**
	Create the registry once on the shared symbol object, before any chunk loads.

	Haxe owns nominal membership and public names. The runtime receives complete
	ancestor lists and interns one object per identity. Enum and abstract values
	are excluded. Array and String use the same core objects for class literals,
	reflection, and predicates.
**/
function renderDefinition(out:Array<String>, program:NekoTypedProgramProjection, modules:Array<TypedBackendModuleProjection>, symbols:String):Void {
	final entries:Array<RegistryEntry> = [
		{
			identity: "core:Array",
			name: "Array",
			kind: NativeArray,
			assignable: []
		},
		{
			identity: "core:String",
			name: "String",
			kind: NativeString,
			assignable: []
		}
	];
	for (module in modules) {
		final pack = HxModuleDecl.getPackagePath(module.getDeclaration());
		for (owner in module.getClasses()) {
			final facts = owner.requireSemanticFacts();
			if (!facts.getNominalKind().match(ClassInstance))
				continue;
			if (facts.getIsExtern() && facts.getIsInterface())
				continue;
			// Core providers share the explicitly admitted native objects above.
			if (facts.getClassIdentity() == "Array" || facts.getClassIdentity() == "String")
				continue;
			final name = HxClassDecl.getName(owner.getDeclaration());
			entries.push({
				identity: "nominal:" + facts.getClassIdentity(),
				name: pack == null || pack.length == 0 ? name : pack + "." + name,
				kind: facts.getIsInterface() ? NominalInterface : NominalClass,
				assignable: [
					for (node in program.classGraph.requireAssignableTypes(facts.getClassIdentity(), hasRuntimeMembership))
						"nominal:" + node.classIdentity
				]
			});
		}
	}
	entries.sort((left, right) -> left.identity < right.identity ? -1 : left.identity == right.identity ? 0 : 1);
	out.push(symbols + ".__hxhx_types = $new(null);");
	for (entry in entries) {
		final object = "$objget(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(entry.identity) + "))";
		out.push("$objset(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(entry.identity) + "), $new(null));");
		out.push(object + ".identity = " + haxe.Json.stringify(entry.identity) + ";");
		out.push(object + ".name = " + haxe.Json.stringify(entry.name) + ";");
		out.push(object + ".kind = " + haxe.Json.stringify(entry.kind) + ";");
	}
	for (entry in entries) {
		final values = [
			for (identity in entry.assignable)
				"$objget(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(identity) + "))"
		];
		out.push("$objget("
			+ symbols
			+ ".__hxhx_types, $hash("
			+ haxe.Json.stringify(entry.identity)
			+ ")).assignable = $array("
			+ values.join(", ")
			+ ");");
	}
}

/** Bind each chunk to the same registry; never create type objects in a chunk. */
function renderPrelude(out:Array<String>, symbols:String, program:NekoTypedProgramProjection):Void {
	final typeValue = program.runtimeHelperName("__hxhx_runtime_type");
	final getClass = program.runtimeHelperName("__hxhx_type_get_class");
	final className = program.runtimeHelperName("__hxhx_type_class_name");
	final isOfType = program.runtimeHelperName("__hxhx_is_of_type");
	out.push("var __hxhx_types = " + symbols + ".__hxhx_types;");
	out.push("var " + typeValue + " = function(identity) {");
	out.push("  var value = $objget(__hxhx_types, $hash(identity));");
	out.push("  if (value == null) $throw(\"unknown runtime type\");");
	out.push("  return value;");
	out.push("}");
	out.push("var __hxhx_is_type_object = function(value) {");
	out.push("  if (value == null || $typeof(value) != $tobject) return false;");
	out.push("  var identity = $objget(value, $hash(\"identity\"));");
	out.push("  return identity != null && $typeof(identity) == $tstring && $objget(__hxhx_types, $hash(identity)) == value;");
	out.push("}");
	out.push("var " + className + " = function(value) {");
	out.push("  return if (__hxhx_is_type_object(value)) value.name else null;");
	out.push("}");
	out.push("var " + getClass + " = function(value) {");
	out.push("  if ($typeof(value) == $tarray) return " + typeValue + "(\"core:Array\");");
	out.push("  if ($typeof(value) == $tstring) return " + typeValue + "(\"core:String\");");
	out.push("  if (value == null || $typeof(value) != $tobject) return null;");
	out.push("  var selected = $objget(value, $hash(" + haxe.Json.stringify(typeValue) + "));");
	out.push("  return if (__hxhx_is_type_object(selected) && selected.kind == \"class\") selected else null;");
	out.push("}");
	out.push("var " + isOfType + " = function(value, target) {");
	out.push("  if (__hxhx_is_type_object(target) == false) return false;");
	out.push("  if (target.kind == \"array\") return $typeof(value) == $tarray;");
	out.push("  if (target.kind == \"string\") return $typeof(value) == $tstring;");
	out.push("  var actual = " + getClass + "(value);");
	out.push("  if (actual == null || actual.kind != \"class\") return false;");
	out.push("  var parents = actual.assignable;");
	out.push("  var i = 0;");
	out.push("  while (i < $asize(parents)) { if (parents[i] == target) return true; i = i + 1; }");
	out.push("  return false;");
	out.push("}");
}
