package hxhxmacrohost;

import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Validates the receipt that binds a generated project-macro plugin to one `hxhx` candidate.

	The receipt is deliberately small: it identifies the candidate, ABI, exact expressions, and
	plugin digest. Both in-process and external-host macro modes call this validator before loading
	the same artifact. A receipt is optional; once selected through the environment, every missing
	or mismatched field is a hard error rather than a fallback to stage0.
**/
class NativeMacroModuleReceipt {
	public static inline final SCHEMA:String = "hxhx.native-macro-module.v1";
	public static inline final RECEIPT_ENV:String = "HXHX_NATIVE_MACRO_MODULE_RECEIPT";
	public static inline final CANDIDATE_ENV:String = "HXHX_CANDIDATE_COMMIT";
	public static inline final NATIVE_ARTIFACT:String = "native";
	public static inline final BYTECODE_ARTIFACT:String = "bytecode";

	static function fail(message:String):Dynamic {
		throw "native macro module receipt: " + message;
	}

	static function requiredString(value:Dynamic, field:String):String {
		if (value == null)
			return fail(field + " is required");
		final out = StringTools.trim(Std.string(value));
		if (out.length == 0)
			return fail(field + " is required");
		return out;
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		if (value == null)
			return fail(field + " is required");
		final parsed = Std.parseInt(Std.string(value));
		if (parsed == null)
			return fail(field + " must be an integer");
		return parsed;
	}

	static function requiredField(value:Dynamic, field:String):Dynamic {
		if (value == null || !Reflect.hasField(value, field))
			return fail(field + " is required");
		return Reflect.field(value, field);
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
			return fail("artifact.path escapes the receipt directory");
		return artifactPath;
	}

	static function normalizeDigest(value:String):String {
		final digest = value.toLowerCase();
		if (digest.length != 64)
			return fail("artifact.sha256 must contain 64 hexadecimal characters");
		for (idx in 0...digest.length) {
			final code = digest.charCodeAt(idx);
			if (!(code >= 48 && code <= 57 || code >= 97 && code <= 102))
				return fail("artifact.sha256 must contain 64 hexadecimal characters");
		}
		return digest;
	}

	static function decodeExpressions(value:Dynamic):Array<String> {
		if (value == null)
			return fail("expressions must be an array");
		final raw:Array<Dynamic> = try {
			cast value;
		} catch (_:Dynamic) {
			return fail("expressions must be an array");
		}
		if (raw.length == 0)
			return fail("expressions must contain at least one exact macro call");
		final out = new Array<String>();
		for (entry in raw) {
			final expr = requiredString(entry, "expressions[]");
			if (out.indexOf(expr) != -1)
				return fail("duplicate expression `" + expr + "`");
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
			return fail("file not found: " + selectedPath);
		final receiptPath = Path.normalize(FileSystem.fullPath(selectedPath));

		final decoded:Dynamic = try {
			haxe.Json.parse(File.getContent(receiptPath));
		} catch (error:Dynamic) {
			return fail("invalid JSON in `" + receiptPath + "`: " + Std.string(error));
		}
		if (decoded == null)
			return fail("receipt JSON must be an object");

		final schema = requiredString(requiredField(decoded, "schema"), "schema");
		if (schema != SCHEMA)
			return fail("unsupported schema `" + schema + "` (expected `" + SCHEMA + "`)");
		final candidateCommit = requiredString(requiredField(decoded, "candidateCommit"), "candidateCommit");
		final expectedCandidate = requiredString(Sys.getEnv(CANDIDATE_ENV), CANDIDATE_ENV);
		if (candidateCommit != expectedCandidate)
			return fail("candidate mismatch: receipt has `" + candidateCommit + "`, current compiler expects `" + expectedCandidate + "`");
		final pluginId = requiredString(requiredField(decoded, "pluginId"), "pluginId");
		final abiVersion = requiredInt(requiredField(decoded, "abiVersion"), "abiVersion");
		if (abiVersion != NativeMacroModuleAbi.ABI_VERSION)
			return fail("abiVersion mismatch: expected " + NativeMacroModuleAbi.ABI_VERSION + ", got " + abiVersion);
		final macroApiVersion = requiredInt(requiredField(decoded, "macroApiVersion"), "macroApiVersion");
		if (macroApiVersion != NativeMacroModuleAbi.MACRO_API_VERSION)
			return fail("macroApiVersion mismatch: expected " + NativeMacroModuleAbi.MACRO_API_VERSION + ", got " + macroApiVersion);
		final expressions = decodeExpressions(requiredField(decoded, "expressions"));

		final selectedArtifactKind = StringTools.trim(artifactKind == null ? "" : artifactKind);
		if (selectedArtifactKind != NATIVE_ARTIFACT && selectedArtifactKind != BYTECODE_ARTIFACT)
			return fail("unsupported artifact kind `" + selectedArtifactKind + "`");
		final artifacts:Dynamic = requiredField(decoded, "artifacts");
		final artifact:Dynamic = requiredField(artifacts, selectedArtifactKind);
		final artifactField = "artifacts." + selectedArtifactKind;
		final artifactRelativePath = requiredString(requiredField(artifact, "path"), artifactField + ".path");
		final expectedDigest = normalizeDigest(requiredString(requiredField(artifact, "sha256"), artifactField + ".sha256"));
		final artifactPath = resolveContainedArtifact(receiptPath, artifactRelativePath);
		if (!FileSystem.exists(artifactPath) || FileSystem.isDirectory(artifactPath))
			return fail("artifact file not found: " + artifactPath);
		final actualDigest = Sha256.make(File.getBytes(artifactPath)).toHex().toLowerCase();
		if (actualDigest != expectedDigest)
			return fail("artifact SHA-256 mismatch: expected " + expectedDigest + ", got " + actualDigest);

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
