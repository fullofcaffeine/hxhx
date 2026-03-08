import haxe.macro.Expr;
import haxe.macro.PositionTools;
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

	static function expectAbstract(t:Type):Ref<AbstractType> {
		return switch (t) {
			case TAbstract(a, _):
				a;
			case _:
				fail("expected synthetic TAbstract module entry but got " + RuntimeMacroTypes.toString(t));
				null;
		}
	}

	static function assertMetadataHas(meta:MetaAccess, name:String):Array<MetadataEntry> {
		assertTrue(meta.has(name), "expected metadata " + name);
		final entries = meta.extract(name);
		assertTrue(entries != null && entries.length > 0, "expected extracted metadata entries for " + name);
		return entries;
	}

	static function assertPosFile(pos:Position, expectedSuffix:String, expectedMin:Int, expectedMax:Int):Void {
		final info = PositionTools.getInfos(pos);
		assertTrue(info.file != null && StringTools.endsWith(info.file, expectedSuffix),
			"expected position file suffix "
			+ expectedSuffix
			+ " but got "
			+ info.file);
		assertTrue(info.min == expectedMin, "expected position min " + expectedMin + " but got " + info.min);
		assertTrue(info.max == expectedMax, "expected position max " + expectedMax + " but got " + info.max);
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

		final syntheticType = RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeContextApiMacros", "class", applied, null,
			"test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx", 10, 30);
		final syntheticClass = expectInst(syntheticType).get();
		assertTrue(syntheticClass.meta.has(":demoMeta"), "expected demo metadata on synthetic type path");
		assertTrue(syntheticClass.meta.has(":nullSafety"), "expected nullSafety metadata on synthetic type path");
		assertPosFile(syntheticClass.pos, "RuntimeContextApiMacros.hx", 10, 30);

		final enumApplied = ["@:enumProbeMeta"];
		final typedefApplied = ["@:typedefProbeMeta"];
		final abstractApplied = ["@:abstractProbeMeta"];
		final syntheticEnum = expectEnum(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleState", "enum", enumApplied, null,
			"test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx", 40, 50)).get();
		assertTrue(syntheticEnum.meta.has(":enumProbeMeta"), "expected enum metadata on synthetic runtime type");
		assertPosFile(syntheticEnum.pos, "RuntimeModuleMembers.hx", 40, 50);
		final syntheticTypedef = expectTypeDef(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleData", "typedef", typedefApplied, null,
			"test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx", 60, 75)).get();
		assertTrue(syntheticTypedef.meta.has(":typedefProbeMeta"), "expected typedef metadata on synthetic runtime type");
		assertPosFile(syntheticTypedef.pos, "RuntimeModuleMembers.hx", 60, 75);
		final syntheticAbstract = expectAbstract(RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleId", "abstract", abstractApplied, null,
			"test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx", 80, 95)).get();
		assertTrue(syntheticAbstract.meta.has(":abstractProbeMeta"), "expected abstract metadata on synthetic runtime type");
		assertPosFile(syntheticAbstract.pos, "RuntimeModuleMembers.hx", 80, 95);

		final moduleEntries = RuntimeMacroTypes.moduleTypesForModule("hxhxmacros.RuntimeModuleMembers", [
			{
				name: "RuntimeModuleMembers",
				kind: "class",
				metadata: [],
				file: "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx",
				min: 100,
				max: 120
			},
			{
				name: "RuntimeModuleState",
				kind: "enum",
				metadata: enumApplied,
				file: "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx",
				min: 121,
				max: 140
			},
			{
				name: "RuntimeModuleData",
				kind: "typedef",
				metadata: typedefApplied,
				file: "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx",
				min: 141,
				max: 160
			},
			{
				name: "RuntimeModuleId",
				kind: "abstract",
				metadata: abstractApplied,
				file: "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx",
				min: 161,
				max: 180
			}
		]);
		assertTrue(moduleEntries.length == 4, "expected four synthetic module members");
		assertPosFile(expectInst(moduleEntries[0]).get().pos, "RuntimeModuleMembers.hx", 100, 120);
		final enumEntry = expectEnum(moduleEntries[1]).get();
		assertTrue(enumEntry.meta.has(":enumProbeMeta"), "expected per-type enum metadata");
		assertPosFile(enumEntry.pos, "RuntimeModuleMembers.hx", 121, 140);
		final typedefEntry = expectTypeDef(moduleEntries[2]).get();
		assertTrue(typedefEntry.meta.has(":typedefProbeMeta"), "expected per-type typedef metadata");
		assertPosFile(typedefEntry.pos, "RuntimeModuleMembers.hx", 141, 160);
		final abstractEntry = expectAbstract(moduleEntries[3]).get();
		assertTrue(abstractEntry.meta.has(":abstractProbeMeta"), "expected per-type abstract metadata");
		assertPosFile(abstractEntry.pos, "RuntimeModuleMembers.hx", 161, 180);

		MacroState.reset();
	}
}
