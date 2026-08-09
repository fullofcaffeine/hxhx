import reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassFields;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassSuper;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassTags;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEmptyConstructor;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEnumLayout;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryProgramIdentifier;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryRuntimeUse;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryRuntimeUseSection;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

using StringTools;

/**
	Checks the Haxe-owned generator for the base reflection registry.

	The fixture checks constructor adapters and Dynamic stringifier registration
	between the base metadata sections. Every private runtime identifier must have
	one planned use before the complete generated file can be published.
**/
class TypeRegistryGeneratedTextFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function emitter(includeConstructorUses:Bool = true, ?stringifierUseIds:Array<String>):OcamlTypeRegistryBaseEmitter {
		final layouts:Array<OcamlTypeRegistryEnumLayout> = [
			{
				enumName: "demo.Choice",
				constructorName: "Some",
				haxeIndex: 1,
				ocamlTag: 0,
				carriesPayload: true
			}
		];
		final emptyConstructors:Array<OcamlTypeRegistryEmptyConstructor> = [
			{
				className: "demo.Foo",
				moduleName: "HxDemoFoo",
				targetFunctionName: "foo___empty"
			}
		];
		final fields:Array<OcamlTypeRegistryClassFields> = [
			{
				className: "demo.Foo",
				instanceFields: ["name"],
				staticFields: ["create"]
			}
		];
		final supers:Array<OcamlTypeRegistryClassSuper> = [
			{
				className: "demo.Foo",
				superName: "demo.Base"
			}
		];
		final tags:Array<OcamlTypeRegistryClassTags> = [
			{
				className: "demo.Foo",
				tags: ["demo.Base", "demo.Foo"]
			}
		];
		final plannedStringifierUseIds = stringifierUseIds == null ? ["dynamic-stringifier:demo.Foo"] : stringifierUseIds;
		final programIdentifiers:Array<OcamlTypeRegistryProgramIdentifier> = [
			{id: "program:empty-constructor-module:0", exactIdentifier: "HxDemoFoo"},
			{id: "program:empty-constructor-function:0", exactIdentifier: "foo___empty"}
		];
		final runtimeUses:Array<OcamlTypeRegistryRuntimeUse> = includeConstructorUses ? [
			{
				id: "constructor:register",
				exactSymbol: "HxType.register_class_ctor",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:array-type",
				exactSymbol: "HxArray.t",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:array-length",
				exactSymbol: "HxArray.length",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:bool",
				exactSymbol: "HxRuntime.unbox_bool_or_obj",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:array-get",
				exactSymbol: "HxArray.get",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:null",
				exactSymbol: "HxRuntime.hx_null",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			},
			{
				id: "constructor:string-null",
				exactSymbol: "HxString.hx_null_string",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_STRING_NULL,
				section: OcamlTypeRegistryRuntimeUseSection.ReflectionConstructor
			}
		] : [];
		for (useId in plannedStringifierUseIds) {
			runtimeUses.push({
				id: useId,
				exactSymbol: "HxDynamic.register_class_stringifier",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_STRING,
				section: OcamlTypeRegistryRuntimeUseSection.DynamicStringifier
			});
			programIdentifiers.push({id: useId + ":program-module", exactIdentifier: "HxDemoFoo"});
			programIdentifiers.push({id: useId + ":program-method", exactIdentifier: "foo_to_string"});
		}
		return new OcamlTypeRegistryBaseEmitter("portable", "program:fixture:v1", true, ["demo.Foo"], ["demo.Choice"], layouts, emptyConstructors, fields,
			supers, tags, programIdentifiers, runtimeUses);
	}

	static function validAndFullyChecked():Void {
		final generated = emitter();
		generated.emitHeader();
		generated.emitClassAndEnumIdentities();
		generated.emitEnumLayouts();
		final register = generated.runtimeToken("constructor:register", "HxType.register_class_ctor");
		final arrayType = generated.runtimeToken("constructor:array-type", "HxArray.t");
		final arrayLength = generated.runtimeToken("constructor:array-length", "HxArray.length");
		final arrayGet = generated.runtimeToken("constructor:array-get", "HxArray.get");
		final boolUnbox = generated.runtimeToken("constructor:bool", "HxRuntime.unbox_bool_or_obj");
		final dynamicNull = generated.runtimeToken("constructor:null", "HxRuntime.hx_null");
		final stringNull = generated.runtimeToken("constructor:string-null", "HxString.hx_null_string");
		generated.addTemplate("  " + register + " \"demo.Foo\" (fun (args : Obj.t " + arrayType + ") ->\n");
		generated.addTemplate("    let len = " + arrayLength + " args in\n");
		generated.addTemplate("    let enabled = " + boolUnbox + " ((" + arrayGet + " args 0)) in\n");
		generated.addTemplate("    let payload = " + dynamicNull + " in\n");
		generated.addTemplate("    let label = " + stringNull + " in\n");
		generated.addLiteral("    ignore (enabled, payload, label, len));\n");
		generated.emitEmptyConstructors();
		generated.emitClassFields();
		final stringifierUseId = "dynamic-stringifier:demo.Foo";
		final registerStringifier = generated.runtimeToken(stringifierUseId, "HxDynamic.register_class_stringifier");
		final programModule = generated.programIdentifierToken(stringifierUseId + ":program-module", "HxDemoFoo");
		final programMethod = generated.programIdentifierToken(stringifierUseId + ":program-method", "foo_to_string");
		generated.addTemplate("  "
			+ registerStringifier
			+ " \"demo.Foo\" (fun value -> "
			+ programModule
			+ "."
			+ programMethod
			+ " (Obj.obj value) ());\n");
		generated.emitClassSupers();
		generated.emitClassTags();
		generated.emitFooter();
		final record = generated.seal();
		OcamlCheckedGeneratedText.verify(record);

		final expected = [
			"# 1 \"HxTypeRegistry.ml\"",
			"(* Generated by reflaxe.ocaml (WIP) *)",
			"(* Type registry used by `Type.resolveClass/resolveEnum`, `Type.get*Fields`, `Type.createInstance`, and typed catches. *)",
			"",
			"let init () : unit =",
			"  ignore (HxType.class_ \"demo.Foo\");",
			"  ignore (HxType.enum_ \"demo.Choice\");",
			"  HxType.register_enum_ctor_layout \"demo.Choice\" \"Some\" 1 (HxType.EnumBlock 0);",
			"  HxType.register_class_ctor \"demo.Foo\" (fun (args : Obj.t HxArray.t) ->",
			"    let len = HxArray.length args in",
			"    let enabled = HxRuntime.unbox_bool_or_obj ((HxArray.get args 0)) in",
			"    let payload = HxRuntime.hx_null in",
			"    let label = HxString.hx_null_string in",
			"    ignore (enabled, payload, label, len));",
			"  HxType.register_class_empty_ctor \"demo.Foo\" (fun () -> Obj.repr (HxDemoFoo.foo___empty ()));",
			"  HxType.register_class_instance_fields \"demo.Foo\" [ \"name\" ];",
			"  HxType.register_class_static_fields \"demo.Foo\" [ \"create\" ];",
			"  HxDynamic.register_class_stringifier \"demo.Foo\" (fun value -> HxDemoFoo.foo_to_string (Obj.obj value) ());",
			"  HxType.register_class_super \"demo.Foo\" (HxType.class_ \"demo.Base\");",
			"  HxType.register_class_tags \"demo.Foo\" [ \"demo.Base\"; \"demo.Foo\" ];",
			"  ()",
			""
		].join("\n");
		assertTrue(record.content == expected, "type-registry generated bytes changed");
		assertTrue(record.orderedUseIds.length == 18, "the fixture should authorize base, constructor, and Dynamic stringifier runtime uses");
		assertTrue(record.legacyUseIds.length == 0, "the complete type registry should contain no generated-text legacy uses");
		assertTrue(record.programIdentifierIds.join(",") == [
			"program:empty-constructor-module:0",
			"program:empty-constructor-function:0",
			"dynamic-stringifier:demo.Foo:program-module",
			"dynamic-stringifier:demo.Foo:program-method"
		].join(","), "program-owned identifiers should remain separate from runtime authority");
		for (programId in record.programIdentifierIds) {
			assertTrue(!record.orderedUseIds.contains(programId), "program identifier was incorrectly counted as checked runtime authority");
			assertTrue(!record.legacyUseIds.contains(programId), "program identifier was incorrectly counted as legacy runtime debt");
		}
	}

	static function uncheckedCodeCannotAddPrivateCalls():Void {
		final directLiteral = emitter(false, []);
		directLiteral.emitHeader();
		directLiteral.emitClassAndEnumIdentities();
		directLiteral.emitEnumLayouts();
		directLiteral.addLiteral("  HxType.register_class_ctor \"demo.Foo\" unchecked_ctor;\n");
		directLiteral.emitEmptyConstructors();
		directLiteral.emitClassFields();
		directLiteral.emitClassSupers();
		directLiteral.emitClassTags();
		directLiteral.emitFooter();
		expectFailure("unchecked private call", "private runtime name HxType", () -> directLiteral.seal());

		final invalidProgramIdentifier = emitter();
		invalidProgramIdentifier.emitHeader();
		invalidProgramIdentifier.emitClassAndEnumIdentities();
		invalidProgramIdentifier.emitEnumLayouts();
		expectFailure("invalid program identifier", "has no planned program identifier program:invalid", () -> {
			final invalidToken = invalidProgramIdentifier.programIdentifierToken("program:invalid", "Bad.Name");
			invalidProgramIdentifier.addTemplate("  " + invalidToken + "\n");
		});

		final wrongRuntimeSymbol = emitter();
		wrongRuntimeSymbol.emitHeader();
		wrongRuntimeSymbol.emitClassAndEnumIdentities();
		wrongRuntimeSymbol.emitEnumLayouts();
		expectFailure("wrong constructor runtime symbol", "expected HxArray.get",
			() -> wrongRuntimeSymbol.runtimeToken("constructor:array-get", "HxArray.set"));

		final wrongStringifierSymbol = emitter(false);
		wrongStringifierSymbol.emitHeader();
		wrongStringifierSymbol.emitClassAndEnumIdentities();
		wrongStringifierSymbol.emitEnumLayouts();
		expectFailure("wrong Dynamic stringifier symbol", "expected HxDynamic.register_class_stringifier",
			() -> wrongStringifierSymbol.runtimeToken("dynamic-stringifier:demo.Foo", "HxDynamic.register_value_stringifier"));

		final reordered = emitter(false, ["dynamic-stringifier:first", "dynamic-stringifier:second"]);
		reordered.emitHeader();
		reordered.emitClassAndEnumIdentities();
		reordered.emitEnumLayouts();
		reordered.emitEmptyConstructors();
		reordered.emitClassFields();
		for (useId in ["dynamic-stringifier:second", "dynamic-stringifier:first"]) {
			final register = reordered.runtimeToken(useId, "HxDynamic.register_class_stringifier");
			final moduleName = reordered.programIdentifierToken(useId + ":program-module", "HxDemoFoo");
			final methodName = reordered.programIdentifierToken(useId + ":program-method", "foo_to_string");
			reordered.addTemplate("  " + register + " \"demo.Foo\" (fun value -> " + moduleName + "." + methodName + " (Obj.obj value) ());\n");
		}
		reordered.emitClassSupers();
		reordered.emitClassTags();
		reordered.emitFooter();
		expectFailure("reordered Dynamic stringifiers", "runtime use order", () -> reordered.seal());
	}

	static function main():Void {
		validAndFullyChecked();
		uncheckedCodeCannotAddPrivateCalls();
		Sys.println("TYPE_REGISTRY_GENERATED_TEXT:PASS");
	}
}
