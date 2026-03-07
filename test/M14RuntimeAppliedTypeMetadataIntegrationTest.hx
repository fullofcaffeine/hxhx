import haxe.macro.Expr;
import haxe.macro.Type;
import hxhx.macro.MacroState;
import hxhxmacrohost.api.RuntimeMacroTypes;

class M14RuntimeAppliedTypeMetadataIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function expectInst(t:Type):Ref<ClassType> {
		return switch (t) {
			case TInst(c, _):
				c;
			case _:
				fail("expected synthetic TInst module entry but got " + RuntimeMacroTypes.toString(t));
				null;
		}
	}

	static function expectEnum(t:Type):Ref<EnumType> {
		return switch (t) {
			case TEnum(e, _):
				e;
			case _:
				fail("expected synthetic TEnum module entry but got " + RuntimeMacroTypes.toString(t));
				null;
		}
	}

	static function expectTypeDef(t:Type):Ref<DefType> {
		return switch (t) {
			case TType(td, _):
				td;
			case _:
				fail("expected synthetic TType module entry but got " + RuntimeMacroTypes.toString(t));
				null;
		}
	}

	static function assertMetadataHas(meta:MetaAccess, name:String):Array<MetadataEntry> {
		assertTrue(meta.has(name), "expected metadata " + name);
		final entries = meta.extract(name);
		assertTrue(entries != null && entries.length > 0, "expected extracted metadata entries for " + name);
		return entries;
	}

	static function main():Void {
		MacroState.reset();
		MacroState.registerGlobalMetadata("hxhxmacros.RuntimeContextApiMacros", "@:demoMeta", false, true, false);
		MacroState.registerGlobalMetadata("hxhxmacros.RuntimeContextApiMacros", "@:nullSafety(Strict)", false, true, false);

		final applied = MacroState.listAppliedTypeMetadata("hxhxmacros.RuntimeContextApiMacros");
		assertTrue(applied.length == 2, "expected two applied metadata entries");
		assertTrue(applied.indexOf("@:demoMeta") >= 0, "expected demo metadata entry");
		assertTrue(applied.indexOf("@:nullSafety(Strict)") >= 0, "expected nullSafety metadata entry");

		final moduleTypes = RuntimeMacroTypes.moduleTypesForPath("hxhxmacros.RuntimeContextApiMacros", applied);
		assertTrue(moduleTypes.length == 1, "expected one synthetic module type");

		final classRef = expectInst(moduleTypes[0]);
		final classType = classRef.get();
		final meta = classType.meta;

		assertMetadataHas(meta, ":demoMeta");
		final nullSafetyEntries = assertMetadataHas(meta, ":nullSafety");
		final nullSafetyParams = nullSafetyEntries[0].params;
		assertTrue(nullSafetyParams.length == 1, "expected one nullSafety parameter");
		switch (nullSafetyParams[0].expr) {
			case EConst(CIdent("Strict")):
			case _:
				fail("expected nullSafety parameter Strict");
		}

		final syntheticType = RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeContextApiMacros", "class", applied);
		final syntheticClass = expectInst(syntheticType).get();
		assertTrue(syntheticClass.meta.has(":demoMeta"), "expected demo metadata on synthetic type path");
		assertTrue(syntheticClass.meta.has(":nullSafety"), "expected nullSafety metadata on synthetic type path");

		final enumApplied = ["@:enumProbeMeta"];
		final typedefApplied = ["@:typedefProbeMeta"];
		final abstractApplied = ["@:abstractProbeMeta"];
		final syntheticEnum = expectEnum(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleState", "enum", enumApplied)).get();
		assertTrue(syntheticEnum.meta.has(":enumProbeMeta"), "expected enum metadata on synthetic runtime type");
		final syntheticTypedef = expectTypeDef(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleData", "typedef", typedefApplied)).get();
		assertTrue(syntheticTypedef.meta.has(":typedefProbeMeta"), "expected typedef metadata on synthetic runtime type");
		final syntheticAbstract = expectInst(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleId", "abstract", abstractApplied)).get();
		assertTrue(syntheticAbstract.meta.has(":abstractProbeMeta"), "expected abstract metadata on synthetic runtime type");

		final moduleEntries = RuntimeMacroTypes.moduleTypesForModule("hxhxmacros.RuntimeModuleMembers", [
			{name: "RuntimeModuleMembers", kind: "class", metadata: []},
			{name: "RuntimeModuleState", kind: "enum", metadata: enumApplied},
			{name: "RuntimeModuleData", kind: "typedef", metadata: typedefApplied},
			{name: "RuntimeModuleId", kind: "abstract", metadata: abstractApplied}
		]);
		assertTrue(moduleEntries.length == 4, "expected four synthetic module members");
		expectInst(moduleEntries[0]);
		assertTrue(expectEnum(moduleEntries[1]).get().meta.has(":enumProbeMeta"), "expected per-type enum metadata");
		assertTrue(expectTypeDef(moduleEntries[2]).get().meta.has(":typedefProbeMeta"), "expected per-type typedef metadata");
		assertTrue(expectInst(moduleEntries[3]).get().meta.has(":abstractProbeMeta"), "expected per-type abstract metadata");

		MacroState.reset();
	}
}
