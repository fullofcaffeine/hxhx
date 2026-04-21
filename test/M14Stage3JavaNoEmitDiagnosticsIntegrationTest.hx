class M14Stage3JavaNoEmitDiagnosticsIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function assertContains(message:String, needle:String, label:String):Void {
		assertTrue(message.indexOf(needle) >= 0, label + " missing `" + needle + "` in: " + message);
	}

	static function main():Void {
		final metadataSource = [
			"@:strict(jvm.annotation.ClassReflectionInformation(hasSuperClass = false))",
			"class Main {",
			"\tstatic function main() {}",
			"}"
		].join("\n");
		final metadataDiagnostic = JavaNoEmitDiagnostics.jvmAnnotationMetadataDiagnostic([typedModule(metadataSource)]);
		assertTrue(metadataDiagnostic != null, "expected malformed jvm.annotation metadata diagnostic");
		assertContains(metadataDiagnostic, "Main.hx:1: characters 52-73 : Object declaration expected", "metadata diagnostic");

		final abstractSource = [
			"abstract",
			"class BaseAbstract {",
			"\t@:overload",
			"\tabstract",
			"\tfunction required():Void;",
			"",
			"\t@:overload",
			"\tabstract",
			"\tfunction required(i:Int):Void;",
			"}",
			"",
			"class Concrete extends BaseAbstract {",
			"\tstatic function main() {}",
			"",
			"\t@:overload",
			"\tfunction required():Void {}",
			"}"
		].join("\n");
		final abstractDiagnostic = JavaNoEmitDiagnostics.abstractOverloadImplementationDiagnostic([typedModule(abstractSource)]);
		assertTrue(abstractDiagnostic != null, "expected missing abstract overload implementation diagnostic");
		assertContains(abstractDiagnostic,
			"Main.hx:12: characters 7-15 : This class extends abstract class BaseAbstract but doesn't implement the following method", "abstract diagnostic");
		assertContains(abstractDiagnostic, "Main.hx:9: characters 11-19 : ... required(i:Int)", "abstract diagnostic missing method");

		final mixedCollisionSource = [
			"class Main {",
			"\tstatic function main() {}",
			"",
			"\t@:overload static function bridge(fn:(Int)->String) {}",
			"\t@:overload static function bridge(fn:(Bool)->String) {}",
			"",
			"\t@:overload static function mirror(fn:(Int)->String) {}",
			"\t@:overload static function mirror(fn:(Int)->String) {}",
			"}"
		].join("\n");
		final mixedCollisionDiagnostic = JavaNoEmitDiagnostics.overloadCollisionDiagnostic([typedModule(mixedCollisionSource)]);
		assertTrue(mixedCollisionDiagnostic != null, "expected mixed overload collision diagnostic");
		assertContains(mixedCollisionDiagnostic, "Main.hx:4: characters 13-56 : Another overloaded field of similar signature was already declared : bridge",
			"similar overload diagnostic");
		assertContains(mixedCollisionDiagnostic, "Main.hx:4: characters 13-56 : ... The signatures are different in Haxe, but not in the target language",
			"similar overload diagnostic explanation");
		assertContains(mixedCollisionDiagnostic, "Main.hx:5: characters 13-57 : ... The second field is declared here",
			"similar overload diagnostic second field");
		assertContains(mixedCollisionDiagnostic, "Main.hx:7: characters 13-56 : Another overloaded field of same signature was already declared : mirror",
			"same overload diagnostic");
		assertContains(mixedCollisionDiagnostic, "Main.hx:8: characters 13-56 : ... The second field is declared here",
			"same overload diagnostic second field");

		final overloadedThenDuplicateSource = [
			"class Main {",
			"\t@:overload static function choose(s:String) {}",
			"\t@:overload static function choose(i:Int) {}",
			"\t@:overload static function choose(i:Int) {}",
			"",
			"\tstatic public function main() {}",
			"}"
		].join("\n");
		final overloadedThenDuplicateDiagnostic = JavaNoEmitDiagnostics.overloadCollisionDiagnostic([typedModule(overloadedThenDuplicateSource)]);
		assertTrue(overloadedThenDuplicateDiagnostic != null, "expected overloaded duplicate diagnostic");
		assertContains(overloadedThenDuplicateDiagnostic,
			"Main.hx:4: characters 13-45 : Another overloaded field of same signature was already declared : choose", "overloaded duplicate diagnostic");
		assertContains(overloadedThenDuplicateDiagnostic, "Main.hx:3: characters 13-45 : ... The second field is declared here",
			"overloaded duplicate diagnostic prior field");
	}

	static function typedModule(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		return new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Main", [])));
	}
}
