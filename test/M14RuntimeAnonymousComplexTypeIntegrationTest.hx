import haxe.macro.Expr;
import haxe.macro.Type;
import hxhxmacrohost.api.RuntimeMacroTypes;

class M14RuntimeAnonymousComplexTypeIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function expectAnonymous(t:Type):Ref<AnonType> {
		return switch (t) {
			case TAnonymous(ref):
				ref;
			case _:
				fail("expected anonymous type but got " + RuntimeMacroTypes.describeTypeShape(t));
				null;
		};
	}

	static function expectAnonymousComplex(ct:ComplexType):Array<Field> {
		return switch (ct) {
			case TAnonymous(fields):
				fields;
			case _:
				fail("expected anonymous complex type");
				[];
		};
	}

	static function main():Void {
		final resolved = RuntimeMacroTypes.resolveComplexType(macro :{
			name:String,
			count:Int,
			profile:{active:Bool},
			callback:(String) -> Int
		});
		final anon = expectAnonymous(resolved).get();
		assertTrue(anon.fields.length == 4, "expected four anonymous fields");
		assertTrue(anon.fields[0].name == "name", "expected name field");
		assertTrue(RuntimeMacroTypes.toString(anon.fields[0].type) == "String", "expected name:String");
		assertTrue(anon.fields[1].name == "count" && !anon.fields[1].isFinal, "expected mutable count field");
		assertTrue(RuntimeMacroTypes.toString(anon.fields[1].type) == "Int", "expected count:Int");
		assertTrue(RuntimeMacroTypes.followedAnonymousFieldSummary(anon.fields[2].type) == "active:Bool", "expected nested anonymous payload");
		assertTrue(RuntimeMacroTypes.toString(anon.fields[3].type) == "(String) -> Int", "expected callback:(String) -> Int");

		final complex = RuntimeMacroTypes.toComplexType(resolved);
		assertTrue(complex != null, "expected anonymous complex type");
		final fields = expectAnonymousComplex(complex);
		assertTrue(fields.length == 4, "expected four anonymous complex fields");
		switch (fields[1].kind) {
			case FVar(_, _):
			case _:
				fail("expected count field to remain a normal variable field");
		}

		final roundTripped = RuntimeMacroTypes.resolveComplexType(complex);
		final roundAnon = expectAnonymous(roundTripped).get();
		assertTrue(roundAnon.fields.length == 4, "expected round-tripped anonymous fields");
		assertTrue(RuntimeMacroTypes.followedAnonymousFieldSummary(roundAnon.fields[2].type) == "active:Bool",
			"expected round-tripped nested anonymous payload");

		final typedefAnon = RuntimeMacroTypes.typeForResolvedDecl("hxhxmacros.RuntimeModuleData", "typedef", [":typedefProbeMeta"], null,
			"test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeModuleMembers.hx", 141, 160, null, [], "{ final name:String; profile:{ active:Bool }; }");
		final typedefComplex = RuntimeMacroTypes.toComplexType(RuntimeMacroTypes.follow(typedefAnon));
		final typedefFields = expectAnonymousComplex(typedefComplex);
		assertTrue(typedefFields.length == 2, "expected typedef anonymous complex fields");
		switch (typedefFields[0].kind) {
			case FProp("default", "never", _, _):
			case _:
				fail("expected typedef final field to preserve final-ness");
		}
	}
}
