package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactClaim;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.reuse.OcamlSourceBundleCandidate.OcamlSourceBundleIndexEntry;
import reflaxe.output.OutputMetadataCodec;
import reflaxe.output.OutputManager.OutputMetadata;
import sys.FileSystem;
import sys.io.File;

/** Result of replaying one opaque candidate into a disposable private tree. **/
typedef OcamlSourceBundleShadowReplayResult = {
	final status:String;
	final equal:Bool;
	final mismatchReason:Null<String>;
	final replayAndValidationMilliseconds:Int;
	final receiptSemanticsEqual:Bool;
	final artifactManifestEqual:Bool;
}

/**
	Reconstructs one packed source bundle without publishing it.

	The shadow consumes a freshly decoded opaque payload. It writes stable files,
	regenerates the framework receipt from the current receipt identity and the
	payload's framework-owned set, rebuilds the target manifest from immutable
	claims and current authorities, validates every byte, and then deletes the
	private tree.
**/
class OcamlSourceBundleShadowReplay {
	public static inline final STATUS = "stable-source-equal";

	/** Replays, validates, compares, and removes one private shadow directory. **/
	public static function run(candidate:OcamlSourceBundleCandidate, normalOutputDirectory:String):OcamlSourceBundleShadowReplayResult {
		final started = haxe.Timer.stamp();
		final decoded = OcamlSourceBundleCandidate.decode(candidate.copyPayload());
		final shadowDirectory = createShadowDirectory(normalOutputDirectory, decoded.targetRequestRevision);
		try {
			final result = replay(decoded, normalOutputDirectory, shadowDirectory, started);
			deleteTree(shadowDirectory);
			return result;
		} catch (error:Dynamic) {
			deleteTree(shadowDirectory);
			throw error;
		}
	}

	static function replay(candidate:OcamlSourceBundleCandidate, normalOutputDirectory:String, shadowDirectory:String,
			started:Float):OcamlSourceBundleShadowReplayResult {
		final frameworkPaths = new Array<String>();
		for (entry in candidate.entries) {
			writeFile(shadowDirectory, entry.path, candidate.copyFile(entry));
			if (entry.owner == "reflaxe-framework")
				frameworkPaths.push(entry.path);
		}
		frameworkPaths.sort(compareStrings);

		final normalReceiptPath = Path.join([normalOutputDirectory, OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT]);
		final normalReceipt = OutputMetadataCodec.decode(File.getContent(normalReceiptPath), normalReceiptPath);
		final receipt:OutputMetadata = {
			version: normalReceipt.version,
			id: normalReceipt.id,
			wasCached: false,
			filesGenerated: frameworkPaths
		};
		final receiptPath = Path.join([shadowDirectory, OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT]);
		File.saveContent(receiptPath, OutputMetadataCodec.encode(receipt));
		final regeneratedReceipt = OutputMetadataCodec.decode(File.getContent(receiptPath), receiptPath);
		final receiptSemanticsEqual = receiptEquals(normalReceipt, regeneratedReceipt);
		if (!receiptSemanticsEqual)
			throw "OCaml source-bundle shadow receipt does not match normal generation.";

		final artifacts = new OcamlArtifactManifestBuilder(shadowDirectory, candidate.programRevision, candidate.configurationRevision, candidate.profile);
		for (entry in candidate.entries) {
			if (entry.owner == "reflaxe-framework")
				continue;
			artifacts.record(toClaim(entry));
		}
		artifacts.recordFrameworkModules();
		final report = artifacts.seal(candidate.semanticRuntimeAuthority, candidate.nativeDependenciesAuthority);
		if (!report.summary.completeForSourceBundle || report.summary.sourceBundleRevision != candidate.sourceBundleRevision)
			throw "OCaml source-bundle shadow manifest does not match the packed source revision.";
		final artifactManifestEqual = entriesEqual(candidate.entries, report.entries);
		if (!artifactManifestEqual)
			throw "OCaml source-bundle shadow manifest claims do not match the packed candidate.";
		OcamlArtifactManifestSchema.loadAndValidate(shadowDirectory, candidate.programRevision, candidate.configurationRevision);
		return {
			status: STATUS,
			equal: true,
			mismatchReason: null,
			replayAndValidationMilliseconds: elapsedMilliseconds(started),
			receiptSemanticsEqual: receiptSemanticsEqual,
			artifactManifestEqual: artifactManifestEqual
		};
	}

	static function toClaim(entry:OcamlSourceBundleIndexEntry):OcamlArtifactClaim {
		return {
			path: entry.path,
			kind: cast entry.kind,
			owner: cast entry.owner,
			sourceKind: cast entry.sourceKind,
			sourcePath: entry.sourcePath,
			license: entry.license,
			profileEligibility: entry.profileEligibility.copy(),
			stability: cast entry.stability,
			includeInSourceBundle: entry.includeInSourceBundle
		};
	}

	static function receiptEquals(left:OutputMetadata, right:OutputMetadata):Bool {
		if (left.version != right.version
			|| left.id != right.id
			|| left.wasCached != right.wasCached
			|| left.filesGenerated.length != right.filesGenerated.length)
			return false;
		for (index in 0...left.filesGenerated.length) {
			if (left.filesGenerated[index] != right.filesGenerated[index])
				return false;
		}
		return true;
	}

	static function entriesEqual(left:Array<OcamlSourceBundleIndexEntry>, right:Array<OcamlArtifactEntry>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			final a = left[index];
			final b = right[index];
			if (a.path != b.path
				|| a.bytes != b.bytes
				|| a.sha256 != b.sha256
				|| a.kind != b.kind
				|| a.owner != b.owner
				|| a.sourceKind != b.sourceKind
				|| a.sourcePath != b.sourcePath
				|| a.license != b.license
				|| a.stability != b.stability
				|| a.includeInSourceBundle != b.includeInSourceBundle
				|| !stringsEqual(a.profileEligibility, b.profileEligibility))
				return false;
		}
		return true;
	}

	static function stringsEqual(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			if (left[index] != right[index])
				return false;
		}
		return true;
	}

	static function createShadowDirectory(normalOutputDirectory:String, targetRequestRevision:String):String {
		final absolute = Path.normalize(FileSystem.absolutePath(normalOutputDirectory));
		final parent = Path.directory(absolute);
		final name = Path.withoutDirectory(absolute);
		final nonce = Sha256.encode(targetRequestRevision + ":" + Std.string(haxe.Timer.stamp())).substr(0, 16);
		final shadow = Path.join([parent, '.$name.reflaxe-ocaml-shadow-$nonce']);
		if (FileSystem.exists(shadow))
			throw "OCaml source-bundle shadow path already exists.";
		FileSystem.createDirectory(shadow);
		return shadow;
	}

	static function writeFile(root:String, relative:String, bytes:haxe.io.Bytes):Void {
		final path = Path.join([root, OcamlArtifactManifestSchema.normalizeRelativePath(relative)]);
		ensureDirectory(Path.directory(path));
		File.saveBytes(path, bytes);
	}

	static function ensureDirectory(path:String):Void {
		if (FileSystem.exists(path)) {
			if (!FileSystem.isDirectory(path))
				throw "OCaml source-bundle shadow parent is not a directory.";
			return;
		}
		final parent = Path.directory(path);
		if (parent != path && parent.length > 0)
			ensureDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		try {
			FileSystem.deleteFile(path);
			return;
		} catch (_:Dynamic) {}
		if (!FileSystem.isDirectory(path))
			throw "OCaml source-bundle shadow cleanup could not remove an owned path.";
		for (entry in FileSystem.readDirectory(path))
			deleteTree(Path.join([path, entry]));
		FileSystem.deleteDirectory(path);
	}

	static function elapsedMilliseconds(started:Float):Int {
		final value = Std.int((haxe.Timer.stamp() - started) * 1000.0);
		return value < 0 ? 0 : value;
	}

	static function compareStrings(left:String, right:String):Int
		return Reflect.compare(left, right);
}
#end
