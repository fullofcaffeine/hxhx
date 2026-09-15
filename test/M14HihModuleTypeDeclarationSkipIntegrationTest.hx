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

	/** Final class modifiers must retain class facts without consuming module-level final fields. */
	static function assertFinalClassDeclarations():Void {
		for (modifiers in ["final", "private final", "final private", "extern final", "final extern"]) {
			final module = new HxParser([
				"final before:Int = 7;",
				"@:keep " + modifiers + " class SealedValue<T> { public var value:T; }",
				"class Main { static function main():Void {} }",
				"final after:Int = 9;"
			].join("\n")).parseModule("Main");
			final declaration = findClass(module, "SealedValue");
			final metadata = HxClassDecl.getMetadata(declaration);
			assertTrue(metadata.indexOf("@:keep") >= 0, "class metadata was lost: " + modifiers);
			assertTrue(metadata.indexOf("final") >= 0, "final class modifier was lost: " + modifiers);
			assertTrue(metadata.indexOf("__hxhx_type_params=T") >= 0, "generic class parameter was lost: " + modifiers);
			assertTrue(HxClassDecl.getFields(declaration).length == 1, "module fields leaked into final class: " + modifiers);
			assertTrue(HxClassDecl.getVisibility(declaration) == (modifiers.indexOf("private") >= 0 ? Private : Public),
				"class visibility was lost: " + modifiers);
			final main = findClass(module, "Main");
			final fields = HxClassDecl.getFields(main);
			assertTrue(fields.length == 2, "module-level final fields were lost: " + modifiers);
			assertTrue(HxFieldDecl.getName(fields[0]) == "before" && HxFieldDecl.getName(fields[1]) == "after",
				"module-level final field order changed: " + modifiers);
			assertTrue(fields[0].isFinal && fields[1].isFinal, "module fields lost final modifiers: " + modifiers);
			assertTrue(HxClassDecl.getFunctions(main).length == 1, "following class body was lost: " + modifiers);
		}
		assertRejects("final @:keep class Invalid {}", "Expected top-level field name");
	}

	static function main():Void {
		assertFinalClassDeclarations();
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
