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
				fail("expected synthetic TInst module entry but got " + Std.string(t));
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

		MacroState.reset();
	}
}
