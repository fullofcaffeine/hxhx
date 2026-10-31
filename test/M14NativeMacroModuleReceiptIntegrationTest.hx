import hxhxmacrohost.NativeMacroModuleReceipt;
import hxhxmacrohost.NativeMacroModuleReceipt.NativeMacroModuleExpectation;
import sys.FileSystem;
import sys.io.File;

/**
	A project-macro plugin receipt must match the loading compiler before its plugin can load.

	The receipt (`hxhx.native-macro-module.v3`) is written by `NativeMacroModuleReceipt.encode` and
	checked by `NativeMacroModuleReceipt.validate`. Each case below changes one input, through the
	public validator, and requires the named rejection: field kinds, schema and ABI versions
	(including the removed version 1), the cache key, compiler identity, OCaml version, runtime
	digest, declarations, an edited or deleted macro source, a changed or missing artifact, and an
	artifact path that leaves the receipt directory.
**/
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

	static final digestA = StringTools.lpad("", "a", 64);

	static function main():Void {
		final root = FileSystem.fullPath(".tmp") + "/m14-native-macro-receipt-" + Std.string(Std.int(haxe.Timer.stamp() * 1000000));
		FileSystem.createDirectory(root + "/build");
		final receiptPath = root + "/receipt.json";
		final nativePath = root + "/build/native.cmxs";
		final bytecodePath = root + "/build/bytecode.cma";
		final sourcePath = root + "/Identity.hx";
		File.saveContent(nativePath, "native-fixture");
		File.saveContent(bytecodePath, "bytecode-fixture");
		File.saveContent(sourcePath, "class Identity {}\n");

		function receipt(?nativeDigest:String):String {
			return NativeMacroModuleReceipt.encode({
				cacheKey: digestA,
				compilerIdentity: "compiler-ok",
				pluginId: "hxhx.project-macro.fixture",
				declarations: ["Identity.preserve"],
				toolchain: {ocaml: "5.4.0", dune: "3.21.0", ocamlConfigSha256: digestA},
				runtimeDigest: "runtime-ok",
				sources: [{path: sourcePath, sha256: NativeMacroModuleReceipt.fileSha256(sourcePath)}],
				native: {path: "build/native.cmxs", sha256: nativeDigest == null ? NativeMacroModuleReceipt.fileSha256(nativePath) : nativeDigest},
				bytecode: {path: "build/bytecode.cma", sha256: NativeMacroModuleReceipt.fileSha256(bytecodePath)}
			});
		}
		final expected:NativeMacroModuleExpectation = {
			cacheKey: digestA,
			compilerIdentity: "compiler-ok",
			ocamlVersion: "5.4.0",
			runtimeDigest: "runtime-ok",
			declarations: ["Identity.preserve"]
		};
		function load(?kind:String)
			return NativeMacroModuleReceipt.validate(receiptPath, expected, kind == null ? NativeMacroModuleReceipt.NATIVE_ARTIFACT : kind);

		final validReceipt = receipt();
		File.saveContent(receiptPath, validReceipt);
		final native = load();
		assertEq("native artifact kind", native.artifactKind, NativeMacroModuleReceipt.NATIVE_ARTIFACT);
		assertEq("native artifact path", native.artifactPath, FileSystem.fullPath(nativePath));
		assertEq("plugin id", native.pluginId, "hxhx.project-macro.fixture");
		final bytecode = load(NativeMacroModuleReceipt.BYTECODE_ARTIFACT);
		assertEq("bytecode artifact path", bytecode.artifactPath, FileSystem.fullPath(bytecodePath));

		/** Change one `"field": original` token of the valid receipt and require the rejection. */
		function invalid(field:String, original:String, replacement:String, error:String):Void {
			final token = '"' + field + '": ' + original;
			if (validReceipt.indexOf(token) == -1)
				throw "fixture token missing: " + token;
			File.saveContent(receiptPath, StringTools.replace(validReceipt, token, '"' + field + '": ' + replacement));
			expectFailure(field + " -> " + replacement, () -> load(), error);
		}
		for (token in ["1.5", '"1suffix"', "true", "[]", "{}"])
			invalid("abiVersion", "2", token, "abiVersion must be an integer");
		invalid("abiVersion", "2", "null", "abiVersion is required");
		// A receipt for the removed version 1 plugin ABI (exact-expression `unit -> string` handlers) is rejected.
		invalid("abiVersion", "2", "1", "abiVersion mismatch: expected 2, got 1");
		invalid("abiVersion", "2", "3", "abiVersion mismatch: expected 2, got 3");
		invalid("schema", '"hxhx.native-macro-module.v3"', '"hxhx.native-macro-module.v2"', "unsupported schema");
		invalid("pluginId", '"hxhx.project-macro.fixture"', "true", "pluginId must be a string");
		invalid("cacheKey", '"' + digestA + '"', '"' + StringTools.lpad("", "b", 64) + '"', "cacheKey mismatch");
		invalid("compilerIdentity", '"compiler-ok"', '"another-compiler"', "compilerIdentity mismatch");
		invalid("ocaml", '"5.4.0"', '"5.3.0"', "toolchain.ocaml mismatch");
		invalid("runtimeDigest", '"runtime-ok"', '"runtime-other"', "runtimeDigest mismatch");
		invalid("declarations", '["Identity.preserve"]', '["Identity.missing"]', "registered declaration mismatch");
		invalid("declarations", '["Identity.preserve"]', "[7]", "declarations[] must be a string");
		invalid("declarations", '["Identity.preserve"]', "[]", "declarations must contain at least one macro declaration");
		invalid("path", '"build/native.cmxs"', '"../escape.cmxs"', "escapes the receipt directory");
		invalid("path", '"build/native.cmxs"', '"build/missing.cmxs"', "artifact file not found");

		// JSON fraction and exponent syntax remains valid when its value is an exact integer.
		File.saveContent(receiptPath, StringTools.replace(validReceipt, '"abiVersion": 2', '"abiVersion": 2e0'));
		assertEq("integral exponent receipt", load().pluginId, "hxhx.project-macro.fixture");

		File.saveContent(receiptPath, "{");
		expectFailure("invalid JSON", () -> load(), "invalid JSON");
		File.saveContent(receiptPath, "true\n");
		expectFailure("non-object JSON", () -> load(), "receipt JSON must be an object");

		File.saveContent(receiptPath, receipt(StringTools.lpad("", "0", 64)));
		expectFailure("digest mismatch", () -> load(), "artifact SHA-256 mismatch");
		File.saveContent(receiptPath, validReceipt);
		File.saveContent(sourcePath, "class Identity { /* edited */ }\n");
		expectFailure("edited source", () -> load(), "macro source changed since the plugin was built");
		FileSystem.deleteFile(sourcePath);
		expectFailure("deleted source", () -> load(), "macro source no longer exists");
		File.saveContent(sourcePath, "class Identity {}\n");
		assertEq("restored source", load().pluginId, "hxhx.project-macro.fixture");
		FileSystem.deleteFile(nativePath);
		expectFailure("missing artifact", () -> load(), "artifact file not found");
		FileSystem.deleteFile(receiptPath);
		expectFailure("missing receipt", () -> load(), "file not found");

		FileSystem.deleteFile(bytecodePath);
		FileSystem.deleteFile(sourcePath);
		FileSystem.deleteDirectory(root + "/build");
		FileSystem.deleteDirectory(root);
		Sys.println("OK m14 native macro module receipt");
	}
}
