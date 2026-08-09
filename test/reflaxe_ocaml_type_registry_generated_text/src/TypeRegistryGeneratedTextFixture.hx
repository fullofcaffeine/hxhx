import reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassFields;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassSuper;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassTags;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEmptyConstructor;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEnumLayout;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryProgramIdentifier;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryRuntimeUse;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

using StringTools;

/**
	Checks the Haxe-owned generator for the base reflection registry.

	The fixture includes two deliberately unfinished runtime calls between the
	checked base sections. Those calls stay visible as migration debt; they must
	not appear in the list of runtime uses that already have semantic authority.
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

	static function emitter(includeConstructorUses:Bool = true):OcamlTypeRegistryBaseEmitter {
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
		final programIdentifiers:Array<OcamlTypeRegistryProgramIdentifier> = [
			{id: "program:empty-constructor-module:0", exactIdentifier: "HxDemoFoo"},
			{id: "program:empty-constructor-function:0", exactIdentifier: "foo___empty"}
		];
		final constructorRuntimeUses:Array<OcamlTypeRegistryRuntimeUse> = [
			{id: "constructor:register", exactSymbol: "HxType.register_class_ctor", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY},
			{id: "constructor:array-type", exactSymbol: "HxArray.t", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS},
			{id: "constructor:array-length", exactSymbol: "HxArray.length", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS},
			{id: "constructor:bool", exactSymbol: "HxRuntime.unbox_bool_or_obj", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX},
			{id: "constructor:array-get", exactSymbol: "HxArray.get", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS},
			{id: "constructor:null", exactSymbol: "HxRuntime.hx_null", capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL},
			{
				id: "constructor:string-null",
				exactSymbol: "HxString.hx_null_string",
				capability: OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_STRING_NULL
			}
		];
		return new OcamlTypeRegistryBaseEmitter("portable", "program:fixture:v1", true, ["demo.Foo"], ["demo.Choice"], layouts, emptyConstructors, fields,
			supers, tags, programIdentifiers, includeConstructorUses ? constructorRuntimeUses : []);
	}

	static function validAndExplicitlyPartial():Void {
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
		generated.addLiteral("  ");
		generated.addLegacyRuntimeUse("legacy:dynamic-stringifier", "HxDynamic.register_class_stringifier");
		generated.addLiteral(" \"demo.Foo\" legacy_stringifier;\n");
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
			"  HxDynamic.register_class_stringifier \"demo.Foo\" legacy_stringifier;",
			"  HxType.register_class_super \"demo.Foo\" (HxType.class_ \"demo.Base\");",
			"  HxType.register_class_tags \"demo.Foo\" [ \"demo.Base\"; \"demo.Foo\" ];",
			"  ()",
			""
		].join("\n");
		assertTrue(record.content == expected, "type-registry generated bytes changed");
		assertTrue(record.orderedUseIds.length == 17, "the fixture should authorize ten base and seven constructor runtime uses");
		assertTrue(record.legacyUseIds.join(",") == "legacy:dynamic-stringifier", "unfinished runtime calls should remain explicit and ordered");
		for (legacyId in record.legacyUseIds)
			assertTrue(!record.orderedUseIds.contains(legacyId), "legacy runtime use was incorrectly counted as checked authority");
		assertTrue(record.programIdentifierIds.join(",") == "program:empty-constructor-module:0,program:empty-constructor-function:0",
			"program-owned identifiers should remain separate from runtime authority");
		for (programId in record.programIdentifierIds) {
			assertTrue(!record.orderedUseIds.contains(programId), "program identifier was incorrectly counted as checked runtime authority");
			assertTrue(!record.legacyUseIds.contains(programId), "program identifier was incorrectly counted as legacy runtime debt");
		}
	}

	static function legacyTextCannotHidePrivateCalls():Void {
		final directLiteral = emitter(false);
		directLiteral.emitHeader();
		directLiteral.emitClassAndEnumIdentities();
		directLiteral.emitEnumLayouts();
		directLiteral.addLiteral("  HxType.register_class_ctor \"demo.Foo\" legacy_ctor;\n");
		directLiteral.emitEmptyConstructors();
		directLiteral.emitClassFields();
		directLiteral.emitClassSupers();
		directLiteral.emitClassTags();
		directLiteral.emitFooter();
		expectFailure("unmarked legacy call", "private runtime name HxType", () -> directLiteral.seal());

		final hiddenInString = emitter(false);
		hiddenInString.emitHeader();
		hiddenInString.emitClassAndEnumIdentities();
		hiddenInString.emitEnumLayouts();
		hiddenInString.addLiteral("  let hidden = \"");
		hiddenInString.addLegacyRuntimeUse("legacy:hidden", "HxType.register_class_ctor");
		hiddenInString.addLiteral("\" in ignore hidden;\n");
		hiddenInString.emitEmptyConstructors();
		hiddenInString.emitClassFields();
		hiddenInString.emitClassSupers();
		hiddenInString.emitClassTags();
		hiddenInString.emitFooter();
		expectFailure("legacy marker in string", "is not an OCaml code identifier", () -> hiddenInString.seal());

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
	}

	static function main():Void {
		validAndExplicitlyPartial();
		legacyTextCannotHidePrivateCalls();
		Sys.println("TYPE_REGISTRY_GENERATED_TEXT:PASS");
	}
}
