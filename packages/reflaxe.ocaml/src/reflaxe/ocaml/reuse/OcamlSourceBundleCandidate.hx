package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.io.Path;
import reflaxe.lifecycle.TargetReuseCatalog;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactClaim;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlSourceBundleSnapshot;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import sys.io.File;

using StringTools;

/** One verified byte range and its plain target-ownership claim. **/
typedef OcamlSourceBundleIndexEntry = {
	final path:String;
	final offset:Int;
	final bytes:Int;
	final sha256:String;
	final kind:String;
	final owner:String;
	final sourceKind:String;
	final sourcePath:Null<String>;
	final license:String;
	final profileEligibility:Array<String>;
	final stability:String;
	final includeInSourceBundle:Bool;
}

/**
	An observation-only, immutable encoding of one complete generated source tree.

	The payload contains a canonical JSON index followed by one contiguous byte
	range for every stable source file. Decoding revalidates paths, ownership,
	offsets, digests, source-bundle identity, and prerequisite authorities. It
	never retains compiler objects, target plans, callbacks, writers, or open
	files.
**/
class OcamlSourceBundleCandidate {
	public static inline final MODEL = "reflaxe-ocaml-source-bundle-candidate";
	public static inline final SCHEMA_VERSION = 1;
	public static inline final ESTIMATED_CATALOG_OVERHEAD_BYTES = 1024;
	static inline final MAGIC = "ROSBC1\n";

	public final targetRequestRevision:String;
	public final programRevision:String;
	public final configurationRevision:String;
	public final profile:String;
	public final sourceBundleRevision:String;
	public final diagnosticsEligible:Bool;
	public final entries:Array<OcamlSourceBundleIndexEntry>;
	public final semanticRuntimeAuthority:OcamlArtifactAuthority;
	public final nativeDependenciesAuthority:OcamlArtifactAuthority;
	public final packedBytes:Int;
	public final indexBytes:Int;
	public final payloadBytes:Int;

	final payload:Bytes;
	final dataOffset:Int;

	function new(payload:Bytes, dataOffset:Int, targetRequestRevision:String, programRevision:String, configurationRevision:String, profile:String,
			sourceBundleRevision:String, diagnosticsEligible:Bool, entries:Array<OcamlSourceBundleIndexEntry>,
			semanticRuntimeAuthority:OcamlArtifactAuthority, nativeDependenciesAuthority:OcamlArtifactAuthority, packedBytes:Int, indexBytes:Int) {
		this.payload = payload;
		this.dataOffset = dataOffset;
		this.targetRequestRevision = targetRequestRevision;
		this.programRevision = programRevision;
		this.configurationRevision = configurationRevision;
		this.profile = profile;
		this.sourceBundleRevision = sourceBundleRevision;
		this.diagnosticsEligible = diagnosticsEligible;
		this.entries = entries;
		this.semanticRuntimeAuthority = semanticRuntimeAuthority;
		this.nativeDependenciesAuthority = nativeDependenciesAuthority;
		this.packedBytes = packedBytes;
		this.indexBytes = indexBytes;
		payloadBytes = payload.length;
	}

	/**
		Packs and then decodes the stable source snapshot.

		The self-decode is intentional: the shadow path must consume the same opaque
		bytes that a future catalog would retain, not an easier request-local object
		graph used only while building the payload.
	**/
	public static function pack(outputDirectory:String, targetRequestRevision:String, snapshot:OcamlSourceBundleSnapshot, diagnosticsEligible:Bool,
			maximumPayloadBytes:Int = TargetReuseCatalog.DEFAULT_MAXIMUM_ENTRY_BYTES):OcamlSourceBundleCandidate {
		if (!snapshot.completeForSourceBundle || snapshot.blockers.length > 0)
			throw "OCaml source-bundle candidate requires complete source authority.";
		if (maximumPayloadBytes <= 0)
			throw "OCaml source-bundle candidate payload cap must be positive.";
		final normalizedRequestRevision = OcamlArtifactManifestSchema.normalizeRevision(targetRequestRevision, "target request revision");
		final content = new BytesBuffer();
		final indexEntries = new Array<Dynamic>();
		var offset = 0;
		for (entry in snapshot.entries) {
			final path = OcamlArtifactManifestSchema.normalizeRelativePath(entry.path);
			final bytes = File.getBytes(Path.join([outputDirectory, path]));
			final digest = "sha256:" + Sha256.make(bytes).toHex();
			if (bytes.length != entry.bytes || digest != entry.sha256)
				throw 'OCaml source-bundle file "$path" changed after authority observation.';
			indexEntries.push(indexEntryValue(entry, offset));
			content.add(bytes);
			offset += bytes.length;
		}
		final indexValue = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			targetRequestRevision: normalizedRequestRevision,
			programRevision: snapshot.programRevision,
			configurationRevision: snapshot.configurationRevision,
			profile: snapshot.profile,
			sourceBundleRevision: snapshot.sourceBundleRevision,
			diagnosticsEligible: diagnosticsEligible,
			semanticRuntimeAuthority: snapshot.authorities.semanticRuntime,
			nativeDependenciesAuthority: snapshot.authorities.nativeDependencies,
			entries: indexEntries
		};
		final encodedIndex = Bytes.ofString(Json.stringify(indexValue));
		final payloadLength = MAGIC.length + 4 + encodedIndex.length + offset;
		if (payloadLength > maximumPayloadBytes)
			throw 'OCaml source-bundle candidate exceeds the $maximumPayloadBytes-byte entry cap.';
		final output = new BytesOutput();
		output.bigEndian = true;
		output.writeString(MAGIC);
		output.writeInt32(encodedIndex.length);
		output.write(encodedIndex);
		output.write(content.getBytes());
		return decode(output.getBytes());
	}

	/** Decodes and fully validates one opaque candidate payload. **/
	public static function decode(payload:Bytes):OcamlSourceBundleCandidate {
		if (payload == null || payload.length < MAGIC.length + 4)
			throw "OCaml source-bundle candidate payload is truncated.";
		final input = new BytesInput(payload);
		input.bigEndian = true;
		if (input.readString(MAGIC.length) != MAGIC)
			throw "OCaml source-bundle candidate uses an unsupported encoding.";
		final indexLength = input.readInt32();
		if (indexLength <= 0 || indexLength > payload.length - MAGIC.length - 4)
			throw "OCaml source-bundle candidate index length is invalid.";
		final indexStart = MAGIC.length + 4;
		final dataOffset = indexStart + indexLength;
		final index:Dynamic = try {
			Json.parse(input.readString(indexLength));
		} catch (error:Dynamic) {
			throw 'OCaml source-bundle candidate index is invalid JSON: ${Std.string(error)}';
		}
		if (requiredInt(index, "schemaVersion") != SCHEMA_VERSION || requiredString(index, "model") != MODEL)
			throw "OCaml source-bundle candidate uses an unsupported schema or model.";
		final targetRequestRevision = OcamlArtifactManifestSchema.normalizeRevision(requiredString(index, "targetRequestRevision"),
			"candidate target request revision");
		final programRevision = OcamlArtifactManifestSchema.normalizeRevision(requiredString(index, "programRevision"), "candidate program revision");
		final configurationRevision = OcamlArtifactManifestSchema.normalizeRevision(requiredString(index, "configurationRevision"),
			"candidate configuration revision");
		final profile = OcamlArtifactManifestSchema.validatedProfile(requiredString(index, "profile"));
		final sourceBundleRevision = OcamlArtifactManifestSchema.normalizeRevision(requiredString(index, "sourceBundleRevision"),
			"candidate source-bundle revision");
		final diagnosticsEligible = requiredBool(index, "diagnosticsEligible");
		final semanticRuntimeAuthority = parseAuthority(Reflect.field(index, "semanticRuntimeAuthority"), "semantic runtime");
		final nativeDependenciesAuthority = parseAuthority(Reflect.field(index, "nativeDependenciesAuthority"), "native dependencies");
		if (semanticRuntimeAuthority.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE
			|| nativeDependenciesAuthority.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE)
			throw "OCaml source-bundle candidate prerequisite authority is incomplete.";

		final entries = new Array<OcamlSourceBundleIndexEntry>();
		final artifactEntries = new Array<OcamlArtifactEntry>();
		var expectedOffset = 0;
		var previousPath:Null<String> = null;
		for (raw in requiredArray(index, "entries")) {
			final entry = parseEntry(raw, profile);
			if (previousPath != null && Reflect.compare(previousPath, entry.path) >= 0)
				throw 'OCaml source-bundle candidate paths are not in canonical order at "${entry.path}".';
			if (entry.offset != expectedOffset)
				throw 'OCaml source-bundle candidate byte range for "${entry.path}" is not contiguous.';
			if (entry.bytes < 0 || dataOffset + entry.offset + entry.bytes > payload.length)
				throw 'OCaml source-bundle candidate byte range for "${entry.path}" is outside the payload.';
			final bytes = payload.sub(dataOffset + entry.offset, entry.bytes);
			final digest = "sha256:" + Sha256.make(bytes).toHex();
			if (digest != entry.sha256)
				throw 'OCaml source-bundle candidate digest mismatch for "${entry.path}".';
			entries.push(entry);
			artifactEntries.push(toArtifactEntry(entry));
			previousPath = entry.path;
			expectedOffset += entry.bytes;
		}
		if (dataOffset + expectedOffset != payload.length)
			throw "OCaml source-bundle candidate has trailing or missing packed bytes.";
		final actualRevision = OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, artifactEntries,
			semanticRuntimeAuthority, nativeDependenciesAuthority, "source-bundle");
		if (actualRevision != sourceBundleRevision)
			throw "OCaml source-bundle candidate source revision does not match its index.";
		return new OcamlSourceBundleCandidate(copyBytes(payload), dataOffset, targetRequestRevision, programRevision, configurationRevision, profile,
			sourceBundleRevision, diagnosticsEligible, entries, semanticRuntimeAuthority, nativeDependenciesAuthority, expectedOffset, indexLength);
	}

	/** Returns a caller-owned payload copy suitable for an opaque catalog. **/
	public function copyPayload():Bytes
		return copyBytes(payload);

	/** Returns a caller-owned copy of one verified packed source file. **/
	public function copyFile(entry:OcamlSourceBundleIndexEntry):Bytes
		return payload.sub(dataOffset + entry.offset, entry.bytes);

	static function indexEntryValue(entry:OcamlArtifactEntry, offset:Int):Dynamic {
		return {
			path: entry.path,
			offset: offset,
			bytes: entry.bytes,
			sha256: entry.sha256,
			kind: entry.kind,
			owner: entry.owner,
			sourceKind: entry.sourceKind,
			sourcePath: entry.sourcePath,
			license: entry.license,
			profileEligibility: entry.profileEligibility.copy(),
			stability: entry.stability,
			includeInSourceBundle: entry.includeInSourceBundle
		};
	}

	static function parseEntry(value:Dynamic, profile:String):OcamlSourceBundleIndexEntry {
		final sourcePathValue:Dynamic = Reflect.field(value, "sourcePath");
		if (sourcePathValue != null && !Std.isOfType(sourcePathValue, String))
			throw "OCaml source-bundle candidate sourcePath must be null or a string.";
		final profiles = stringArray(value, "profileEligibility");
		final claim:OcamlArtifactClaim = {
			path: requiredString(value, "path"),
			kind: cast requiredString(value, "kind"),
			owner: cast requiredString(value, "owner"),
			sourceKind: cast requiredString(value, "sourceKind"),
			sourcePath: sourcePathValue == null ? null : cast sourcePathValue,
			license: requiredString(value, "license"),
			profileEligibility: profiles,
			stability: cast requiredString(value, "stability"),
			includeInSourceBundle: requiredBool(value, "includeInSourceBundle")
		};
		final normalized = OcamlArtifactManifestSchema.normalizeClaim(claim, profile);
		if (!normalized.includeInSourceBundle || normalized.stability != "stable")
			throw 'OCaml source-bundle candidate entry "${normalized.path}" is not stable source.';
		return {
			path: normalized.path,
			offset: requiredInt(value, "offset"),
			bytes: requiredInt(value, "bytes"),
			sha256: OcamlArtifactManifestSchema.normalizeRevision(requiredString(value, "sha256"), 'candidate digest for "${normalized.path}"'),
			kind: normalized.kind,
			owner: normalized.owner,
			sourceKind: normalized.sourceKind,
			sourcePath: normalized.sourcePath,
			license: normalized.license,
			profileEligibility: normalized.profileEligibility.copy(),
			stability: normalized.stability,
			includeInSourceBundle: normalized.includeInSourceBundle
		};
	}

	static function toArtifactEntry(entry:OcamlSourceBundleIndexEntry):OcamlArtifactEntry {
		return {
			path: entry.path,
			kind: entry.kind,
			owner: entry.owner,
			sourceKind: entry.sourceKind,
			sourcePath: entry.sourcePath,
			license: entry.license,
			profileEligibility: entry.profileEligibility.copy(),
			stability: entry.stability,
			includeInSourceBundle: entry.includeInSourceBundle,
			sha256: entry.sha256,
			bytes: entry.bytes
		};
	}

	static function parseAuthority(value:Dynamic, label:String):OcamlArtifactAuthority {
		if (value == null)
			throw 'OCaml source-bundle candidate is missing $label authority.';
		final revisionValue:Dynamic = Reflect.field(value, "revision");
		if (revisionValue != null && !Std.isOfType(revisionValue, String))
			throw 'OCaml source-bundle candidate $label authority revision must be null or a string.';
		return OcamlArtifactManifestSchema.validatedAuthority({
			status: requiredString(value, "status"),
			model: requiredString(value, "model"),
			revision: revisionValue == null ? null : cast revisionValue,
			message: requiredString(value, "message")
		}, label);
	}

	static function requiredString(value:Dynamic, field:String):String {
		final result:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(result, String) || StringTools.trim(cast result).length == 0)
			throw 'OCaml source-bundle candidate field "$field" must be a non-empty string.';
		return cast result;
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		final result:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(result, Int))
			throw 'OCaml source-bundle candidate field "$field" must be an integer.';
		return cast result;
	}

	static function requiredBool(value:Dynamic, field:String):Bool {
		final result:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(result, Bool))
			throw 'OCaml source-bundle candidate field "$field" must be a boolean.';
		return cast result;
	}

	static function requiredArray(value:Dynamic, field:String):Array<Dynamic> {
		final result:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(result, Array))
			throw 'OCaml source-bundle candidate field "$field" must be an array.';
		return cast result;
	}

	static function stringArray(value:Dynamic, field:String):Array<String> {
		final result = new Array<String>();
		for (entry in requiredArray(value, field)) {
			if (!Std.isOfType(entry, String))
				throw 'OCaml source-bundle candidate field "$field" must contain only strings.';
			result.push(cast entry);
		}
		return result;
	}

	static function copyBytes(value:Bytes):Bytes {
		final result = Bytes.alloc(value.length);
		result.blit(0, value, 0, value.length);
		return result;
	}
}
#end
