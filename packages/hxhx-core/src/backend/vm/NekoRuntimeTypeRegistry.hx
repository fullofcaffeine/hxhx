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

/** A class value can become a constructor binding; retain its exact factory with the descriptor. */
function constructorOwner(program:NekoTypedProgramProjection, target:TypedRuntimeTypeTarget):Null<TypedBackendClassProjection> {
	return switch target.getKind() {
		case Nominal(identity): final owner = program.requireClass(identity.getCanonicalName()); final facts = owner.requireSemanticFacts(); facts.getNominalKind()
				.match(ClassInstance) && !facts.getIsInterface() && !facts.getIsExtern() ? owner : null;
		case _: null;
	};
}

/** Runtime representations supported by this target's class-object registry. */
private enum abstract RegistryKind(String) {
	var NominalClass = "class";
	var NominalInterface = "interface";
	var NativeArray = "array";
	var NativeString = "string";
	var NativeInt = "int";
	var NativeFloat = "float";
	var NativeBool = "bool";
	var NativeDynamic = "dynamic";
	var NativeClassMeta = "class-meta";
	var NativeEnumMeta = "enum-meta";
	var NominalEnum = "enum";
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
		case IntCore:
			return "core:Int";
		case FloatCore:
			return "core:Float";
		case BoolCore:
			return "core:Bool";
		case DynamicCore:
			return "core:Dynamic";
		case ClassCore:
			return "core:Class";
		case EnumCore:
			return "core:Enum";
		case EnumDeclaration(identity):
			final owner = program.requireClass(identity.getCanonicalName());
			if (!owner.requireSemanticFacts().getNominalKind().match(EnumValue))
				throw "Neko enum descriptor requires its exact enum declaration";
			return "enum:" + identity.getCanonicalName();
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

/** Constructor factories and instances use the same descriptor as their exact core provider. */
function classDescriptorIdentity(program:NekoTypedProgramProjection, declaration:HxClassDecl):String {
	final identity = program.requireClassIdentity(declaration);
	if (!program.requireClass(identity).requireSemanticFacts().getNominalKind().match(ClassInstance))
		throw "Neko class descriptor requires a class representation: " + identity;
	return switch identity {
		case "Array" | "String": "core:" + identity;
		case _: "nominal:" + identity;
	};
}

/** Extern interfaces constrain typing but have no generated Neko membership object. */
function hasRuntimeMembership(facts:TypedBackendClassSemanticFacts):Bool {
	return !(facts.getIsExtern() && facts.getIsInterface());
}

/**
	Create the registry once on the shared symbol object, before any chunk loads.

	Haxe owns nominal membership and public names. The runtime receives complete
	ancestor lists and retains one original descriptor per identity. Separate
	cells hold source-visible bindings, so writes cannot alter the class metadata
	already attached to instances. The primitive abstract
	targets and runtime meta categories have explicit native kinds. Ordinary
	enum descriptors retain their exact declaration identities. Every chunk
	shares the descriptors and binding cells.
**/
function renderDefinition(out:Array<String>, program:NekoTypedProgramProjection, modules:Array<TypedBackendModuleProjection>, symbols:String):Void {
	final entries:Array<RegistryEntry> = [
		{
			identity: "core:Dynamic",
			name: "Dynamic",
			kind: NativeDynamic,
			assignable: []
		},
		{
			identity: "core:Class",
			name: "Class",
			kind: NativeClassMeta,
			assignable: []
		},
		{
			identity: "core:Enum",
			name: "Enum",
			kind: NativeEnumMeta,
			assignable: []
		},
		{
			identity: "core:Int",
			name: "Int",
			kind: NativeInt,
			assignable: []
		},
		{
			identity: "core:Float",
			name: "Float",
			kind: NativeFloat,
			assignable: []
		},
		{
			identity: "core:Bool",
			name: "Bool",
			kind: NativeBool,
			assignable: []
		},
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
			if (facts.getNominalKind().match(EnumValue)) {
				final name = HxClassDecl.getName(owner.getDeclaration());
				entries.push({
					identity: "enum:" + facts.getClassIdentity(),
					name: pack == null || pack.length == 0 ? name : pack + "." + name,
					kind: NominalEnum,
					assignable: []
				});
				continue;
			}
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
	out.push(symbols + ".__hxhx_type_cells = $new(null);");
	for (entry in entries) {
		final object = "$objget(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(entry.identity) + "))";
		out.push("$objset(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(entry.identity) + "), $new(null));");
		out.push(object + ".identity = " + haxe.Json.stringify(entry.identity) + ";");
		out.push(object + ".name = " + haxe.Json.stringify(entry.name) + ";");
		out.push(object + ".kind = " + haxe.Json.stringify(entry.kind) + ";");
		// Array and String have authored class bodies despite their distinct runtime type categories.
		if (entry.kind == NominalClass || entry.kind == NativeArray || entry.kind == NativeString) {
			out.push(object + ".prototype = $new(null);");
			out.push(object + ".prototype.__class__ = " + object + ";");
		}
		// Neko's public meta-category predicates test metadata presence, not its spelling.
		final metadata = switch entry.kind {
			case NativeEnumMeta: null;
			case NominalEnum | NativeBool: "__ename__";
			case _: "__name__";
		};
		if (metadata != null)
			out.push(object
				+ "."
				+ metadata
				+ " = $array("
				+ [for (part in entry.name.split(".")) haxe.Json.stringify(part)].join(", ") + ");");
		out.push("$objset("
			+ symbols
			+ ".__hxhx_type_cells, $hash("
			+ haxe.Json.stringify(entry.identity)
			+ "), $array("
			+ object
			+ "));");
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
	NekoNamedTypeRegistry.render(out, [for (entry in entries) {identity: entry.identity, name: entry.name}], symbols,
		program.runtimeHelperName("__hxhx_named_types"));
}

/** Bind each chunk to the same registry; never create type objects in a chunk. */
function renderPrelude(out:Array<String>, symbols:String, program:NekoTypedProgramProjection):Void {
	final typeValue = program.runtimeHelperName("__hxhx_runtime_type");
	final typeCell = program.runtimeHelperName("__hxhx_runtime_type_cell");
	final typeDefinition = program.runtimeHelperName("__hxhx_runtime_type_definition");
	final getClass = program.runtimeHelperName("__hxhx_type_get_class");
	final className = program.runtimeHelperName("__hxhx_type_class_name");
	final isOfType = program.runtimeHelperName("__hxhx_is_of_type");
	out.push("var __hxhx_types = " + symbols + ".__hxhx_types;");
	out.push("var " + typeDefinition + " = function(identity) {");
	out.push("  var value = $objget(__hxhx_types, $hash(identity));");
	out.push("  if (value == null) $throw(\"unknown runtime type\");");
	out.push("  return value;");
	out.push("}");
	out.push("var " + typeCell + " = function(identity) {");
	out.push("  var cell = $objget(" + symbols + ".__hxhx_type_cells, $hash(identity));");
	out.push("  if (cell == null) $throw(\"unknown runtime type binding\");");
	out.push("  return cell;");
	out.push("}");
	out.push("var " + typeValue + " = function(identity) { return " + typeCell + "(identity)[0]; }");
	out.push("var __hxhx_is_type_object = function(value) {");
	out.push("  if (value == null || $typeof(value) != $tobject) return false;");
	out.push("  var identity = $objget(value, $hash(\"identity\"));");
	out.push("  return identity != null && $typeof(identity) == $tstring && $objget(__hxhx_types, $hash(identity)) == value;");
	out.push("}");
	out.push("var " + className + " = function(value) {");
	out.push("  return if (__hxhx_is_type_object(value) && $objget(value, $hash(\"__name__\")) != null) value.name else null;");
	out.push("}");
	out.push("var " + getClass + " = function(value) {");
	out.push("  if ($typeof(value) == $tarray) return " + typeDefinition + "(\"core:Array\");");
	out.push("  if ($typeof(value) == $tstring) return " + typeDefinition + "(\"core:String\");");
	out.push("  if (value == null || $typeof(value) != $tobject) return null;");
	out.push("  var selected = $objget(value, $hash(" + haxe.Json.stringify(typeValue) + "));");
	out.push("  return if (__hxhx_is_type_object(selected) && selected.kind == \"class\") selected else null;");
	out.push("}");
	out.push("var " + isOfType + " = function(value, target) {");
	out.push("  if (value == null) return false;");
	out.push("  if (target == " + typeValue + "(\"core:Dynamic\")) return true;");
	out.push("  if (target == " + typeValue + "(\"core:Class\")) return $typeof(value) == $tobject && $objget(value, $hash(\"__name__\")) != null;");
	out.push("  if (target == " + typeValue + "(\"core:Enum\")) return $typeof(value) == $tobject && $objget(value, $hash(\"__ename__\")) != null;");
	// Explicit untyped writes can replace a core binding with any runtime value.
	// Compare the current binding without changing the native numeric predicates.
	out.push("  if ($typeof(value) == $tarray) return target == " + typeValue + "(\"core:Array\");");
	out.push("  if ($typeof(value) == $tstring) return target == " + typeValue + "(\"core:String\");");
	out.push("  if ($typeof(value) == $tint) return target == "
		+ typeValue
		+ "(\"core:Int\") || target == "
		+ typeValue
		+ "(\"core:Float\");");
	out.push("  if ($typeof(value) == $tfloat) return target == " + typeValue + "(\"core:Float\") || (target == " + typeValue
		+ "(\"core:Int\") && $int(value) == value);");
	out.push("  if ($typeof(value) == $tbool) return target == " + typeValue + "(\"core:Bool\");");
	out.push("  if ($typeof(value) == $tobject) {");
	out.push("    var owner = $objget(value, $hash(\"__enum__\"));");
	out.push("    if (owner != null && owner == target) return true;");
	out.push("  }");
	out.push("  if (__hxhx_is_type_object(target) == false) return false;");
	out.push("  var actual = " + getClass + "(value);");
	out.push("  if (actual == null || actual.kind != \"class\") return false;");
	out.push("  var parents = actual.assignable;");
	out.push("  var i = 0;");
	out.push("  while (i < $asize(parents)) { if (parents[i] == target) return true; i = i + 1; }");
	out.push("  return false;");
	out.push("}");
	NekoEnumRuntimeType.renderPrelude(out, program);
}
