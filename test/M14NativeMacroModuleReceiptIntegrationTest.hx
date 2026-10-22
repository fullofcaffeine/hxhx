import haxe.crypto.Sha256;
import hxhxmacrohost.NativeMacroModuleReceipt;
import sys.FileSystem;
import sys.io.File;

/** Validates receipt kinds and artifact identity before a macro plugin can load. */
class M14NativeMacroModuleReceiptIntegrationTest {
	static function assertEq(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ": expected `" + expected + "`, got `" + actual + "`";
	}

	static function expectFailure(label:String, run:Void->Void, expectedMessage:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			final message = error.message;
			if (message.indexOf(expectedMessage) == -1)
				throw label + ": expected error containing `" + expectedMessage + "`, got `" + message + "`";
			return;
		}
		throw label + ": expected failure";
	}

	static function digest(path:String):String {
		return Sha256.make(File.getBytes(path)).toHex().toLowerCase();
	}

	/**
		Writes literal parser input without importing a JSON serializer or its parser.
		Candidate names are fixed test tokens; digest values contain hexadecimal digits.
	**/
	static function writeReceipt(path:String, candidate:String, nativePath:String, bytecodePath:String, ?nativeDigest:String):Void {
		final selectedDigest = nativeDigest == null ? digest(nativePath) : nativeDigest;
		final receipt = '{"schema":"hxhx.native-macro-module.v1","candidateCommit":"'
			+ candidate
			+ '","pluginId":"fixture.project.macro","abiVersion":1,"macroApiVersion":1,'
			+ '"expressions":["projectmacro.ProjectMacro.message()"],"artifacts":{'
			+ '"native":{"path":"native.cmxs","sha256":"'
			+ selectedDigest
			+ '"},'
			+ '"bytecode":{"path":"bytecode.cma","sha256":"'
			+ digest(bytecodePath)
			+ '"}}}';
		File.saveContent(path, receipt + "\n");
	}

	/** Changes one input token so malformed metadata is checked through the public loader. */
	static function expectInvalidField(path:String, validReceipt:String, change:{
		field:String,
		original:String,
		replacement:String,
		error:String
	}):Void {
		final original = '"' + change.field + '":' + change.original;
		if (validReceipt.indexOf(original) == -1)
			throw "fixture token missing: " + original;
		File.saveContent(path, StringTools.replace(validReceipt, original, '"' + change.field + '":' + change.replacement));
		expectFailure(change.field, () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT), change.error);
	}

	static function main():Void {
		final root = ".tmp/m14-native-macro-receipt-" + Std.string(Std.int(haxe.Timer.stamp() * 1000000));
		FileSystem.createDirectory(root);
		final receiptPath = root + "/receipt.json";
		final nativePath = root + "/native.cmxs";
		final bytecodePath = root + "/bytecode.cma";
		File.saveContent(nativePath, "native-fixture");
		File.saveContent(bytecodePath, "bytecode-fixture");
		writeReceipt(receiptPath, "candidate-ok", nativePath, bytecodePath);

		final oldReceipt = Sys.getEnv(NativeMacroModuleReceipt.RECEIPT_ENV);
		final oldCandidate = Sys.getEnv(NativeMacroModuleReceipt.CANDIDATE_ENV);
		Sys.putEnv(NativeMacroModuleReceipt.RECEIPT_ENV, receiptPath);
		Sys.putEnv(NativeMacroModuleReceipt.CANDIDATE_ENV, "candidate-ok");

		final native = NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT);
		assertEq("native artifact kind", native.artifactKind, NativeMacroModuleReceipt.NATIVE_ARTIFACT);
		assertEq("native artifact path", native.artifactPath, FileSystem.fullPath(nativePath));
		final bytecode = NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.BYTECODE_ARTIFACT);
		assertEq("bytecode artifact kind", bytecode.artifactKind, NativeMacroModuleReceipt.BYTECODE_ARTIFACT);
		assertEq("bytecode artifact path", bytecode.artifactPath, FileSystem.fullPath(bytecodePath));

		final validReceipt = File.getContent(receiptPath);
		for (token in ["1.5", '"1suffix"', "true", "[]", "{}"]) {
			expectInvalidField(receiptPath, validReceipt, {
				field: "abiVersion",
				original: "1",
				replacement: token,
				error: "abiVersion must be an integer"
			});
		}
		expectInvalidField(receiptPath, validReceipt, {
			field: "pluginId",
			original: '"fixture.project.macro"',
			replacement: "true",
			error: "pluginId must be a string"
		});
		expectInvalidField(receiptPath, validReceipt, {
			field: "expressions",
			original: '["projectmacro.ProjectMacro.message()"]',
			replacement: "[7]",
			error: "expressions[] must be a string"
		});
		expectInvalidField(receiptPath, validReceipt, {
			field: "abiVersion",
			original: "1",
			replacement: "null",
			error: "abiVersion is required"
		});
		// JSON fraction/exponent syntax remains valid when its value is an exact integer.
		File.saveContent(receiptPath, StringTools.replace(validReceipt, '"abiVersion":1', '"abiVersion":1e0'));
		assertEq("integral exponent receipt", NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT).pluginId,
			"fixture.project.macro");

		File.saveContent(receiptPath, "{");
		expectFailure("invalid JSON", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT), "invalid JSON");
		File.saveContent(receiptPath, "true\n");
		expectFailure("non-object JSON", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT),
			"receipt JSON must be an object");
		writeReceipt(receiptPath, "candidate-ok", nativePath, bytecodePath);

		Sys.putEnv(NativeMacroModuleReceipt.CANDIDATE_ENV, "candidate-other");
		expectFailure("candidate mismatch", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT), "candidate mismatch");
		Sys.putEnv(NativeMacroModuleReceipt.CANDIDATE_ENV, "candidate-ok");
		writeReceipt(receiptPath, "candidate-ok", nativePath, bytecodePath, StringTools.lpad("0", "0", 64));
		expectFailure("digest mismatch", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT),
			"artifact SHA-256 mismatch");
		FileSystem.deleteFile(nativePath);
		expectFailure("missing artifact", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT),
			"artifact file not found");
		Sys.putEnv(NativeMacroModuleReceipt.RECEIPT_ENV, root + "/missing-receipt.json");
		expectFailure("missing receipt", () -> NativeMacroModuleReceipt.loadFromEnvironment(NativeMacroModuleReceipt.NATIVE_ARTIFACT), "file not found");

		Sys.putEnv(NativeMacroModuleReceipt.RECEIPT_ENV, oldReceipt);
		Sys.putEnv(NativeMacroModuleReceipt.CANDIDATE_ENV, oldCandidate);
		FileSystem.deleteFile(bytecodePath);
		FileSystem.deleteFile(receiptPath);
		FileSystem.deleteDirectory(root);
		Sys.println("OK m14 native macro module receipt");
	}
}
