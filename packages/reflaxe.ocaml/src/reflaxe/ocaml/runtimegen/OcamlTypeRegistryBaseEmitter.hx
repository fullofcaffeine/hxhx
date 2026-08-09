package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText.OcamlCheckedGeneratedTextRecord;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

private enum OcamlTypeRegistryTemplateToken {
	RuntimeUse(id:String, exactSymbol:String);
	ProgramIdentifier(id:String, exactIdentifier:String);
}

/** One enum constructor's stable runtime representation metadata. */
typedef OcamlTypeRegistryEnumLayout = {
	final enumName:String;
	final constructorName:String;
	final haxeIndex:Int;
	final ocamlTag:Int;
	final carriesPayload:Bool;
}

/** One class function used by `Type.createEmptyInstance`. */
typedef OcamlTypeRegistryEmptyConstructor = {
	final className:String;
	final moduleName:String;
	final targetFunctionName:String;
}

/** The sorted instance and static field names visible through Haxe reflection. */
typedef OcamlTypeRegistryClassFields = {
	final className:String;
	final instanceFields:Array<String>;
	final staticFields:Array<String>;
}

/** One direct superclass relationship used by `Type.getSuperClass`. */
typedef OcamlTypeRegistryClassSuper = {
	final className:String;
	final superName:String;
}

/** The sorted runtime type tags used by typed exception catches. */
typedef OcamlTypeRegistryClassTags = {
	final className:String;
	final tags:Array<String>;
}

/** One exact program-owned identifier that may appear in generated registry code. */
typedef OcamlTypeRegistryProgramIdentifier = {
	final id:String;
	final exactIdentifier:String;
}

/** The generated-file section where one planned runtime use must appear. */
enum OcamlTypeRegistryRuntimeUseSection {
	ReflectionConstructor;
	DynamicStringifier;
}

/** One planned runtime call, its exact section, and the capability that explains it. */
typedef OcamlTypeRegistryRuntimeUse = {
	final id:String;
	final exactSymbol:String;
	final capability:String;
	final section:OcamlTypeRegistryRuntimeUseSection;
}

/**
	Emits the checked base metadata in `HxTypeRegistry.ml`.

	For example, `{className: "demo.Foo", superName: "demo.Base"}` becomes
	`HxType.register_class_super "demo.Foo" (HxType.class_ "demo.Base")`.
	Each private `HxType` identifier is created from a planned runtime-use record,
	so a plain string cannot silently add, remove, or reorder these calls.

	Reflection constructor adapters and Dynamic stringifier registrations use the
	same checked occurrence model in their final emitted sections. Program-owned
	module and method names use a separate exact whitelist, so a user type whose
	OCaml name begins with `Hx` is not mistaken for a runtime module.
**/
class OcamlTypeRegistryBaseEmitter {
	public static inline final OWNER_ID = "compiler-generated:HxTypeRegistry";
	static inline final SOURCE_FILE = "compiler-generated/HxTypeRegistry.ml";

	public final planRevision:String;

	final checked:OcamlCheckedGeneratedText;
	final useLineDirectives:Bool;
	final classNames:Array<String>;
	final enumNames:Array<String>;
	final enumLayouts:Array<OcamlTypeRegistryEnumLayout>;
	final emptyConstructors:Array<OcamlTypeRegistryEmptyConstructor>;
	final classFields:Array<OcamlTypeRegistryClassFields>;
	final classSupers:Array<OcamlTypeRegistryClassSuper>;
	final classTags:Array<OcamlTypeRegistryClassTags>;
	final programIdentifiersById:Map<String, String> = [];
	final consumedProgramIdentifiers:Map<String, Bool> = [];
	final runtimeUsesById:Map<String, OcamlTypeRegistryRuntimeUse> = [];
	final templateTokens:Map<String, OcamlTypeRegistryTemplateToken> = [];
	var nextTemplateToken:Int = 0;
	var phase:Int = 0;

	public function new(activeProfile:String, programRevision:String, useLineDirectives:Bool, classNames:Array<String>, enumNames:Array<String>,
			enumLayouts:Array<OcamlTypeRegistryEnumLayout>, emptyConstructors:Array<OcamlTypeRegistryEmptyConstructor>,
			classFields:Array<OcamlTypeRegistryClassFields>, classSupers:Array<OcamlTypeRegistryClassSuper>, classTags:Array<OcamlTypeRegistryClassTags>,
			programIdentifiers:Array<OcamlTypeRegistryProgramIdentifier>, runtimeUses:Array<OcamlTypeRegistryRuntimeUse>) {
		this.useLineDirectives = useLineDirectives;
		this.classNames = copyStrings(classNames);
		this.enumNames = copyStrings(enumNames);
		this.enumLayouts = enumLayouts == null ? [] : enumLayouts.map(layout -> {
			enumName: layout.enumName,
			constructorName: layout.constructorName,
			haxeIndex: layout.haxeIndex,
			ocamlTag: layout.ocamlTag,
			carriesPayload: layout.carriesPayload
		});
		this.emptyConstructors = emptyConstructors == null ? [] : emptyConstructors.map(constructor -> {
			className: constructor.className,
			moduleName: constructor.moduleName,
			targetFunctionName: constructor.targetFunctionName
		});
		this.classFields = classFields == null ? [] : classFields.map(fields -> {
			className: fields.className,
			instanceFields: copyStrings(fields.instanceFields),
			staticFields: copyStrings(fields.staticFields)
		});
		this.classSupers = classSupers == null ? [] : classSupers.map(superclass -> {
			className: superclass.className,
			superName: superclass.superName
		});
		this.classTags = classTags == null ? [] : classTags.map(entry -> {
			className: entry.className,
			tags: copyStrings(entry.tags)
		});
		final plannedProgramIdentifiers = programIdentifiers == null ? [] : programIdentifiers;
		for (entry in plannedProgramIdentifiers) {
			if (programIdentifiersById.exists(entry.id))
				throw 'HxTypeRegistry repeats planned program identifier ${entry.id}.';
			programIdentifiersById.set(entry.id, entry.exactIdentifier);
		}
		final plannedRuntimeUses:Array<OcamlTypeRegistryRuntimeUse> = runtimeUses == null ? [] : runtimeUses.map(use -> ({
			id: use.id,
			exactSymbol: use.exactSymbol,
			capability: use.capability,
			section: use.section
		} : OcamlTypeRegistryRuntimeUse));
		for (use in plannedRuntimeUses) {
			if (runtimeUsesById.exists(use.id))
				throw 'HxTypeRegistry repeats planned runtime use ${use.id}.';
			runtimeUsesById.set(use.id, use);
		}

		final revisionInputs = [programRevision, activeProfile, Std.string(useLineDirectives)];
		for (name in this.classNames)
			revisionInputs.push("class:" + name);
		for (name in this.enumNames)
			revisionInputs.push("enum:" + name);
		for (layout in this.enumLayouts)
			revisionInputs.push("layout:" + [
				layout.enumName,
				layout.constructorName,
				Std.string(layout.haxeIndex),
				Std.string(layout.ocamlTag),
				Std.string(layout.carriesPayload)
			].join(":"));
		for (constructor in this.emptyConstructors)
			revisionInputs.push("empty:" + [constructor.className, constructor.moduleName, constructor.targetFunctionName].join(":"));
		for (fields in this.classFields)
			revisionInputs.push("fields:" + [fields.className, fields.instanceFields.join(","), fields.staticFields.join(",")].join(":"));
		for (superclass in this.classSupers)
			revisionInputs.push("super:" + superclass.className + ":" + superclass.superName);
		for (entry in this.classTags)
			revisionInputs.push("tags:" + entry.className + ":" + entry.tags.join(","));
		for (entry in plannedProgramIdentifiers)
			revisionInputs.push("program-identifier:" + entry.id + ":" + entry.exactIdentifier);
		for (use in plannedRuntimeUses)
			revisionInputs.push("runtime-use:" + [Std.string(use.section), use.id, use.exactSymbol, use.capability].join(":"));

		planRevision = OcamlCheckedGeneratedText.revision(OWNER_ID, revisionInputs);
		final requirements:Array<OcamlRuntimeRequirement> = [];
		final requirementsByCapability:Map<String, OcamlRuntimeRequirement> = [];
		function requireCapability(capability:String):Void {
			if (requirementsByCapability.exists(capability))
				return;
			final requirement = OcamlRuntimeRequirementLedger.requirementForCompilerInfrastructure(capability);
			requirementsByCapability.set(capability, requirement);
			requirements.push(requirement);
		}
		requireCapability(OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		for (use in plannedRuntimeUses)
			requireCapability(use.capability);
		checked = new OcamlCheckedGeneratedText(OWNER_ID, planRevision, activeProfile, requirements,
			plannedOccurrences(requirementsByCapability, plannedRuntimeUses));
	}

	/** Starts the exact generated module and its `init` function. */
	public function emitHeader():Void {
		requirePhase(0, "header");
		if (useLineDirectives)
			checked.addLiteral("# 1 \"HxTypeRegistry.ml\"\n");
		checked.addLiteral("(* Generated by reflaxe.ocaml (WIP) *)\n");
		checked.addLiteral("(* Type registry used by `Type.resolveClass/resolveEnum`, `Type.get*Fields`, `Type.createInstance`, and typed catches. *)\n\n");
		checked.addLiteral("let init () : unit =\n");
		phase = 1;
	}

	/** Emits runtime identities for every class and enum in their supplied order. */
	public function emitClassAndEnumIdentities():Void {
		requirePhase(1, "class and enum identities");
		for (index in 0...classNames.length) {
			checked.addLiteral("  ignore (");
			addBaseRuntimeUse("class-identity", index, "HxType.class_");
			checked.addLiteral(" " + ocamlStringLiteral(classNames[index]) + ");\n");
		}
		for (index in 0...enumNames.length) {
			checked.addLiteral("  ignore (");
			addBaseRuntimeUse("enum-identity", index, "HxType.enum_");
			checked.addLiteral(" " + ocamlStringLiteral(enumNames[index]) + ");\n");
		}
		phase = 2;
	}

	/** Emits the Haxe-index to OCaml-representation mapping for enum constructors. */
	public function emitEnumLayouts():Void {
		requirePhase(2, "enum layouts");
		for (index in 0...enumLayouts.length) {
			final layout = enumLayouts[index];
			checked.addLiteral("  ");
			addBaseRuntimeUse("enum-layout", index, "HxType.register_enum_ctor_layout");
			checked.addLiteral(" " + ocamlStringLiteral(layout.enumName) + " " + ocamlStringLiteral(layout.constructorName) + " "
				+ Std.string(layout.haxeIndex) + " (");
			addBaseRuntimeUse("enum-representation", index, layout.carriesPayload ? "HxType.EnumBlock" : "HxType.EnumImmediate");
			checked.addLiteral(" " + Std.string(layout.ocamlTag) + ");\n");
		}
		phase = 3;
	}

	/**
		Adds ordinary OCaml syntax between checked placeholders.

		The complete-file scanner still rejects any private `Hx...` name placed in
		this text. Every private runtime name must instead use `runtimeToken`, which
		binds the exact identifier to the pre-emission plan and requirement.
	**/
	public function addLiteral(value:String):Void {
		requireTemplatePhase();
		checked.addLiteral(value);
	}

	/** Creates one token from a runtime use planned before emission began. */
	public function runtimeToken(id:String, exactSymbol:String):String {
		requireTemplatePhase();
		validateRuntimeUse(id, exactSymbol);
		final token = "ReflaxeTypeRegistryTemplateToken" + Std.string(nextTemplateToken++);
		templateTokens.set(token, RuntimeUse(id, exactSymbol));
		return token;
	}

	/** Creates a token only when its stable role and exact program identifier were planned at construction. */
	public function programIdentifierToken(id:String, exactIdentifier:String):String {
		requireTemplatePhase();
		validateProgramIdentifier(id, exactIdentifier);
		final token = "ReflaxeTypeRegistryTemplateToken" + Std.string(nextTemplateToken++);
		templateTokens.set(token, ProgramIdentifier(id, exactIdentifier));
		return token;
	}

	/** Replaces temporary runtime and program-identifier tokens in exact text order. */
	public function addTemplate(value:String):Void {
		requireTemplatePhase();
		if (value == null)
			throw "HxTypeRegistry cannot add a null generated template.";
		var rest = value;
		while (true) {
			var nextToken:Null<String> = null;
			var nextIndex = rest.length;
			for (token => _ in templateTokens) {
				final index = rest.indexOf(token);
				if (index >= 0 && index < nextIndex) {
					nextToken = token;
					nextIndex = index;
				}
			}
			if (nextToken == null)
				break;
			final planned = templateTokens.get(nextToken);
			if (planned == null)
				throw 'HxTypeRegistry lost template token $nextToken.';
			if (rest.indexOf(nextToken, nextIndex + nextToken.length) >= 0)
				throw 'HxTypeRegistry template token $nextToken appears more than once in one template.';
			checked.addLiteral(rest.substring(0, nextIndex));
			switch (planned) {
				case RuntimeUse(id, exactSymbol):
					checked.addRuntimeUse(id, planRevision, exactSymbol);
				case ProgramIdentifier(id, exactIdentifier):
					addProgramIdentifier(id, exactIdentifier);
			}
			templateTokens.remove(nextToken);
			rest = rest.substr(nextIndex + nextToken.length);
		}
		checked.addLiteral(rest);
	}

	/** Emits the no-argument allocation functions used by `Type.createEmptyInstance`. */
	public function emitEmptyConstructors():Void {
		requirePhase(3, "empty constructors");
		requireNoPendingTemplateTokens("empty constructors");
		for (index in 0...emptyConstructors.length) {
			final constructor = emptyConstructors[index];
			checked.addLiteral("  ");
			addBaseRuntimeUse("empty-constructor", index, "HxType.register_class_empty_ctor");
			checked.addLiteral(" " + ocamlStringLiteral(constructor.className) + " (fun () -> Obj.repr (");
			addProgramIdentifier("program:empty-constructor-module:" + Std.string(index), constructor.moduleName);
			checked.addLiteral(".");
			addProgramIdentifier("program:empty-constructor-function:" + Std.string(index), constructor.targetFunctionName);
			checked.addLiteral(" ()));\n");
		}
		phase = 4;
	}

	/** Emits the instance and static field names exposed by Haxe reflection. */
	public function emitClassFields():Void {
		requirePhase(4, "class fields");
		for (index in 0...classFields.length) {
			final fields = classFields[index];
			checked.addLiteral("  ");
			addBaseRuntimeUse("instance-fields", index, "HxType.register_class_instance_fields");
			checked.addLiteral(" " + ocamlStringLiteral(fields.className) + " " + ocamlStringListLiteral(fields.instanceFields) + ";\n  ");
			addBaseRuntimeUse("static-fields", index, "HxType.register_class_static_fields");
			checked.addLiteral(" " + ocamlStringLiteral(fields.className) + " " + ocamlStringListLiteral(fields.staticFields) + ";\n");
		}
		phase = 5;
	}

	/** Emits direct superclass links and the corresponding runtime class values. */
	public function emitClassSupers():Void {
		requirePhase(5, "class supers");
		requireNoPendingTemplateTokens("class supers");
		for (index in 0...classSupers.length) {
			final superclass = classSupers[index];
			checked.addLiteral("  ");
			addBaseRuntimeUse("class-super-register", index, "HxType.register_class_super");
			checked.addLiteral(" " + ocamlStringLiteral(superclass.className) + " (");
			addBaseRuntimeUse("class-super-value", index, "HxType.class_");
			checked.addLiteral(" " + ocamlStringLiteral(superclass.superName) + ");\n");
		}
		phase = 6;
	}

	/** Emits the runtime type-tag sets used by typed catches. */
	public function emitClassTags():Void {
		requirePhase(6, "class tags");
		for (index in 0...classTags.length) {
			final entry = classTags[index];
			checked.addLiteral("  ");
			addBaseRuntimeUse("class-tags", index, "HxType.register_class_tags");
			checked.addLiteral(" " + ocamlStringLiteral(entry.className) + " " + ocamlStringListLiteral(entry.tags) + ";\n");
		}
		phase = 7;
	}

	/** Closes the generated `init` function without publishing it. */
	public function emitFooter():Void {
		requirePhase(7, "footer");
		checked.addLiteral("  ()\n");
		phase = 8;
	}

	/** Seals and verifies the exact bytes after every required section was emitted. */
	public function seal():OcamlCheckedGeneratedTextRecord {
		requirePhase(8, "seal");
		for (id => _ in programIdentifiersById)
			if (!consumedProgramIdentifiers.exists(id))
				throw 'HxTypeRegistry did not consume planned program identifier $id.';
		phase = 9;
		return checked.seal();
	}

	function plannedOccurrences(requirementsByCapability:Map<String, OcamlRuntimeRequirement>,
			runtimeUses:Array<OcamlTypeRegistryRuntimeUse>):Array<OcamlRuntimeUseOccurrence> {
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
		function add(id:String, role:String, exactSymbol:String, capability:String):Void {
			final requirement = requirementsByCapability.get(capability);
			if (requirement == null)
				throw 'HxTypeRegistry runtime use $id has no requirement for capability $capability.';
			occurrences.push({
				id: id,
				planRevision: planRevision,
				ownerId: OWNER_ID,
				requirementId: requirement.id,
				domain: OcamlRuntimeUseDomain.GeneratedText,
				exactSymbol: exactSymbol,
				role: role,
				order: occurrences.length,
				source: {
					file: SOURCE_FILE,
					min: 0,
					max: 0
				},
				profileEligibility: requirement.profileEligibility.copy(),
				cardinality: 1
			});
		}
		function addSection(section:OcamlTypeRegistryRuntimeUseSection, role:String):Void {
			for (use in runtimeUses)
				if (use.section == section)
					add(use.id, role, use.exactSymbol, use.capability);
		}
		for (index in 0...classNames.length)
			add(runtimeUseId("class-identity", index), "class-identity", "HxType.class_", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		for (index in 0...enumNames.length)
			add(runtimeUseId("enum-identity", index), "enum-identity", "HxType.enum_", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		for (index in 0...enumLayouts.length) {
			add(runtimeUseId("enum-layout", index), "enum-layout", "HxType.register_enum_ctor_layout", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
			add(runtimeUseId("enum-representation", index), "enum-representation",
				enumLayouts[index].carriesPayload ? "HxType.EnumBlock" : "HxType.EnumImmediate", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		}
		addSection(OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor, "reflection-constructor");
		for (index in 0...emptyConstructors.length)
			add(runtimeUseId("empty-constructor", index), "empty-constructor", "HxType.register_class_empty_ctor", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		for (index in 0...classFields.length) {
			add(runtimeUseId("instance-fields", index), "instance-fields", "HxType.register_class_instance_fields",
				OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
			add(runtimeUseId("static-fields", index), "static-fields", "HxType.register_class_static_fields", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		}
		addSection(OcamlTypeRegistryRuntimeUseSection.DynamicStringifier, "dynamic-stringifier");
		for (index in 0...classSupers.length) {
			add(runtimeUseId("class-super-register", index), "class-super-register", "HxType.register_class_super",
				OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
			add(runtimeUseId("class-super-value", index), "class-super-value", "HxType.class_", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		}
		for (index in 0...classTags.length)
			add(runtimeUseId("class-tags", index), "class-tags", "HxType.register_class_tags", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		return occurrences;
	}

	function addBaseRuntimeUse(role:String, index:Int, exactSymbol:String):Void {
		checked.addRuntimeUse(runtimeUseId(role, index), planRevision, exactSymbol);
	}

	function addProgramIdentifier(id:String, exactIdentifier:String):Void {
		validateProgramIdentifier(id, exactIdentifier);
		if (consumedProgramIdentifiers.exists(id))
			throw 'HxTypeRegistry program identifier $id was constructed more than once.';
		consumedProgramIdentifiers.set(id, true);
		checked.addProgramIdentifier(id, exactIdentifier);
	}

	function validateProgramIdentifier(id:String, exactIdentifier:String):Void {
		final planned = programIdentifiersById.get(id);
		if (planned == null)
			throw 'HxTypeRegistry has no planned program identifier $id.';
		if (planned != exactIdentifier)
			throw 'HxTypeRegistry program identifier $id expected $planned, received $exactIdentifier.';
	}

	function validateRuntimeUse(id:String, exactSymbol:String):Void {
		final planned = runtimeUsesById.get(id);
		if (planned == null)
			throw 'HxTypeRegistry has no planned runtime use $id.';
		if (planned.exactSymbol != exactSymbol)
			throw 'HxTypeRegistry runtime use $id expected ${planned.exactSymbol}, received $exactSymbol.';
	}

	function requireTemplatePhase():Void {
		if (phase != 3 && phase != 5)
			throw 'HxTypeRegistry generated templates may appear only after enum layouts or class fields; current phase is $phase.';
	}

	function requireNoPendingTemplateTokens(nextSection:String):Void {
		for (token => planned in templateTokens)
			throw 'HxTypeRegistry cannot emit $nextSection while template token $token for $planned is still unconsumed.';
	}

	function requirePhase(expected:Int, label:String):Void {
		if (phase != expected)
			throw 'HxTypeRegistry cannot emit $label at phase $phase; expected phase $expected.';
	}

	static function runtimeUseId(role:String, index:Int):String {
		return OWNER_ID + ":runtime-use:" + role + ":" + Std.string(index);
	}

	static function copyStrings(values:Array<String>):Array<String> {
		return values == null ? [] : values.copy();
	}

	static function ocamlStringLiteral(value:String):String {
		return "\"" + escapeOcamlString(value) + "\"";
	}

	static function ocamlStringListLiteral(items:Array<String>):String {
		return items.length == 0 ? "[]" : "[ " + items.map(ocamlStringLiteral).join("; ") + " ]";
	}

	/** Matches the existing compiler string escaping so this ownership move is byte-preserving. */
	static function escapeOcamlString(value:String):String {
		return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
	}
}
#end
