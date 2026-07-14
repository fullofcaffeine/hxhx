import haxe.crypto.Sha256;
import hxhxmacrohost.NativeMacroModuleReceipt;
import sys.FileSystem;
import sys.io.File;

class M14NativeMacroModuleReceiptIntegrationTest {
	static function assertEq(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ": expected `" + expected + "`, got `" + actual + "`";
	}

	static function expectFailure(label:String, run:Void->Void, expectedMessage:String):Void {
		try {
			run();
		} catch (error:Dynamic) {
			final message = Std.string(error);
			if (message.indexOf(expectedMessage) == -1)
				throw label + ": expected error containing `" + expectedMessage + "`, got `" + message + "`";
			return;
		}
		throw label + ": expected failure";
	}

	static function digest(path:String):String {
		return Sha256.make(File.getBytes(path)).toHex().toLowerCase();
	}

	static function writeReceipt(path:String, candidate:String, nativePath:String, bytecodePath:String, ?nativeDigest:String):Void {
		final receipt = {
			schema: NativeMacroModuleReceipt.SCHEMA,
			candidateCommit: candidate,
			pluginId: "fixture.project.macro",
			abiVersion: 1,
			macroApiVersion: 1,
			expressions: ["projectmacro.ProjectMacro.message()"],
			artifacts: {
				native: {path: "native.cmxs", sha256: nativeDigest == null ? digest(nativePath) : nativeDigest},
				bytecode: {path: "bytecode.cma", sha256: digest(bytecodePath)}
			}
		};
		File.saveContent(path, haxe.Json.stringify(receipt, null, "  ") + "\n");
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
