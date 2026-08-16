class M14HihModuleTypeDeclarationSkipIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function findClass(module:HxModuleDecl, name:String):HxClassDecl {
		for (candidate in HxModuleDecl.getClasses(module))
			if (HxClassDecl.getName(candidate) == name)
				return candidate;
		fail("missing class " + name);
		return null;
	}

	static function assertRejects(source:String, expectedMessage:String):Void {
		var diagnostic = "";
		try {
			new HxParser(source).parseModule("Main");
		} catch (error:HxParseError) {
			diagnostic = error.toString();
		}
		assertTrue(diagnostic.indexOf(expectedMessage) >= 0, 'expected "$expectedMessage" in parser diagnostic, got "$diagnostic"');
	}

	static function main():Void {
		final source = [
			"package js.lib.intl;",
			"@:native(\"Intl.NumberFormat\")",
			"extern class NumberFormat {",
			"  @:pure function new(?locales:String);",
			"}",
			"typedef NumberFormatOptions = {",
			"  var ?localeMatcher:String;",
			"  var useGrouping:Bool;",
			"}",
			"typedef NumberFormatResolvedOption = {",
			"  final locale:String;",
			"  final numberingSystem:String;",
			"}",
			"typedef NestedPayloads = Array<{",
			"  var required:Int;",
			"  var ?optional:String;",
			"}>;",
			"enum abstract NumberFormatStyle(String) {",
			"  var Decimal = \"decimal\";",
			"}",
			"abstract WrappedNumber(Float) {",
			"  public function value():Float return this;",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");

		final module = new HxParser(source).parseModule("Main");
		final mainClass = findClass(module, "Main");
		final numberFormat = findClass(module, "NumberFormat");

		assertTrue(HxClassDecl.getFields(mainClass).length == 0, "typedef or enum members leaked into Main as module-level fields");
		assertTrue(HxClassDecl.getFunctions(mainClass).length == 1, "typedef, enum, or abstract members leaked into Main as module-level functions");
		assertTrue(HxFunctionDecl.getName(HxClassDecl.getFunctions(mainClass)[0]) == "main", "Main lost its actual entrypoint");
		assertTrue(HxClassDecl.getFields(numberFormat).length == 0, "later typedef members leaked backward into the extern class");
		assertRejects([
			"typedef NestedPayloads = Array<{",
			"  var required:Int;",
			"  var ?optional:String;",
			"}>;",
			"class {}"
		].join("\n"), "Expected class name");
		Sys.println("M14_HIH_MODULE_TYPE_DECLARATION_SKIP:PASS");
	}
}
