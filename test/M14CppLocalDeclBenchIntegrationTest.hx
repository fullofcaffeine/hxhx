import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppLocalDeclFixture = {
	var scope:backend.cpp.CppRenderScope;
	var owner:HxClassDecl;
}

/**
	Focused attribution probe for C++ local-declaration rendering.

	Strict Cpp timing identifies an explicit String local initialized by a literal
	as a stable statement hotspot. This probe separates declared-type discovery,
	initializer rendering, and the complete declaration while retaining controls
	that must continue through the general local-declaration pipeline.
**/
class M14CppLocalDeclBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 250;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function fixture():CppLocalDeclFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final stringAlias = new HxClassDecl("StringAlias", false, [], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=String"]);
		final owner = new HxClassDecl("LocalDeclBenchOwner", false, [], [new HxFieldDecl("value", Public, false, "String", null)]);
		for (cls in [stringAlias, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		for (i in 0...280) {
			final cls = new HxClassDecl("LocalDeclDummy" + i, false, [], []);
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		return {
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void"),
			owner: owner
		};
	}

	static function elapsed(calls:Int, action:Void->Void):Float {
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function elapsedIndexed(calls:Int, action:Int->Void):Float {
		final start = Sys.time();
		for (i in 0...calls)
			action(i);
		return Sys.time() - start;
	}

	static function render(stmt:HxStmt, scope:backend.cpp.CppRenderScope):String {
		return @:privateAccess backend.cpp.CppTargetCore.renderStmt(stmt, "", scope).join("\n");
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_LOCAL_DECL_BENCH_CALLS", DEFAULT_CALLS);
		final literal = EString('{ test } "quoted"\nnext');
		final typedStmt = SVar("text", "String", literal, HxPos.unknown());
		final phaseFixture = fixture();
		var declaredTypeSample = "";
		final declaredTypeSeconds = elapsed(calls, () -> {
			declaredTypeSample = @:privateAccess
				backend.cpp.CppTargetCore.cppLocalDeclaredType("text", "String", literal, phaseFixture.scope, "text");
		});
		var initSample = "";
		final initSeconds = elapsed(calls, () -> {
			initSample = @:privateAccess backend.cpp.CppTargetCore.renderLocalInitExpr(literal, "std::string", "std::string", phaseFixture.scope);
		});
		final fullFixtures = [for (_ in 0...calls) fixture()];
		var fullSample = "";
		final fullSeconds = elapsedIndexed(calls, i -> {
			fullSample = render(typedStmt, fullFixtures[i].scope);
		});

		final controls = fixture();
		final untypedSample = render(SVar("untypedText", "", EString("literal"), HxPos.unknown()), controls.scope);
		final dynamicSample = render(SVar("dynamicText", "Dynamic", EString("literal"), HxPos.unknown()), controls.scope);
		final abstractSample = render(SVar("abstractText", "StringAlias", EString("literal"), HxPos.unknown()), controls.scope);
		final firstShadowSample = render(SVar("shadow", "String", EString("first"), HxPos.unknown()), controls.scope);
		final secondShadowSample = render(SVar("shadow", "String", EString("second"), HxPos.unknown()), controls.scope);
		final fieldShadowSample = render(SVar("value", "String", EIdent("value"), HxPos.unknown()), controls.scope);
		controls.scope.localNames.set("source", "source");
		controls.scope.localTypes.set("source", "std::string");
		controls.scope.localTypeHints.set("source", "String");
		final nonliteralSample = render(SVar("copied", "String", EIdent("source"), HxPos.unknown()), controls.scope);

		assertTrue(declaredTypeSample == "std::string", "typed String literal locals should retain their declared C++ type");
		assertTrue(initSample == 'std::string("{ test } \\"quoted\\"\\nnext")',
			"typed String literal initialization should preserve braces, quotes, and newlines, got " + initSample);
		assertTrue(fullSample == "std::string text = " + initSample + ";", "typed String literal declarations should retain exact output, got " + fullSample);
		assertTrue(untypedSample == 'auto untypedText = std::string("literal");', "untyped String literal locals should retain auto declarations");
		assertTrue(dynamicSample == 'std::string dynamicText = std::string("literal");',
			"Dynamic-shaped String literal locals should retain their current carrier");
		assertTrue(abstractSample == 'std::string abstractText = std::string("literal");',
			"String-backed abstract locals should retain general conversion rendering");
		assertTrue(firstShadowSample == 'std::string shadow = std::string("first");'
			&& secondShadowSample == 'std::string shadow_2 = std::string("second");',
			"duplicate typed String locals should retain unique C++ names");
		assertTrue(fieldShadowSample == "std::string value = std::string(this->value);",
			"nonliteral same-name field initialization should retain explicit owner qualification");
		assertTrue(nonliteralSample == "std::string copied = std::string(source);",
			"ordinary nonliteral String initialization should remain on the general conversion path");

		Sys.println("CPP_LOCAL_DECL_BENCH:PASS calls=" + calls + " declared_type_seconds=" + declaredTypeSeconds + " init_seconds=" + initSeconds
			+ " full_seconds=" + fullSeconds);
	}
}
