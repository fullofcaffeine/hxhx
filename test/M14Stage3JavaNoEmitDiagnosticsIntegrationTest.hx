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
		final source = [
			"@:strict(jvm.annotation.ClassReflectionInformation(hasSuperClass = false))",
			"class Main {",
			"\tstatic function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Main", [])));
		final diagnostic = JavaNoEmitDiagnostics.jvmAnnotationMetadataDiagnostic([typed]);
		assertTrue(diagnostic != null, "expected malformed jvm.annotation metadata diagnostic");
		assertContains(diagnostic, "Main.hx:1: characters 52-73 : Object declaration expected", "diagnostic");
	}
}
