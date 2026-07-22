import haxe.io.Bytes;
import hxhx.CompilationServerReply;
import hxhx.CompilationServerRequest;
import hxhx.CompilationServerRequestCodec;
import hxhx.CompilationServerRequestDispatcher;

class M14CompilationServerRequestDispatcherIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
	}

	static function assertArgs(actual:Array<String>, expected:Array<String>, label:String):Void {
		assertEquals(actual.join("\n"), expected.join("\n"), label);
	}

	static function main():Void {
		final baseArgs = ["--hxhx-no-emit", "--hxhx-out", "out"];
		final requestArgs = ["-cp", "src", "-main", "Main"];
		final direct = new CompilationServerRequest(7, baseArgs, requestArgs, Bytes.ofString("original input"));
		baseArgs[0] = "mutated base";
		requestArgs[0] = "mutated request";
		assertArgs(direct.invocationArgs(), ["--hxhx-no-emit", "--hxhx-out", "out", "-cp", "src", "-main", "Main"], "request constructor copy");

		final firstInput = direct.stdinBytes();
		assertTrue(firstInput != null, "request should return copied display input");
		firstInput.set(0, "X".code);
		final secondInput = direct.stdinBytes();
		assertTrue(secondInput != null, "request should retain display input after caller mutation");
		assertEquals(secondInput.getString(0, secondInput.length), "original input", "request input copy");

		final decoded = CompilationServerRequestCodec.decodeString(8, ["--base"], "--display\r\nMain.hx@0@diagnostics\n-cp\nsrc\n\x01class Main {}");
		assertTrue(decoded.requestId == 8, "codec should retain the request ID");
		assertArgs(decoded.requestArgs(), ["--display", "Main.hx@0@diagnostics", "-cp", "src"], "decoded request args");
		assertEquals(decoded.findFlagValue("--display"), "Main.hx@0@diagnostics", "display flag");
		final decodedInput = decoded.stdinBytes();
		assertTrue(decodedInput != null, "codec should preserve display stdin");
		assertEquals(decodedInput.getString(0, decodedInput.length), "class Main {}", "decoded display stdin");

		var compileCalls = 0;
		var compiledArgs = new Array<String>();
		final compileReply = CompilationServerRequestDispatcher.dispatch(direct, args -> {
			compileCalls += 1;
			compiledArgs = args;
			return 0;
		});
		assertTrue(compileCalls == 1, "ordinary request should call the shared compiler exactly once");
		assertArgs(compiledArgs, direct.invocationArgs(), "shared compile invocation");
		assertTrue(!compileReply.isError, "successful compile should not be an error reply");
		assertEquals(compileReply.payload, "OK", "successful compile reply");

		final failedReply = CompilationServerRequestDispatcher.dispatch(direct, _ -> 1);
		assertTrue(failedReply.isError, "failed compile should return an error reply");
		assertEquals(failedReply.payload, "hxhx(stage3): server request failed", "failed compile reply");

		final displayReply = CompilationServerRequestDispatcher.dispatch(decoded, _ -> {
			throw "display request must not invoke the ordinary compile callback";
		});
		assertTrue(!displayReply.isError, "supported display request should not be an error reply");
		assertTrue(displayReply.payload.indexOf("diagnostics") >= 0, "display response should come from the shared dispatcher");

		assertEquals(CompilationServerRequestCodec.encodeSocketReply(new CompilationServerReply("plain", false)), "plain", "socket success encoding");
		final encodedError = CompilationServerRequestCodec.encodeSocketReply(new CompilationServerReply("failed", true));
		assertTrue(encodedError.length > 0 && encodedError.charCodeAt(0) == 0x02, "socket error encoding should use Haxe's error control byte");
		assertEquals(encodedError.substr(1), "failed", "socket error payload");
	}
}
