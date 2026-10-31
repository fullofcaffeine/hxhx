package hxhxmacrohost;

import haxe.crypto.Sha256;
import haxe.io.Path;
import hxhx.CompilerJsonParser;
import hxhx.CompilerJsonValue;
import sys.FileSystem;
import sys.io.File;

/** One file the receipt binds by content: an artifact (relative path) or a macro source (absolute path). */
typedef NativeMacroModuleFile = {
	final path:String;
	final sha256:String;
}

/** The OCaml tools that built a plugin; recorded as build evidence. */
typedef NativeMacroModuleToolchain = {
	/** `ocamlopt -version`; it must equal the compiler binary's own OCaml version. */
	final ocaml:String;

	final dune:String;

	/** SHA-256 of `ocamlopt -config`, which names the architecture, flags, and configuration. */
	final ocamlConfigSha256:String;
}

/** Everything a receipt records about one built project-macro plugin. */
typedef NativeMacroModuleReceiptData = {
	final cacheKey:String;
	final compilerIdentity:String;
	final pluginId:String;
	final declarations:Array<String>;
	final toolchain:NativeMacroModuleToolchain;
	final runtimeDigest:String;

	/** Every source file the plugin compilation read, with its content digest. */
	final sources:Array<NativeMacroModuleFile>;

	final native:NativeMacroModuleFile;
	final bytecode:NativeMacroModuleFile;
}

/** What the loading compiler requires of a receipt before it trusts the plugin it names. */
typedef NativeMacroModuleExpectation = {
	final cacheKey:String;
	final compilerIdentity:String;
	final ocamlVersion:String;
	final runtimeDigest:String;
	final declarations:Array<String>;
}

/**
	Writes and validates the receipt that binds a project-macro plugin to one compiler binary.

	Why
	- hxhx builds a project's macro classes into a native plugin and caches it. Loading a plugin
	  runs its code inside the compiler, so the compiler must prove, before loading, that the
	  cached files are exactly the ones it built for the current inputs. The receipt is that proof.
	- A stale or foreign plugin must never load. Every mismatch below is a hard rejection; the
	  cache (`hxhx.macro.ProjectMacroPluginCache`) then rebuilds or reports the failure. It never
	  falls back to an installed Haxe compiler.

	What (schema `hxhx.native-macro-module.v3`)
	- `cacheKey`: the digest of every build input the cache can name before building (compiler
	  identity, ABI versions, declarations, classpaths, defines, OCaml version, runtime digest).
	- `compilerIdentity`: the digest of the hxhx executable that built the plugin.
	- `abiVersion` and `macroApiVersion`: `NativeMacroModuleAbi` constants.
	- `declarations`: the registered `pack.Type.method` keys, in registration order.
	- `toolchain`: the OCaml and dune versions and the `ocamlopt -config` digest.
	- `runtimeDigest`: the digest of the OCaml runtime and shim sources the plugin was built with.
	- `sources`: every Haxe source file the plugin compilation read (absolute path and SHA-256).
	  Editing any of them invalidates the plugin.
	- `artifacts.native` and `artifacts.bytecode`: the `.cmxs` and `.cma` files, as paths inside
	  the receipt directory, with SHA-256 digests.

	How
	- `encode` writes JSON text without reflection. `validate` reads the receipt through
	  `CompilerJsonParser`, checks every field against the expectation and the files on disk, and
	  returns the activation for the requested artifact kind. JSON strings and integer-valued
	  numbers are checked before use; other value kinds are never coerced.
**/
class NativeMacroModuleReceipt {
	public static inline final SCHEMA:String = "hxhx.native-macro-module.v3";
	public static inline final NATIVE_ARTIFACT:String = "native";
	public static inline final BYTECODE_ARTIFACT:String = "bytecode";

	/** Formats the exact String payload used by every receipt-validation failure. */
	static function failureMessage(message:String):String {
		return "native macro module receipt: " + message;
	}

	/** Render a receipt as JSON text; the format is stable so receipts can be diffed. */
	public static function encode(data:NativeMacroModuleReceiptData):String {
		final out = new StringBuf();
		function file(value:NativeMacroModuleFile):String
			return '{"path": ' + quote(value.path) + ', "sha256": ' + quote(value.sha256) + "}";
		out.add("{\n");
		out.add('  "schema": ' + quote(SCHEMA) + ",\n");
		out.add('  "cacheKey": ' + quote(data.cacheKey) + ",\n");
		out.add('  "compilerIdentity": ' + quote(data.compilerIdentity) + ",\n");
		out.add('  "pluginId": ' + quote(data.pluginId) + ",\n");
		out.add('  "abiVersion": ' + NativeMacroModuleAbi.ABI_VERSION + ",\n");
		out.add('  "macroApiVersion": ' + NativeMacroModuleAbi.MACRO_API_VERSION + ",\n");
		out.add('  "declarations": [' + [for (declaration in data.declarations) quote(declaration)].join(", ") + "],\n");
		out.add('  "toolchain": {"ocaml": ' + quote(data.toolchain.ocaml) + ', "dune": ' + quote(data.toolchain.dune) + ', "ocamlConfigSha256": '
			+ quote(data.toolchain.ocamlConfigSha256) + "},\n");
		out.add('  "runtimeDigest": ' + quote(data.runtimeDigest) + ",\n");
		out.add('  "sources": [\n');
		out.add([for (source in data.sources) "    " + file(source)].join(",\n"));
		out.add("\n  ],\n");
		out.add('  "artifacts": {\n    "native": ' + file(data.native) + ',\n    "bytecode": ' + file(data.bytecode) + "\n  }\n");
		out.add("}\n");
		return out.toString();
	}

	/** SHA-256 of a file's bytes, in lower-case hexadecimal. */
	public static function fileSha256(path:String):String {
		return Sha256.make(File.getBytes(path)).toHex().toLowerCase();
	}

	/**
		Validate the receipt at `receiptPath` against `expected` and the files it names.

		Returns the activation for `artifactKind` (`native` or `bytecode`). Throws a String that
		starts with `native macro module receipt:` on the first mismatch.
	**/
	public static function validate(receiptPath:String, expected:NativeMacroModuleExpectation, artifactKind:String):NativeMacroModuleActivation {
		final selectedPath = Path.normalize(StringTools.trim(receiptPath == null ? "" : receiptPath));
		if (selectedPath.length == 0 || !FileSystem.exists(selectedPath) || FileSystem.isDirectory(selectedPath))
			throw failureMessage("file not found: " + selectedPath);
		final resolvedPath = Path.normalize(FileSystem.fullPath(selectedPath));
		final decoded = try {
			CompilerJsonParser.parse(File.getContent(resolvedPath));
		} catch (error:haxe.Exception) {
			throw failureMessage("invalid JSON in `" + resolvedPath + "`: " + error.message);
		}
		switch (decoded) {
			case JsonObject(_):
			case _:
				throw failureMessage("receipt JSON must be an object");
		}

		final schema = requiredString(requiredField(decoded, "schema"), "schema");
		if (schema != SCHEMA)
			throw failureMessage("unsupported schema `" + schema + "` (expected `" + SCHEMA + "`)");
		final abiVersion = requiredInt(requiredField(decoded, "abiVersion"), "abiVersion");
		if (abiVersion != NativeMacroModuleAbi.ABI_VERSION)
			throw failureMessage("abiVersion mismatch: expected " + NativeMacroModuleAbi.ABI_VERSION + ", got " + abiVersion);
		final macroApiVersion = requiredInt(requiredField(decoded, "macroApiVersion"), "macroApiVersion");
		if (macroApiVersion != NativeMacroModuleAbi.MACRO_API_VERSION)
			throw failureMessage("macroApiVersion mismatch: expected " + NativeMacroModuleAbi.MACRO_API_VERSION + ", got " + macroApiVersion);
		requireEqual("cacheKey", requiredString(requiredField(decoded, "cacheKey"), "cacheKey"), expected.cacheKey);
		requireEqual("compilerIdentity", requiredString(requiredField(decoded, "compilerIdentity"), "compilerIdentity"), expected.compilerIdentity);
		final toolchain = requiredField(decoded, "toolchain");
		requireEqual("toolchain.ocaml", requiredString(requiredField(toolchain, "ocaml"), "toolchain.ocaml"), expected.ocamlVersion);
		requiredString(requiredField(toolchain, "dune"), "toolchain.dune");
		normalizeDigest(requiredString(requiredField(toolchain, "ocamlConfigSha256"), "toolchain.ocamlConfigSha256"), "toolchain.ocamlConfigSha256");
		requireEqual("runtimeDigest", requiredString(requiredField(decoded, "runtimeDigest"), "runtimeDigest"), expected.runtimeDigest);
		final pluginId = requiredString(requiredField(decoded, "pluginId"), "pluginId");
		final declarations = decodeDeclarations(requiredField(decoded, "declarations"));
		if (declarations.join(",") != expected.declarations.join(","))
			throw failureMessage("registered declaration mismatch: receipt has `" + declarations.join(",") + "`, the compile needs `"
				+ expected.declarations.join(",") + "`");

		final sources = requiredArray(requiredField(decoded, "sources"), "sources");
		if (sources.length == 0)
			throw failureMessage("sources must list the macro sources the plugin was built from");
		for (source in sources) {
			final path = requiredString(requiredField(source, "path"), "sources[].path");
			final digest = normalizeDigest(requiredString(requiredField(source, "sha256"), "sources[].sha256"), "sources[].sha256");
			if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
				throw failureMessage("macro source no longer exists: " + path);
			if (fileSha256(path) != digest)
				throw failureMessage("macro source changed since the plugin was built: " + path);
		}

		final selectedArtifactKind = StringTools.trim(artifactKind == null ? "" : artifactKind);
		if (selectedArtifactKind != NATIVE_ARTIFACT && selectedArtifactKind != BYTECODE_ARTIFACT)
			throw failureMessage("unsupported artifact kind `" + selectedArtifactKind + "`");
		final artifact = requiredField(requiredField(decoded, "artifacts"), selectedArtifactKind);
		final artifactField = "artifacts." + selectedArtifactKind;
		final artifactRelativePath = requiredString(requiredField(artifact, "path"), artifactField + ".path");
		final expectedDigest = normalizeDigest(requiredString(requiredField(artifact, "sha256"), artifactField + ".sha256"), artifactField + ".sha256");
		final artifactPath = resolveContainedArtifact(resolvedPath, artifactRelativePath);
		if (!FileSystem.exists(artifactPath) || FileSystem.isDirectory(artifactPath))
			throw failureMessage("artifact file not found: " + artifactPath);
		final actualDigest = fileSha256(artifactPath);
		if (actualDigest != expectedDigest)
			throw failureMessage("artifact SHA-256 mismatch: expected " + expectedDigest + ", got " + actualDigest);

		return {
			cacheKey: expected.cacheKey,
			pluginId: pluginId,
			declarations: declarations,
			artifactKind: selectedArtifactKind,
			artifactPath: artifactPath,
			artifactSha256: actualDigest
		};
	}

	static function requireEqual(field:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw failureMessage(field + " mismatch: receipt has `" + actual + "`, the current compile needs `" + expected + "`");
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

	static function requiredArray(value:CompilerJsonValue, field:String):Array<CompilerJsonValue> {
		return switch (value) {
			case JsonArray(values): values;
			case _: throw failureMessage(field + " must be an array");
		}
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

	static function normalizeDigest(value:String, field:String):String {
		final digest = value.toLowerCase();
		if (digest.length != 64)
			throw failureMessage(field + " must contain 64 hexadecimal characters");
		for (idx in 0...digest.length) {
			final code = digest.charCodeAt(idx);
			if (!(code >= 48 && code <= 57 || code >= 97 && code <= 102))
				throw failureMessage(field + " must contain 64 hexadecimal characters");
		}
		return digest;
	}

	static function decodeDeclarations(value:CompilerJsonValue):Array<String> {
		final raw = switch (value) {
			case JsonArray(values): values;
			case _: throw failureMessage("declarations must be an array");
		}
		if (raw.length == 0)
			throw failureMessage("declarations must contain at least one macro declaration");
		final out = new Array<String>();
		for (entry in raw) {
			final declaration = requiredString(entry, "declarations[]");
			if (out.indexOf(declaration) != -1)
				throw failureMessage("duplicate declaration `" + declaration + "`");
			out.push(declaration);
		}
		return out;
	}

	/** A JSON string literal; every control character is escaped. */
	static function quote(text:String):String {
		final out = new StringBuf();
		out.add("\"");
		for (index in 0...text.length) {
			final code = text.charCodeAt(index);
			switch (code) {
				case 34:
					out.add("\\\"");
				case 92:
					out.add("\\\\");
				case 10:
					out.add("\\n");
				case 13:
					out.add("\\r");
				case 9:
					out.add("\\t");
				case _ if (code < 32):
					out.add("\\u" + StringTools.hex(code, 4));
				case _:
					out.add(String.fromCharCode(code));
			}
		}
		out.add("\"");
		return out.toString();
	}
}
