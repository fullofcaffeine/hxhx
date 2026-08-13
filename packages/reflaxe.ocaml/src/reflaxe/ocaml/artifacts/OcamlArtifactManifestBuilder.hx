package reflaxe.ocaml.artifacts;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
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
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlSourceBundleSnapshot;
import sys.FileSystem;
import sys.io.File;

/**
	Builds and seals one target-owned OCaml artifact inventory.

	Producer claims are the source of truth. The final directory walk is only a
	fail-closed consistency check: an unknown file is rejected instead of being
	automatically assigned an owner.
**/
class OcamlArtifactManifestBuilder {
	var outputDirectory:String;
	final programRevision:String;
	final configurationRevision:String;
	final profile:String;
	final claims:Map<String, OcamlArtifactClaim> = [];
	final previousEntries:Array<OcamlPreviousArtifactEntry>;
	var sealedManifestDigest:Null<String>;

	/**
		Starts one output transaction and invalidates the previous manifest.

		The previous inventory is retained in memory only so obsolete target-owned
		files can be removed safely after the new producer set is known.
	**/
	public function new(outputDirectory:String, programRevision:String, configurationRevision:String, profile:String) {
		if (outputDirectory == null || outputDirectory.length == 0)
			throw "OCaml artifact manifest requires an output directory.";
		final absoluteOutputDirectory = Path.normalize(FileSystem.absolutePath(outputDirectory));
		if (!FileSystem.exists(absoluteOutputDirectory) || !FileSystem.isDirectory(absoluteOutputDirectory))
			throw 'OCaml artifact manifest output directory "$outputDirectory" is missing.';
		this.outputDirectory = absoluteOutputDirectory;
		this.programRevision = OcamlArtifactManifestSchema.normalizeRevision(programRevision, "program revision");
		this.configurationRevision = OcamlArtifactManifestSchema.normalizeRevision(configurationRevision, "configuration revision");
		this.profile = OcamlArtifactManifestSchema.validatedProfile(profile);
		previousEntries = OcamlArtifactManifestSchema.readPreviousEntries(absoluteOutputDirectory);
		clearPriorManifest();
	}

	/**
		Continues one sealed artifact inventory after its private directory is published.

		Transactional output renames the complete candidate directory into its stable
		public path. A later native-build callback may add volatile evidence, but it
		must first prove that the public directory contains the exact manifest this
		builder sealed and that the private candidate no longer exists.
	**/
	public function continueAtPublishedDirectory(publicDirectory:String):Void {
		if (sealedManifestDigest == null)
			throw "Cannot continue an OCaml artifact inventory before its candidate manifest is sealed.";
		final previousDirectory = outputDirectory;
		final absolutePublicDirectory = Path.normalize(FileSystem.absolutePath(publicDirectory));
		if (absolutePublicDirectory == previousDirectory)
			throw "Cannot continue an OCaml artifact inventory at the same directory.";
		if (FileSystem.exists(previousDirectory))
			throw 'Cannot continue an OCaml artifact inventory while private candidate "$previousDirectory" still exists.';
		if (!FileSystem.exists(absolutePublicDirectory) || !FileSystem.isDirectory(absolutePublicDirectory))
			throw 'Cannot continue an OCaml artifact inventory because published directory "$absolutePublicDirectory" is missing.';
		final publishedManifest = Path.join([absolutePublicDirectory, OcamlArtifactManifestSchema.FILE_NAME]);
		if (!FileSystem.exists(publishedManifest) || FileSystem.isDirectory(publishedManifest))
			throw 'Cannot continue an OCaml artifact inventory because published manifest "$publishedManifest" is missing.';
		final publishedDigest = OcamlArtifactManifestSchema.digestFile(publishedManifest).sha256;
		if (publishedDigest != sealedManifestDigest)
			throw 'Cannot continue an OCaml artifact inventory because the published manifest changed; expected $sealedManifestDigest, found $publishedDigest.';
		outputDirectory = absolutePublicDirectory;
	}

	/** Records one file from the component that owns why it was emitted. **/
	public function record(claim:OcamlArtifactClaim):Void {
		final normalized = OcamlArtifactManifestSchema.normalizeClaim(claim, profile);
		if (claims.exists(normalized.path))
			throw 'OCaml artifact path "${normalized.path}" was registered more than once.';
		claims.set(normalized.path, normalized);
	}

	/** Returns whether the current output transaction owns this relative path. **/
	public function isRecorded(path:String):Bool {
		return claims.exists(OcamlArtifactManifestSchema.normalizeRelativePath(path));
	}

	/**
		Returns whether any producer already owns a case-equivalent output path.

		OCaml derives module names from filenames, and common macOS filesystems also
		treat filename case as equivalent. Entry-module selection uses this check so
		a requested executable name cannot replace program or package-alias source.
	**/
	public function hasCaseEquivalentPath(path:String):Bool {
		final normalized = OcamlArtifactManifestSchema.normalizeRelativePath(path).toLowerCase();
		for (ownedPath in claims.keys()) {
			if (ownedPath.toLowerCase() == normalized)
				return true;
		}
		return false;
	}

	/**
		Removes a current claim after an explicit output filter deletes that file.

		This does not delete bytes. The caller must perform the deletion first so an
		unclaimed surviving file is still caught by the final consistency check.
	**/
	public function discardRecorded(path:String):Void {
		claims.remove(OcamlArtifactManifestSchema.normalizeRelativePath(path));
	}

	/**
		Returns whether an existing file is unchanged compiler output from the prior
		manifest. A changed prior file fails instead of being silently re-adopted.
	**/
	public function isUnchangedPrevious(path:String):Bool {
		final normalized = OcamlArtifactManifestSchema.normalizeRelativePath(path);
		for (entry in previousEntries) {
			if (entry.path != normalized)
				continue;
			final absolute = absolutePath(normalized);
			if (!FileSystem.exists(absolute) || FileSystem.isDirectory(absolute))
				return false;
			final actual = OcamlArtifactManifestSchema.digestFile(absolute).sha256;
			if (actual != entry.sha256)
				throw 'Refusing to reuse modified OCaml artifact "$normalized"; expected ${entry.sha256}, found $actual.';
			return true;
		}
		return false;
	}

	/**
		Imports the Haxe-module paths already written by Reflaxe.

		The receipt remains framework cache bookkeeping and is not itself a source
		bundle input. Explicitly excluded paths are accepted only when the target's
		output filter already removed them.
	**/
	public function recordFrameworkModules(?excludedPaths:Map<String, Bool>):Void {
		final receiptPath = absolutePath(OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT);
		if (!FileSystem.exists(receiptPath) || FileSystem.isDirectory(receiptPath))
			throw 'Cannot seal OCaml artifacts because ${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} is missing.';
		final value:Dynamic = try {
			Json.parse(File.getContent(receiptPath));
		} catch (error:Dynamic) {
			throw 'Cannot seal OCaml artifacts because ${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} is invalid: ${Std.string(error)}';
		}
		final version:Dynamic = Reflect.field(value, "version");
		if (!Std.isOfType(version, Int) || version != 1)
			throw 'Cannot seal OCaml artifacts from unsupported ${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} schema ${Std.string(version)}.';
		final rawFiles:Dynamic = Reflect.field(value, "filesGenerated");
		if (!Std.isOfType(rawFiles, Array))
			throw '${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} filesGenerated must be an array.';
		final seen:Map<String, Bool> = [];
		for (raw in (cast rawFiles : Array<Dynamic>)) {
			if (!Std.isOfType(raw, String))
				throw '${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} filesGenerated must contain only strings.';
			final path = OcamlArtifactManifestSchema.normalizeRelativePath(cast raw);
			if (seen.exists(path))
				throw '${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} contains duplicate path "$path".';
			seen.set(path, true);
			final absolute = absolutePath(path);
			if (!FileSystem.exists(absolute) || FileSystem.isDirectory(absolute)) {
				if (excludedPaths != null && excludedPaths.exists(path))
					continue;
				throw '${OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT} names missing generated module "$path".';
			}
			record({
				path: path,
				kind: OcamlArtifactKind.HaxeModuleSource,
				owner: OcamlArtifactOwner.Framework,
				sourceKind: OcamlArtifactSourceKind.Generated,
				sourcePath: null,
				license: "generated-output",
				profileEligibility: [profile],
				stability: OcamlArtifactStability.Stable,
				includeInSourceBundle: true
			});
		}
	}

	/**
		Builds the verified stable-output view without writing the manifest root.

		Callers use this after every source producer and output filter has run. A
		later final `seal()` independently reads and validates every claim again, so
		this earlier snapshot cannot authorize publication or conceal a file changed
		between cache packing and the final transaction check.
	**/
	public function snapshotSourceBundle(semanticRuntime:OcamlArtifactAuthority, nativeDependencies:OcamlArtifactAuthority):OcamlSourceBundleSnapshot {
		final checkedRuntime = OcamlArtifactManifestSchema.validatedAuthority(semanticRuntime, "semantic runtime");
		final checkedDependencies = OcamlArtifactManifestSchema.validatedAuthority(nativeDependencies, "native dependencies");
		final entries = materializeEntries().filter(entry -> entry.stability == "stable");
		final sourceEntries = entries.filter(entry -> entry.includeInSourceBundle);
		final completeForSourceBundle = checkedRuntime.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE
			&& checkedDependencies.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE;
		final blockers = new Array<String>();
		if (checkedRuntime.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE)
			blockers.push(checkedRuntime.message);
		if (checkedDependencies.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE)
			blockers.push(checkedDependencies.message);
		return {
			schemaVersion: OcamlArtifactManifestSchema.SCHEMA_VERSION,
			model: OcamlArtifactManifestSchema.MODEL,
			programRevision: programRevision,
			configurationRevision: configurationRevision,
			profile: profile,
			entries: entries,
			authorities: {
				semanticRuntime: checkedRuntime,
				nativeDependencies: checkedDependencies
			},
			sourceBundleRevision: OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, sourceEntries,
				checkedRuntime, checkedDependencies, "source-bundle"),
			completeForSourceBundle: completeForSourceBundle,
			blockers: blockers
		};
	}

	/**
		Verifies, cleans, and atomically writes the completed manifest.

		Obsolete files from a previous valid manifest are removed only when their
		current bytes still match the previous digest. A modified file is treated as
		user data and causes a deterministic error instead of being deleted.
	**/
	public function seal(semanticRuntime:OcamlArtifactAuthority, nativeDependencies:OcamlArtifactAuthority):OcamlArtifactManifestReport {
		final checkedRuntime = OcamlArtifactManifestSchema.validatedAuthority(semanticRuntime, "semantic runtime");
		final checkedDependencies = OcamlArtifactManifestSchema.validatedAuthority(nativeDependencies, "native dependencies");
		final entries = materializeEntries();
		removeObsoletePreviousEntries();
		OcamlArtifactManifestSchema.validateRegisteredPaths(outputDirectory, [for (path in claims.keys()) path => true]);

		final bundleEntries = entries.filter(entry -> entry.includeInSourceBundle);
		final volatileEntries = entries.filter(entry -> entry.stability == "volatile");
		final sourceBundleRevision = OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, bundleEntries,
			checkedRuntime, checkedDependencies, "source-bundle");
		final artifactSetRevision = OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, entries,
			checkedRuntime, checkedDependencies, "artifact-set");
		final completeForSourceBundle = checkedRuntime.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE
			&& checkedDependencies.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE;
		final blockers = new Array<String>();
		if (checkedRuntime.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE)
			blockers.push(checkedRuntime.message);
		if (checkedDependencies.status != OcamlArtifactManifestSchema.AUTHORITY_COMPLETE)
			blockers.push(checkedDependencies.message);
		final report:OcamlArtifactManifestReport = {
			schemaVersion: OcamlArtifactManifestSchema.SCHEMA_VERSION,
			model: OcamlArtifactManifestSchema.MODEL,
			programRevision: programRevision,
			configurationRevision: configurationRevision,
			profile: profile,
			frameworkReceipt: OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT,
			entries: entries,
			authorities: {
				semanticRuntime: checkedRuntime,
				nativeDependencies: checkedDependencies
			},
			summary: {
				entryCount: entries.length,
				sourceBundleEntryCount: bundleEntries.length,
				volatileEvidenceEntryCount: volatileEntries.length,
				sourceBundleRevision: sourceBundleRevision,
				artifactSetRevision: artifactSetRevision,
				completeForSourceBundle: completeForSourceBundle,
				blockers: blockers
			},
			excludedBuildProducts: [
				"_build/** (Dune cache and compiled products)",
				"*.install (Dune package build product)",
				OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT + " (Reflaxe cache bookkeeping)",
				OcamlArtifactManifestSchema.FILE_NAME + " (this inventory root)"
			]
		};
		final manifestPath = absolutePath(OcamlArtifactManifestSchema.FILE_NAME);
		OcamlArtifactManifestSchema.writeAtomically(manifestPath, Json.stringify(report, null, "  ") + "\n");
		sealedManifestDigest = OcamlArtifactManifestSchema.digestFile(manifestPath).sha256;
		return report;
	}

	function materializeEntries():Array<OcamlArtifactEntry> {
		final paths = [for (path in claims.keys()) path];
		paths.sort(compareStrings);
		final entries = new Array<OcamlArtifactEntry>();
		for (path in paths) {
			final claim = claims.get(path);
			if (claim == null)
				continue;
			final digest = OcamlArtifactManifestSchema.digestFile(absolutePath(path));
			entries.push({
				path: claim.path,
				kind: claim.kind,
				owner: claim.owner,
				sourceKind: claim.sourceKind,
				sourcePath: claim.sourcePath,
				license: claim.license,
				profileEligibility: claim.profileEligibility.copy(),
				stability: claim.stability,
				includeInSourceBundle: claim.includeInSourceBundle,
				sha256: digest.sha256,
				bytes: digest.bytes
			});
		}
		return entries;
	}

	function removeObsoletePreviousEntries():Void {
		for (entry in previousEntries) {
			if (claims.exists(entry.path))
				continue;
			final absolute = absolutePath(entry.path);
			if (!FileSystem.exists(absolute))
				continue;
			if (FileSystem.isDirectory(absolute))
				throw 'Previously owned OCaml artifact "${entry.path}" became a directory.';
			final actual = OcamlArtifactManifestSchema.digestFile(absolute).sha256;
			if (actual != entry.sha256)
				throw 'Refusing to delete modified obsolete OCaml artifact "${entry.path}"; expected ${entry.sha256}, found $actual.';
			FileSystem.deleteFile(absolute);
			pruneEmptyParents(Path.directory(absolute));
		}
	}

	function clearPriorManifest():Void {
		final path = absolutePath(OcamlArtifactManifestSchema.FILE_NAME);
		if (FileSystem.exists(path))
			FileSystem.deleteFile(path);
		final temporary = path + ".tmp";
		if (FileSystem.exists(temporary)) {
			if (FileSystem.isDirectory(temporary))
				throw 'Cannot clear OCaml artifact manifest temporary path because "$temporary" is a directory.';
			FileSystem.deleteFile(temporary);
		}
	}

	function pruneEmptyParents(directory:String):Void {
		var current = directory;
		final root = Path.normalize(outputDirectory);
		while (current != null && current.length > 0 && Path.normalize(current) != root) {
			if (!FileSystem.exists(current) || !FileSystem.isDirectory(current) || FileSystem.readDirectory(current).length > 0)
				return;
			FileSystem.deleteDirectory(current);
			current = Path.directory(current);
		}
	}

	inline function absolutePath(relative:String):String {
		return Path.join([outputDirectory, relative]);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
