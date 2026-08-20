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
	}
}
