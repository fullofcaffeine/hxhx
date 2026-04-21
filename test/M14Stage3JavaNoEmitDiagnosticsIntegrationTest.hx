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
	}

	static function typedModule(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		return new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Main", [])));
	}
}
