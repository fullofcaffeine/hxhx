package reflaxe.ocaml.artifacts;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactClaim;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactManifestReport;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlPreviousArtifactEntry;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
	Validates the artifact-manifest vocabulary, revisions, and on-disk contents.

	This class does not decide why a file exists. Producers make that decision and
	the transaction builder records it. The schema only proves that claims use the
	closed vocabulary and still match the sealed output directory.
**/
class OcamlArtifactManifestSchema {
	public static inline final FILE_NAME = "ocaml_artifact_manifest.json";
	public static inline final FRAMEWORK_RECEIPT = "_GeneratedFiles.json";
	public static inline final MODEL = "reflaxe-ocaml-artifact-manifest";
	public static inline final SCHEMA_VERSION = 1;
	public static inline final AUTHORITY_COMPLETE = "complete";
	public static inline final AUTHORITY_INCOMPLETE = "incomplete";

	/** Normalizes and validates one producer claim against the active profile. **/
	public static function normalizeClaim(claim:OcamlArtifactClaim, profile:String):OcamlArtifactClaim {
		final normalizedProfile = validatedProfile(profile);
		final path = normalizeRelativePath(claim.path);
		final profiles = normalizedTokens(claim.profileEligibility, 'profile eligibility for "$path"');
		if (!profiles.contains(normalizedProfile))
			throw 'OCaml artifact "$path" is not eligible for the active "$normalizedProfile" profile.';
		final kind = validatedKind(claim.kind, path);
		final owner = validatedOwner(claim.owner, path);
		final sourceKind = validatedSourceKind(claim.sourceKind, path);
		final stability = validatedStability(claim.stability, path);
		if (claim.includeInSourceBundle && stability != "stable")
			throw 'Volatile OCaml artifact "$path" cannot be a reproducible source-bundle input.';
		final sourcePath = claim.sourcePath == null ? null : normalizeLogicalSourcePath(claim.sourcePath);
		validateSourceProvenance(sourceKind, sourcePath, path);
		return {
			path: path,
			kind: kind,
			owner: owner,
			sourceKind: sourceKind,
			sourcePath: sourcePath,
			license: requireToken(claim.license, 'license for "$path"'),
			profileEligibility: profiles,
			stability: stability,
			includeInSourceBundle: claim.includeInSourceBundle
		};
	}

	/** Validates one runtime or native-dependency prerequisite inventory. **/
	public static function validatedAuthority(value:OcamlArtifactAuthority, label:String):OcamlArtifactAuthority {
		if (value == null)
			throw 'OCaml artifact manifest requires $label authority.';
		final status = requireToken(value.status, '$label status');
		if (status != AUTHORITY_COMPLETE && status != AUTHORITY_INCOMPLETE)
			throw 'OCaml artifact $label authority has unsupported status "$status".';
		final revision = value.revision == null ? null : normalizeRevision(value.revision, '$label revision');
		if (status == AUTHORITY_COMPLETE && revision == null)
			throw 'Complete OCaml artifact $label authority requires a SHA-256 revision.';
		return {
			status: status,
			model: requireToken(value.model, '$label model'),
			revision: revision,
			message: requireToken(value.message, '$label message')
		};
	}

	/** Computes a deterministic revision for one declared subset of the output. **/
	public static function calculateArtifactRevision(programRevision:String, configurationRevision:String, profile:String, entries:Array<OcamlArtifactEntry>,
			semanticRuntime:OcamlArtifactAuthority, nativeDependencies:OcamlArtifactAuthority, scope:String):String {
		final canonicalEntries:Array<Dynamic> = [
			for (entry in entries) [
				entry.path,
				entry.sha256,
				entry.bytes,
				entry.kind,
				entry.owner,
				entry.sourceKind,
				entry.sourcePath == null ? "" : entry.sourcePath,
				entry.license,
				entry.profileEligibility,
				entry.stability,
				entry.includeInSourceBundle
			]
		];
		final canonical:Array<Dynamic> = [
			MODEL,
			SCHEMA_VERSION,
			requireToken(scope, "artifact revision scope"),
			normalizeRevision(programRevision, "program revision"),
			normalizeRevision(configurationRevision, "configuration revision"),
			validatedProfile(profile),
			[
				semanticRuntime.status,
				semanticRuntime.model,
				semanticRuntime.revision == null ? "" : semanticRuntime.revision
			],
			[
				nativeDependencies.status,
				nativeDependencies.model,
				nativeDependencies.revision == null ? "" : nativeDependencies.revision
			],
			canonicalEntries
		];
		return "sha256:" + Sha256.encode(Json.stringify(canonical));
	}

	/** Loads and fully validates the manifest currently sealed in an output directory. **/
	public static function loadAndValidateCurrent(outputDirectory:String):OcamlArtifactManifestReport {
		final value = readManifest(outputDirectory);
		return validateManifest(outputDirectory, value, null, null);
	}

	/**
		Loads a sealed manifest and additionally proves that it describes the
		expected program and source-affecting configuration.
	**/
	public static function loadAndValidate(outputDirectory:String, expectedProgramRevision:String,
			expectedConfigurationRevision:String):OcamlArtifactManifestReport {
		final value = readManifest(outputDirectory);
		return validateManifest(outputDirectory, value, expectedProgramRevision, expectedConfigurationRevision);
	}

	static function readManifest(outputDirectory:String):Dynamic {
		final path = Path.join([outputDirectory, FILE_NAME]);
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
			throw 'OCaml artifact manifest "$path" is missing.';
		return try {
			Json.parse(File.getContent(path));
		} catch (error:Dynamic) {
			throw 'OCaml artifact manifest "$path" is invalid JSON: ${Std.string(error)}';
		}
	}

	static function validateManifest(outputDirectory:String, value:Dynamic, expectedProgramRevision:Null<String>,
			expectedConfigurationRevision:Null<String>):OcamlArtifactManifestReport {
		final path = Path.join([outputDirectory, FILE_NAME]);
		if (requiredInt(value, "schemaVersion") != SCHEMA_VERSION || requiredString(value, "model") != MODEL)
			throw 'OCaml artifact manifest "$path" uses an unsupported schema or model.';
		final programRevision = normalizeRevision(requiredString(value, "programRevision"), "program revision");
		final configurationRevision = normalizeRevision(requiredString(value, "configurationRevision"), "configuration revision");
		if (expectedProgramRevision != null && programRevision != normalizeRevision(expectedProgramRevision, "expected program revision"))
			throw 'OCaml artifact manifest belongs to stale program revision $programRevision.';
		if (expectedConfigurationRevision != null
			&& configurationRevision != normalizeRevision(expectedConfigurationRevision, "expected configuration revision"))
			throw 'OCaml artifact manifest belongs to stale configuration revision $configurationRevision.';
		final profile = validatedProfile(requiredString(value, "profile"));
		if (requiredString(value, "frameworkReceipt") != FRAMEWORK_RECEIPT)
			throw 'OCaml artifact manifest names an unsupported framework receipt.';
		final authoritiesValue:Dynamic = Reflect.field(value, "authorities");
		if (authoritiesValue == null)
			throw 'OCaml artifact manifest is missing prerequisite authorities.';
		final semanticRuntime = parseAuthority(Reflect.field(authoritiesValue, "semanticRuntime"), "semantic runtime");
		final nativeDependencies = parseAuthority(Reflect.field(authoritiesValue, "nativeDependencies"), "native dependencies");
		final entries = parseEntries(requiredArray(value, "entries"), profile, outputDirectory);
		final summary:Dynamic = Reflect.field(value, "summary");
		if (summary == null)
			throw 'OCaml artifact manifest is missing its summary.';
		validateSummary(summary, entries, semanticRuntime, nativeDependencies, programRevision, configurationRevision, profile);
		validateRegisteredPaths(outputDirectory, [for (entry in entries) entry.path => true]);
		return cast value;
	}

	/** Reads only validated cleanup data from a preceding compiler manifest. **/
	public static function readPreviousEntries(outputDirectory:String):Array<OcamlPreviousArtifactEntry> {
		final path = Path.join([outputDirectory, FILE_NAME]);
		if (!FileSystem.exists(path))
			return [];
		if (FileSystem.isDirectory(path))
			throw 'Cannot replace prior OCaml artifact manifest because "$path" is a directory.';
		final value:Dynamic = try {
			Json.parse(File.getContent(path));
		} catch (error:Dynamic) {
			throw 'Prior OCaml artifact manifest is invalid: ${Std.string(error)}';
		}
		if (requiredInt(value, "schemaVersion") != SCHEMA_VERSION || requiredString(value, "model") != MODEL)
			throw "Prior OCaml artifact manifest uses an unsupported schema or model; clean the output directory before rebuilding.";
		normalizeRevision(requiredString(value, "programRevision"), "prior program revision");
		normalizeRevision(requiredString(value, "configurationRevision"), "prior configuration revision");
		validatedProfile(requiredString(value, "profile"));
		final entries = new Array<OcamlPreviousArtifactEntry>();
		final seen:Map<String, Bool> = [];
		for (raw in requiredArray(value, "entries")) {
			final artifactPath = normalizeRelativePath(requiredString(raw, "path"));
			if (seen.exists(artifactPath))
				throw 'Prior OCaml artifact manifest contains duplicate path "$artifactPath".';
			seen.set(artifactPath, true);
			validatedKind(requiredString(raw, "kind"), artifactPath);
			validatedOwner(requiredString(raw, "owner"), artifactPath);
			validatedSourceKind(requiredString(raw, "sourceKind"), artifactPath);
			validatedStability(requiredString(raw, "stability"), artifactPath);
			entries.push({
				path: artifactPath,
				sha256: normalizeRevision(requiredString(raw, "sha256"), 'digest for "$artifactPath"')
			});
		}
		return entries;
	}

	/** Rejects every non-cache output file that no producer registered. **/
	public static function validateRegisteredPaths(outputDirectory:String, registered:Map<String, Bool>):Void {
		final files = new Array<String>();
		collectFiles(outputDirectory, "", files);
		files.sort(compareStrings);
		for (path in files) {
			if (isExcludedBuildProduct(path) || registered.exists(path))
				continue;
			throw 'OCaml output contains unregistered non-cache file "$path". Its producer must declare ownership before packaging can be trusted.';
		}
	}

	/** Returns the digest and byte count used in a sealed entry. **/
	public static function digestFile(path:String):{final sha256:String; final bytes:Int;} {
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
			throw 'Registered OCaml artifact "$path" is missing or is not a file.';
		final bytes = File.getBytes(path);
		return {
			sha256: "sha256:" + Sha256.make(bytes).toHex(),
			bytes: bytes.length
		};
	}

	/** Writes a complete JSON report without leaving a partial final file. **/
	public static function writeAtomically(path:String, contents:String):Void {
		final temporary = path + ".tmp";
		try {
			File.saveContent(temporary, contents);
			try {
				FileSystem.rename(temporary, path);
			} catch (_:Dynamic) {
				if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
					FileSystem.deleteFile(path);
				FileSystem.rename(temporary, path);
			}
		} catch (error:Dynamic) {
			if (FileSystem.exists(temporary) && !FileSystem.isDirectory(temporary)) {
				try
					FileSystem.deleteFile(temporary)
				catch (_:Dynamic) {}
			}
			throw error;
		}
	}

	public static function normalizeRevision(value:String, label:String):String {
		final raw = requireToken(value, label);
		final normalized = raw.startsWith("sha256:") ? raw : "sha256:" + raw;
		if (!~/^sha256:[0-9a-f]{64}$/.match(normalized))
			throw 'OCaml artifact $label must be a lowercase SHA-256 revision.';
		return normalized;
	}

	public static function normalizeRelativePath(value:String):String {
		final normalized = value == null ? "" : value.replace("\\", "/");
		final parts = normalized.split("/");
		if (normalized.length == 0 || Path.isAbsolute(normalized) || ~/^[A-Za-z]:\//.match(normalized) || parts.contains("") || parts.contains(".")
			|| parts.contains(".."))
			throw 'OCaml artifact path "$value" is not a safe output-relative path.';
		return normalized;
	}

	public static function normalizeLogicalSourcePath(value:String):String {
		final normalized = normalizeRelativePath(value);
		if (normalized.startsWith("_build/"))
			throw 'OCaml artifact source path "$value" points into a build cache.';
		return normalized;
	}

	public static function validatedProfile(value:String):String {
		final profile = requireToken(value, "profile").toLowerCase();
		if (profile != "portable" && profile != "metal")
			throw 'OCaml artifact profile "$profile" must be portable or metal.';
		return profile;
	}

	static function parseAuthority(value:Dynamic, label:String):OcamlArtifactAuthority {
		if (value == null)
			throw 'OCaml artifact manifest is missing $label authority.';
		final revisionValue:Dynamic = Reflect.field(value, "revision");
		if (revisionValue != null && !Std.isOfType(revisionValue, String))
			throw 'OCaml artifact $label authority revision must be null or a string.';
		return validatedAuthority({
			status: requiredString(value, "status"),
			model: requiredString(value, "model"),
			revision: revisionValue == null ? null : cast revisionValue,
			message: requiredString(value, "message")
		}, label);
	}

	static function parseEntries(rawEntries:Array<Dynamic>, profile:String, outputDirectory:String):Array<OcamlArtifactEntry> {
		final entries = new Array<OcamlArtifactEntry>();
		final seen:Map<String, Bool> = [];
		var previousPath:Null<String> = null;
		for (raw in rawEntries) {
			final path = normalizeRelativePath(requiredString(raw, "path"));
			if (seen.exists(path))
				throw 'OCaml artifact manifest contains duplicate path "$path".';
			if (previousPath != null && compareStrings(previousPath, path) >= 0)
				throw 'OCaml artifact manifest entries are not in deterministic path order at "$path".';
			previousPath = path;
			seen.set(path, true);
			final kind:String = validatedKind(requiredString(raw, "kind"), path);
			final owner:String = validatedOwner(requiredString(raw, "owner"), path);
			final sourceKind:String = validatedSourceKind(requiredString(raw, "sourceKind"), path);
			final sourcePath = optionalString(raw, "sourcePath");
			final normalizedSourcePath = sourcePath == null ? null : normalizeLogicalSourcePath(sourcePath);
			validateSourceProvenance(sourceKind, normalizedSourcePath, path);
			final profiles = normalizedTokens(requiredStringArray(raw, "profileEligibility"), 'profile eligibility for "$path"');
			if (!profiles.contains(profile))
				throw 'OCaml artifact "$path" is not eligible for manifest profile "$profile".';
			final stability:String = validatedStability(requiredString(raw, "stability"), path);
			final includeInSourceBundle = requiredBool(raw, "includeInSourceBundle");
			if (includeInSourceBundle && stability != "stable")
				throw 'Volatile OCaml artifact "$path" cannot be a reproducible source-bundle input.';
			final sha256 = normalizeRevision(requiredString(raw, "sha256"), 'digest for "$path"');
			final byteCount = requiredInt(raw, "bytes");
			if (byteCount < 0)
				throw 'OCaml artifact "$path" has a negative byte count.';
			final absolute = Path.join([outputDirectory, path]);
			final actual = digestFile(absolute);
			if (actual.bytes != byteCount || actual.sha256 != sha256)
				throw 'OCaml artifact manifest digest mismatch for "$path": expected $sha256 and $byteCount bytes, found ${actual.sha256} and ${actual.bytes} bytes.';
			entries.push({
				path: path,
				kind: kind,
				owner: owner,
				sourceKind: sourceKind,
				sourcePath: normalizedSourcePath,
				license: requireToken(requiredString(raw, "license"), 'license for "$path"'),
				profileEligibility: profiles,
				stability: stability,
				includeInSourceBundle: includeInSourceBundle,
				sha256: sha256,
				bytes: byteCount
			});
		}
		return entries;
	}

	static function validateSummary(summary:Dynamic, entries:Array<OcamlArtifactEntry>, semanticRuntime:OcamlArtifactAuthority,
			nativeDependencies:OcamlArtifactAuthority, programRevision:String, configurationRevision:String, profile:String):Void {
		final bundleEntries = entries.filter(entry -> entry.includeInSourceBundle);
		final volatileEntries = entries.filter(entry -> entry.stability == "volatile");
		if (requiredInt(summary, "entryCount") != entries.length
			|| requiredInt(summary, "sourceBundleEntryCount") != bundleEntries.length
			|| requiredInt(summary, "volatileEvidenceEntryCount") != volatileEntries.length)
			throw 'OCaml artifact manifest summary counts do not match its entries.';
		final expectedSourceRevision = calculateArtifactRevision(programRevision, configurationRevision, profile, bundleEntries, semanticRuntime,
			nativeDependencies, "source-bundle");
		final expectedSetRevision = calculateArtifactRevision(programRevision, configurationRevision, profile, entries, semanticRuntime, nativeDependencies,
			"artifact-set");
		if (normalizeRevision(requiredString(summary, "sourceBundleRevision"), "source-bundle revision") != expectedSourceRevision)
			throw 'OCaml artifact manifest source-bundle revision does not match its entries.';
		if (normalizeRevision(requiredString(summary, "artifactSetRevision"), "artifact-set revision") != expectedSetRevision)
			throw 'OCaml artifact manifest artifact-set revision does not match its entries.';
		final expectedComplete = semanticRuntime.status == AUTHORITY_COMPLETE && nativeDependencies.status == AUTHORITY_COMPLETE;
		if (requiredBool(summary, "completeForSourceBundle") != expectedComplete)
			throw 'OCaml artifact manifest source-bundle readiness does not match its prerequisite authorities.';
		final expectedBlockers = new Array<String>();
		if (semanticRuntime.status != AUTHORITY_COMPLETE)
			expectedBlockers.push(semanticRuntime.message);
		if (nativeDependencies.status != AUTHORITY_COMPLETE)
			expectedBlockers.push(nativeDependencies.message);
		if (!arraysEqual(requiredStringArray(summary, "blockers"), expectedBlockers))
			throw 'OCaml artifact manifest blockers do not match its incomplete prerequisite authorities.';
	}

	static function collectFiles(absoluteDirectory:String, relativeDirectory:String, out:Array<String>):Void {
		if (!FileSystem.exists(absoluteDirectory) || !FileSystem.isDirectory(absoluteDirectory))
			return;
		final names = FileSystem.readDirectory(absoluteDirectory);
		names.sort(compareStrings);
		for (name in names) {
			final relative = relativeDirectory.length == 0 ? name : relativeDirectory + "/" + name;
			if (relative == "_build" || relative.startsWith("_build/"))
				continue;
			final absolute = Path.join([absoluteDirectory, name]);
			if (FileSystem.isDirectory(absolute))
				collectFiles(absolute, relative, out);
			else
				out.push(normalizeRelativePath(relative));
		}
	}

	static function isExcludedBuildProduct(path:String):Bool {
		return path == FILE_NAME || path == FILE_NAME + ".tmp" || path == FRAMEWORK_RECEIPT || path.endsWith(".install");
	}

	static function validatedOwner(value:String, path:String):OcamlArtifactOwner {
		return switch requireToken(value, 'owner for "$path"') {
			case "reflaxe-framework": OcamlArtifactOwner.Framework;
			case "ocaml-compiler": OcamlArtifactOwner.CompilerCore;
			case "dune-project-emitter": OcamlArtifactOwner.DuneScaffold;
			case "runtime-copier": OcamlArtifactOwner.RuntimePackaging;
			case "native-functor-emitter": OcamlArtifactOwner.NativeFunctorGeneration;
			case "package-alias-emitter": OcamlArtifactOwner.PackageAliasGeneration;
			case "lowering-report-writer": OcamlArtifactOwner.LoweringReport;
			case "lifecycle-trace-writer": OcamlArtifactOwner.LifecycleTrace;
			case "target-reuse-report-writer": OcamlArtifactOwner.TargetReuseReport;
			case "mli-generator": OcamlArtifactOwner.MliInference;
			case "build-timing-report-writer": OcamlArtifactOwner.BuildTimingReport;
			case "binding-emitter": OcamlArtifactOwner.BindingGeneration;
			case "native-adapter-emitter": OcamlArtifactOwner.NativeAdapter;
			case "export-wrapper-emitter": OcamlArtifactOwner.ExportWrapper;
			case unknown: throw 'OCaml artifact "$path" has unknown owner "$unknown".';
		};
	}

	static function validatedKind(value:String, path:String):OcamlArtifactKind {
		return switch requireToken(value, 'kind for "$path"') {
			case "haxe-module-source": OcamlArtifactKind.HaxeModuleSource;
			case "type-registry-source": OcamlArtifactKind.TypeRegistrySource;
			case "entry-source": OcamlArtifactKind.EntrySource;
			case "dune-project": OcamlArtifactKind.DuneProject;
			case "dune-stanza": OcamlArtifactKind.DuneStanza;
			case "gitignore": OcamlArtifactKind.GitIgnore;
			case "runtime-source": OcamlArtifactKind.RuntimeSource;
			case "native-functor-source": OcamlArtifactKind.NativeFunctorSource;
			case "package-alias-source": OcamlArtifactKind.PackageAliasSource;
			case "compiler-report": OcamlArtifactKind.CompilerReport;
			case "inferred-interface": OcamlArtifactKind.InferredInterface;
			case "generated-binding": OcamlArtifactKind.GeneratedBinding;
			case "native-adapter": OcamlArtifactKind.NativeAdapter;
			case "export-wrapper": OcamlArtifactKind.ExportWrapper;
			case unknown: throw 'OCaml artifact "$path" has unknown kind "$unknown".';
		};
	}

	static function validatedSourceKind(value:String, path:String):OcamlArtifactSourceKind {
		return switch requireToken(value, 'source kind for "$path"') {
			case "generated": OcamlArtifactSourceKind.Generated;
			case "repository-owned": OcamlArtifactSourceKind.RepositoryOwned;
			case "copied-runtime": OcamlArtifactSourceKind.CopiedRuntime;
			case "inferred": OcamlArtifactSourceKind.Inferred;
			case "generated-binding": OcamlArtifactSourceKind.GeneratedBinding;
			case "handwritten-adapter": OcamlArtifactSourceKind.HandwrittenAdapter;
			case unknown: throw 'OCaml artifact "$path" has unknown source kind "$unknown".';
		};
	}

	static function validatedStability(value:String, path:String):OcamlArtifactStability {
		return switch requireToken(value, 'stability for "$path"') {
			case "stable": OcamlArtifactStability.Stable;
			case "volatile": OcamlArtifactStability.Volatile;
			case unknown: throw 'OCaml artifact "$path" has unsupported stability "$unknown".';
		};
	}

	static function validateSourceProvenance(sourceKind:String, sourcePath:Null<String>, path:String):Void {
		if ((sourceKind == "repository-owned" || sourceKind == "copied-runtime" || sourceKind == "handwritten-adapter")
			&& sourcePath == null)
			throw 'OCaml artifact "$path" with source kind "$sourceKind" requires a repository-relative source path.';
	}

	static function requireToken(value:String, label:String):String {
		final normalized = value == null ? "" : value.trim();
		if (normalized.length == 0)
			throw 'OCaml artifact $label must not be empty.';
		return normalized;
	}

	static function normalizedTokens(values:Array<String>, label:String):Array<String> {
		if (values == null || values.length == 0)
			throw 'OCaml artifact $label must not be empty.';
		final seen:Map<String, Bool> = [];
		final result = new Array<String>();
		for (value in values) {
			final token = requireToken(value, label);
			if (!seen.exists(token)) {
				seen.set(token, true);
				result.push(token);
			}
		}
		result.sort(compareStrings);
		return result;
	}

	static function optionalString(value:Dynamic, field:String):Null<String> {
		final raw:Dynamic = Reflect.field(value, field);
		if (raw == null)
			return null;
		if (!Std.isOfType(raw, String))
			throw 'Expected "$field" to be null or a string.';
		return cast raw;
	}

	static function requiredStringArray(value:Dynamic, field:String):Array<String> {
		final rawValues = requiredArray(value, field);
		final result = new Array<String>();
		for (raw in rawValues) {
			if (!Std.isOfType(raw, String))
				throw 'Expected "$field" to contain only strings.';
			result.push(cast raw);
		}
		return result;
	}

	static function requiredBool(value:Dynamic, field:String):Bool {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, Bool))
			throw 'Expected "$field" to be a Boolean.';
		return cast raw;
	}

	static function arraysEqual(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			if (left[index] != right[index])
				return false;
		}
		return true;
	}

	static function requiredArray(value:Dynamic, field:String):Array<Dynamic> {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, Array))
			throw 'Expected "$field" to be an array.';
		return cast raw;
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, Int))
			throw 'Expected "$field" to be an integer.';
		return cast raw;
	}

	static function requiredString(value:Dynamic, field:String):String {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, String) || StringTools.trim(cast raw).length == 0)
			throw 'Expected "$field" to be a non-empty string.';
		return cast raw;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
