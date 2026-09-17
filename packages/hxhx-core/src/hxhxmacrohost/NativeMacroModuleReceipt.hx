package hxhxmacrohost;

import haxe.crypto.Sha256;
import haxe.io.Path;
import hxhx.CompilerJsonParser;
import hxhx.CompilerJsonValue;
import sys.FileSystem;
import sys.io.File;

/**
	Validates the receipt that binds a generated project-macro plugin to one `hxhx` candidate.

	The receipt is deliberately small: it identifies the candidate, ABI, exact expressions, and
	plugin digest. Both in-process and external-host macro modes call this validator before loading
	the same artifact. A receipt is optional; once selected through the environment, every missing
	or mismatched field is a hard error rather than a fallback to stage0.
	JSON strings and integer-valued version numbers are checked before artifact selection;
	other value kinds are not coerced into identifiers, macro calls, paths, or versions.
**/
class NativeMacroModuleReceipt {
	public static inline final SCHEMA:String = "hxhx.native-macro-module.v1";
	public static inline final RECEIPT_ENV:String = "HXHX_NATIVE_MACRO_MODULE_RECEIPT";
	public static inline final CANDIDATE_ENV:String = "HXHX_CANDIDATE_COMMIT";
	public static inline final NATIVE_ARTIFACT:String = "native";
	public static inline final BYTECODE_ARTIFACT:String = "bytecode";

	/** Formats the exact String payload used by every receipt-validation failure. */
	static function failureMessage(message:String):String {
		return "native macro module receipt: " + message;
	}

	static function requiredText(value:Null<String>, field:String):String {
		if (value == null)
			throw failureMessage(field + " is required");
		final out = StringTools.trim(value);
		if (out.length == 0)
			throw failureMessage(field + " is required");
		return out;
	}

	static function requiredString(value:CompilerJsonValue, field:String):String {
		return switch (value) {
			case JsonString(text): requiredText(text, field);
			case JsonNull: throw failureMessage(field + " is required");
			case _: throw failureMessage(field + " must be a string");
		}
	}

	static function requiredInt(value:CompilerJsonValue, field:String):Int {
		switch (value) {
			case JsonNull:
				throw failureMessage(field + " is required");
			case JsonInt(number):
				return number;
			case JsonFloat(number):
				final integer = Std.int(number);
				final asFloat:Float = integer;
				if (asFloat == number)
					return integer;
			case _:
		}
		throw failureMessage(field + " must be an integer");
	}

	static function requiredField(value:CompilerJsonValue, field:String):CompilerJsonValue {
		return switch (value) {
			case JsonObject(fields):
				if (!fields.exists(field))
					throw failureMessage(field + " is required");
				fields.get(field);
			case _: throw failureMessage(field + " is required");
		}
	}

	static function normalizeDirectory(path:String):String {
		final normalized = Path.normalize(FileSystem.fullPath(path));
		if (StringTools.endsWith(normalized, "/") || StringTools.endsWith(normalized, "\\"))
			return normalized.substr(0, normalized.length - 1);
		return normalized;
	}

	static function resolveContainedArtifact(receiptPath:String, artifactRelativePath:String):String {
		final receiptDirectory = normalizeDirectory(Path.directory(receiptPath));
		final artifactPath = Path.normalize(Path.join([receiptDirectory, artifactRelativePath]));
		final slashPrefix = receiptDirectory + "/";
		final backslashPrefix = receiptDirectory + "\\";
		if (artifactPath != receiptDirectory
			&& !StringTools.startsWith(artifactPath, slashPrefix)
			&& !StringTools.startsWith(artifactPath, backslashPrefix))
			throw failureMessage("artifact.path escapes the receipt directory");
		return artifactPath;
	}

	static function normalizeDigest(value:String):String {
		final digest = value.toLowerCase();
		if (digest.length != 64)
			throw failureMessage("artifact.sha256 must contain 64 hexadecimal characters");
		for (idx in 0...digest.length) {
			final code = digest.charCodeAt(idx);
			if (!(code >= 48 && code <= 57 || code >= 97 && code <= 102))
				throw failureMessage("artifact.sha256 must contain 64 hexadecimal characters");
		}
		return digest;
	}

	static function decodeExpressions(value:CompilerJsonValue):Array<String> {
		final raw = switch (value) {
			case JsonArray(values): values;
			case _: throw failureMessage("expressions must be an array");
		}
		if (raw.length == 0)
			throw failureMessage("expressions must contain at least one exact macro call");
		final out = new Array<String>();
		for (entry in raw) {
			final expr = requiredString(entry, "expressions[]");
			if (out.indexOf(expr) != -1)
				throw failureMessage("duplicate expression `" + expr + "`");
			out.push(expr);
		}
		return out;
	}

	/**
		Load the optional receipt selected by the process environment.

		Returns `null` when no project macro module was requested. When requested, validation includes
		candidate identity, ABI/API versions, path containment, file existence, and SHA-256 content.
	**/
	public static function loadFromEnvironment(artifactKind:String):Null<NativeMacroModuleActivation> {
		final configuredPath = Sys.getEnv(RECEIPT_ENV);
		if (configuredPath == null || StringTools.trim(configuredPath).length == 0)
			return null;

		final selectedPath = Path.normalize(StringTools.trim(configuredPath));
		if (!FileSystem.exists(selectedPath) || FileSystem.isDirectory(selectedPath))
			throw failureMessage("file not found: " + selectedPath);
		final receiptPath = Path.normalize(FileSystem.fullPath(selectedPath));

		final decoded = try {
			CompilerJsonParser.parse(File.getContent(receiptPath));
		} catch (error:haxe.Exception) {
			throw failureMessage("invalid JSON in `" + receiptPath + "`: " + error.message);
		}
		switch (decoded) {
			case JsonObject(_):
			case _:
				throw failureMessage("receipt JSON must be an object");
		}

		final schema = requiredString(requiredField(decoded, "schema"), "schema");
		if (schema != SCHEMA)
			throw failureMessage("unsupported schema `" + schema + "` (expected `" + SCHEMA + "`)");
		final candidateCommit = requiredString(requiredField(decoded, "candidateCommit"), "candidateCommit");
		final expectedCandidate = requiredText(Sys.getEnv(CANDIDATE_ENV), CANDIDATE_ENV);
		if (candidateCommit != expectedCandidate)
			throw failureMessage("candidate mismatch: receipt has `" + candidateCommit + "`, current compiler expects `" + expectedCandidate + "`");
		final pluginId = requiredString(requiredField(decoded, "pluginId"), "pluginId");
		final abiVersion = requiredInt(requiredField(decoded, "abiVersion"), "abiVersion");
		if (abiVersion != NativeMacroModuleAbi.ABI_VERSION)
			throw failureMessage("abiVersion mismatch: expected " + NativeMacroModuleAbi.ABI_VERSION + ", got " + abiVersion);
		final macroApiVersion = requiredInt(requiredField(decoded, "macroApiVersion"), "macroApiVersion");
		if (macroApiVersion != NativeMacroModuleAbi.MACRO_API_VERSION)
			throw failureMessage("macroApiVersion mismatch: expected " + NativeMacroModuleAbi.MACRO_API_VERSION + ", got " + macroApiVersion);
		final expressions = decodeExpressions(requiredField(decoded, "expressions"));

		final selectedArtifactKind = StringTools.trim(artifactKind == null ? "" : artifactKind);
		if (selectedArtifactKind != NATIVE_ARTIFACT && selectedArtifactKind != BYTECODE_ARTIFACT)
			throw failureMessage("unsupported artifact kind `" + selectedArtifactKind + "`");
		final artifacts = requiredField(decoded, "artifacts");
		final artifact = requiredField(artifacts, selectedArtifactKind);
		final artifactField = "artifacts." + selectedArtifactKind;
		final artifactRelativePath = requiredString(requiredField(artifact, "path"), artifactField + ".path");
		final expectedDigest = normalizeDigest(requiredString(requiredField(artifact, "sha256"), artifactField + ".sha256"));
		final artifactPath = resolveContainedArtifact(receiptPath, artifactRelativePath);
		if (!FileSystem.exists(artifactPath) || FileSystem.isDirectory(artifactPath))
			throw failureMessage("artifact file not found: " + artifactPath);
		final actualDigest = Sha256.make(File.getBytes(artifactPath)).toHex().toLowerCase();
		if (actualDigest != expectedDigest)
			throw failureMessage("artifact SHA-256 mismatch: expected " + expectedDigest + ", got " + actualDigest);

		return {
			candidateCommit: candidateCommit,
			pluginId: pluginId,
			expressions: expressions,
			artifactKind: selectedArtifactKind,
			artifactPath: artifactPath,
			artifactSha256: actualDigest
		};
	}
}
