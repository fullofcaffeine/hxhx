/**
	Proves that Stage3 accepts and retains metadata written before a function argument.

	The host Haxe compiler parses `hostAccepted`, while `HxParser` parses the same
	argument form from source text. This keeps the expected syntax independent of
	the upstream null-safety fixture that exposed the parser gap.
**/
class M14HihFunctionArgumentMetadataIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertEquals(expected:String, actual:String, label:String):Void {
		if (actual != expected)
			fail(label + ": expected " + expected + ", got " + actual);
	}

	static function assertTrue(condition:Bool, label:String):Void {
		if (!condition)
			fail(label);
	}

	static function hostAccepted(@:nullSafety(Off) value:Dynamic):Dynamic {
		return value;
	}

	static function main():Void {
		assertEquals("accepted", hostAccepted("accepted"), "host Haxe argument metadata");

		final source = [
			"class Main {",
			"  static function accept(@:nullSafety(Off) value:Dynamic, other:String):Dynamic {",
			"    return value;",
			"  }",
			"}"
		].join("\n");
		final parsed = new HxParser(source).parseModule("Main");
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(parsed));
		final arguments = HxFunctionDecl.getArgs(functions[0]);
		assertEquals("value", HxFunctionArg.getName(arguments[0]), "metadata argument name");
		assertEquals("Dynamic", HxFunctionArg.getTypeHint(arguments[0]), "metadata argument type");
		assertEquals("@:nullSafety(Off)", HxFunctionArg.getMetadata(arguments[0]).join("|"), "argument metadata");
		assertEquals("other", HxFunctionArg.getName(arguments[1]), "following argument name");
		assertEquals("", HxFunctionArg.getMetadata(arguments[1]).join("|"), "following argument metadata");

		final bodyStart = source.indexOf("{") + 1;
		final scanned = ParserStageScanHelpers.scanClassBodyForStatics(source, bodyStart);
		final scannedArguments = HxFunctionDecl.getArgs(scanned.functions[0]);
		assertEquals("value", HxFunctionArg.getName(scannedArguments[0]), "scanned metadata argument name");
		assertEquals("@:nullSafety(Off)", HxFunctionArg.getMetadata(scannedArguments[0]).join("|"), "scanned argument metadata");

		var malformedRejected = false;
		try {
			new HxParser("class Invalid { static function reject(@:(Off) value:Dynamic) {} }").parseModule("Invalid");
		} catch (error:haxe.Exception) {
			malformedRejected = error.message.indexOf("Expected metadata name") >= 0;
		}
		assertTrue(malformedRejected, "malformed argument metadata must keep a stable parser diagnostic");
		checkSharedSignatureReader();
	}

	/** Method declarations and function expressions must retain the same written argument facts. */
	static function checkSharedSignatureReader():Void {
		final signature = "(@:keep ?value:Null<Int> = null, callback:(Int, Int)->Int, ...items:String)";
		final parsed = new HxParser("class Main { static function accept" + signature + " {} }").parseModule("Main");
		final method = HxFunctionDecl.getArgs(HxClassDecl.getFunctions(HxModuleDecl.getMainClass(parsed))[0]);
		final expression = HxFunctionSyntaxParser.parse("function" + signature + " {}").arguments;
		assertTrue(method.length == 3 && expression.length == 3, "shared signature arity");
		for (index in 0...method.length) {
			final written = expression[index].declaration;
			assertEquals(HxFunctionArg.getName(written), HxFunctionArg.getName(method[index]), "shared argument name");
			assertEquals(HxFunctionArg.getMetadata(written).join("|"), HxFunctionArg.getMetadata(method[index]).join("|"), "shared metadata");
			assertEquals(HxFunctionArg.getDefaultValueText(written), HxFunctionArg.getDefaultValueText(method[index]), "shared default text");
			assertTrue(HxFunctionArg.getIsRest(written) == HxFunctionArg.getIsRest(method[index]), "shared rest marker");
		}
		assertTrue(HxFunctionArg.getIsOptional(method[0]), "written optional marker");
		switch (HxFunctionArg.getDefaultValue(method[0])) {
			case Default(ENull):
			case _:
				fail("explicit null default disappeared");
		}
		assertEquals("(Int,Int)->Int", HxFunctionArg.getTypeHint(method[1]), "nested function annotation");
		assertEquals("String", HxFunctionArg.getTypeHint(expression[2].declaration), "written rest element hint");
		assertEquals("Array<String>", HxFunctionArg.getTypeHint(method[2]), "method body rest container");
		assertTrue(HxFunctionArg.getIsOptional(method[2]), "method rest omission contract");
		for (parameters in ["(value:)", "(value=)"]) {
			var rejected = false;
			try
				new HxParser("class Invalid { static function reject" + parameters + " {} }").parseModule("Invalid")
			catch (_:HxParseError)
				rejected = true;
			assertTrue(rejected, "method must reject a missing annotation or default: " + parameters);
		}
	}
}
