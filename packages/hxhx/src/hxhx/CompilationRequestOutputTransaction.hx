package hxhx;

import backend.EmitArtifact;
import backend.EmitResult;
import haxe.io.Path;
import sys.FileSystem;

private typedef CompilationOutputRoot = {
	final finalPath:String;
	final stagedPath:String;
}

private typedef CompilationOutputPublication = {
	final finalPath:String;
	final stagedPath:String;
	final backupPath:String;
	var backedUp:Bool;
	var published:Bool;
}

/**
	Stages filesystem output for one server request and publishes it after success.

	Directory outputs are rendered into a sibling staging tree. File-oriented
	targets render into a private directory so related files such as `app.js.map`
	travel with the requested `app.js`. Publication first moves previous outputs
	to private backups, then renames completed staged outputs into place. A failed
	request deletes staging and leaves the prior output untouched.

	The transaction owns paths and filesystem replacement only. Backends still
	decide which artifacts to create, and `CompilationRequestContext` owns when a
	request may publish or must abort.
**/
class CompilationRequestOutputTransaction {
	static final PROCESS_TOKEN:String = pathToken(Std.string(Date.now().getTime()) + "-" + Std.string(haxe.Timer.stamp()));

	final requestId:Int;
	final directoryRoots:Array<CompilationOutputRoot>;
	final fileBundleRoot:Null<CompilationOutputRoot>;
	final outputPathsValue:CompilationRequestOutputPaths;
	final retainedBackups:Array<String>;
	var state:String;

	public function new(requestId:Int, outDir:String, backendOutputDir:String, outputFileHint:Null<String>) {
		this.requestId = requestId;
		this.directoryRoots = [];
		this.retainedBackups = [];
		this.state = "staged";

		final finalOutDir = absolute(outDir);
		final finalBackendOutputDir = absolute(backendOutputDir);
		final finalOutputFileHint = outputFileHint == null ? null : absolute(outputFileHint);
		final directoryCandidates = [finalOutDir, finalBackendOutputDir];
		directoryCandidates.sort(compareShortestPathFirst);
		var rootIndex = 0;
		for (candidate in directoryCandidates) {
			if (findContainingRoot(candidate) != null)
				continue;
			directoryRoots.push(createRoot(candidate, rootIndex));
			rootIndex += 1;
		}

		var bundle:Null<CompilationOutputRoot> = null;
		if (finalOutputFileHint != null) {
			final containingRoot = findContainingRoot(finalOutputFileHint);
			if (containingRoot != null && comparisonPath(finalOutputFileHint) == comparisonPath(containingRoot.finalPath))
				throw 'compiler output file conflicts with output directory: $finalOutputFileHint';
			if (containingRoot == null) {
				final finalParent = normalizedParent(finalOutputFileHint);
				final stagedContainer = createStagingPath(finalParent, rootIndex);
				bundle = {finalPath: finalParent, stagedPath: stagedContainer};
			}
		}
		this.fileBundleRoot = bundle;
		this.outputPathsValue = new CompilationRequestOutputPaths(finalOutDir, mapDirectory(finalOutDir), finalBackendOutputDir,
			mapDirectory(finalBackendOutputDir), finalOutputFileHint, finalOutputFileHint == null ? null : mapFile(finalOutputFileHint));
	}

	public function outputPaths():CompilationRequestOutputPaths {
		return outputPathsValue;
	}

	public function status():String {
		return state;
	}

	/** Replace prior outputs with the completed staging trees. **/
	public function publish():Void {
		if (state != "staged")
			throw 'compiler request output transaction cannot publish from state $state';
		final publications = collectPublications();
		final createdParents = new Array<String>();
		var failure:Null<String> = null;
		try {
			for (publication in publications) {
				ensureDirectory(normalizedParent(publication.finalPath), createdParents);
				if (FileSystem.exists(publication.backupPath))
					throw 'stale output backup already exists: ${publication.backupPath}';
				if (FileSystem.exists(publication.finalPath)) {
					FileSystem.rename(publication.finalPath, publication.backupPath);
					publication.backedUp = true;
					retainedBackups.push(publication.backupPath);
				}
			}
			for (publication in publications) {
				FileSystem.rename(publication.stagedPath, publication.finalPath);
				publication.published = true;
			}
			removeEmptyFileBundle();
			state = "committed";
		} catch (error:haxe.io.Error) {
			failure = Std.string(error);
		} catch (error:haxe.Exception) {
			failure = error.message;
		} catch (error:String) {
			failure = error;
		}

		if (failure != null) {
			final rollbackProblems = rollback(publications, createdParents);
			state = "aborted";
			throw "could not publish compiler output: " + failure + (rollbackProblems.length == 0 ? "" : "; rollback: " + rollbackProblems.join("; "));
		}

		cleanupRetainedBackups();
	}

	/**
		Delete unpublished staging output and any backup left after publication.

		This method is idempotent. The request context calls it after ordinary
		compiler, macro, and plugin cleanup has finished.
	**/
	public function close():Void {
		if (state == "staged") {
			for (root in directoryRoots)
				deleteTree(root.stagedPath);
			if (fileBundleRoot != null)
				deleteTree(fileBundleRoot.stagedPath);
			state = "aborted";
		}
		cleanupRetainedBackups();
	}

	/** Convert paths returned by a backend from staging names to client names. **/
	public function finalEmitResult(result:EmitResult):EmitResult {
		if (result == null)
			throw "compiler backend returned no emission result";
		return new EmitResult(toFinalPath(result.entryPath), [
			for (artifact in result.artifacts)
				new EmitArtifact(artifact.kind, toFinalPath(artifact.path))
		], result.builtExecutable);
	}

	public function toFinalPath(path:String):String {
		if (path == null || path.length == 0)
			throw "compiler backend returned an empty output path";
		final normalized = absolute(path);
		for (root in directoryRoots) {
			if (isWithin(normalized, root.stagedPath))
				return appendRelative(root.finalPath, relativeTo(normalized, root.stagedPath));
		}
		if (fileBundleRoot != null && isWithin(normalized, fileBundleRoot.stagedPath))
			return appendRelative(fileBundleRoot.finalPath, relativeTo(normalized, fileBundleRoot.stagedPath));
		throw 'compiler backend returned output outside request staging: $normalized';
	}

	function mapDirectory(finalPath:String):String {
		final root = findContainingRoot(finalPath);
		if (root == null)
			throw 'compiler output directory has no transaction root: $finalPath';
		return appendRelative(root.stagedPath, relativeTo(finalPath, root.finalPath));
	}

	function mapFile(finalPath:String):String {
		final root = findContainingRoot(finalPath);
		if (root != null)
			return appendRelative(root.stagedPath, relativeTo(finalPath, root.finalPath));
		if (fileBundleRoot == null)
			throw 'compiler output file has no transaction bundle: $finalPath';
		return Path.join([fileBundleRoot.stagedPath, Path.withoutDirectory(finalPath)]);
	}

	function findContainingRoot(path:String):Null<CompilationOutputRoot> {
		for (root in directoryRoots)
			if (isWithin(path, root.finalPath))
				return root;
		return null;
	}

	function createRoot(finalPath:String, index:Int):CompilationOutputRoot {
		return {finalPath: finalPath, stagedPath: createStagingPath(normalizedParent(finalPath), index)};
	}

	function createStagingPath(preferredParent:String, index:Int):String {
		final stagingParent = nearestExistingDirectory(preferredParent);
		final stagedPath = Path.join([stagingParent, '.hxhx-server-stage-$PROCESS_TOKEN-$requestId-$index']);
		if (FileSystem.exists(stagedPath))
			throw 'stale compiler output staging path already exists: $stagedPath';
		return stagedPath;
	}

	function collectPublications():Array<CompilationOutputPublication> {
		final publications = new Array<CompilationOutputPublication>();
		for (root in directoryRoots) {
			if (!FileSystem.exists(root.stagedPath))
				continue;
			if (!FileSystem.isDirectory(root.stagedPath))
				throw 'compiler directory staging path is not a directory: ${root.stagedPath}';
			publications.push(publication(root.stagedPath, root.finalPath, publications.length));
		}
		if (fileBundleRoot != null && FileSystem.exists(fileBundleRoot.stagedPath)) {
			if (!FileSystem.isDirectory(fileBundleRoot.stagedPath))
				throw 'compiler file staging path is not a directory: ${fileBundleRoot.stagedPath}';
			final entries = FileSystem.readDirectory(fileBundleRoot.stagedPath);
			entries.sort(comparePathNames);
			for (entry in entries) {
				publications.push(publication(Path.join([fileBundleRoot.stagedPath, entry]), Path.join([fileBundleRoot.finalPath, entry]),
					publications.length));
			}
		}
		return publications;
	}

	function publication(stagedPath:String, finalPath:String, index:Int):CompilationOutputPublication {
		final backupPath = Path.join([
			normalizedParent(finalPath),
			'.hxhx-server-backup-$PROCESS_TOKEN-$requestId-$index'
		]);
		return {
			finalPath: finalPath,
			stagedPath: stagedPath,
			backupPath: backupPath,
			backedUp: false,
			published: false
		};
	}

	function rollback(publications:Array<CompilationOutputPublication>, createdParents:Array<String>):Array<String> {
		final problems = new Array<String>();
		var index = publications.length;
		while (index > 0) {
			index -= 1;
			final publication = publications[index];
			if (publication.published && FileSystem.exists(publication.finalPath))
				captureProblem('delete partial output ${publication.finalPath}', () -> deleteTree(publication.finalPath), problems);
			if (publication.backedUp && FileSystem.exists(publication.backupPath)) {
				captureProblem('restore previous output ${publication.finalPath}', () -> FileSystem.rename(publication.backupPath, publication.finalPath),
					problems);
				retainedBackups.remove(publication.backupPath);
			}
		}
		for (root in directoryRoots)
			captureProblem('delete staging ${root.stagedPath}', () -> deleteTree(root.stagedPath), problems);
		if (fileBundleRoot != null)
			captureProblem('delete staging ${fileBundleRoot.stagedPath}', () -> deleteTree(fileBundleRoot.stagedPath), problems);
		removeCreatedParents(createdParents, problems);
		return problems;
	}

	function removeEmptyFileBundle():Void {
		if (fileBundleRoot != null && FileSystem.exists(fileBundleRoot.stagedPath))
			FileSystem.deleteDirectory(fileBundleRoot.stagedPath);
	}

	function cleanupRetainedBackups():Void {
		for (backup in retainedBackups.copy()) {
			if (FileSystem.exists(backup))
				deleteTree(backup);
			retainedBackups.remove(backup);
		}
	}

	static function captureProblem(label:String, action:() -> Void, problems:Array<String>):Void {
		try {
			action();
		} catch (error:haxe.io.Error) {
			problems.push(label + ": " + Std.string(error));
		} catch (error:haxe.Exception) {
			problems.push(label + ": " + error.message);
		} catch (error:String) {
			problems.push(label + ": " + error);
		}
	}

	static function ensureDirectory(path:String, created:Array<String>):Void {
		if (FileSystem.exists(path)) {
			if (!FileSystem.isDirectory(path))
				throw 'compiler output parent is not a directory: $path';
			return;
		}
		final missing = new Array<String>();
		var cursor = path;
		while (!FileSystem.exists(cursor)) {
			missing.push(cursor);
			final parent = normalizedParent(cursor);
			if (parent == cursor)
				throw 'compiler output path has no existing directory ancestor: $path';
			cursor = parent;
		}
		if (!FileSystem.isDirectory(cursor))
			throw 'compiler output ancestor is not a directory: $cursor';
		missing.reverse();
		for (directory in missing) {
			FileSystem.createDirectory(directory);
			created.push(directory);
		}
	}

	static function removeCreatedParents(created:Array<String>, problems:Array<String>):Void {
		var index = created.length;
		while (index > 0) {
			index -= 1;
			final directory = created[index];
			if (!FileSystem.exists(directory) || !FileSystem.isDirectory(directory) || FileSystem.readDirectory(directory).length > 0)
				continue;
			captureProblem('delete transaction-created directory $directory', () -> FileSystem.deleteDirectory(directory), problems);
		}
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function nearestExistingDirectory(path:String):String {
		var cursor = absolute(path);
		while (!FileSystem.exists(cursor)) {
			final parent = normalizedParent(cursor);
			if (parent == cursor)
				throw 'compiler output path has no existing directory ancestor: $path';
			cursor = parent;
		}
		if (!FileSystem.isDirectory(cursor))
			throw 'compiler output ancestor is not a directory: $cursor';
		return cursor;
	}

	static function normalizedParent(path:String):String {
		final parent = Path.directory(path);
		return absolute(parent == null || parent.length == 0 ? "." : parent);
	}

	static function absolute(path:String):String {
		return Path.normalize(FileSystem.absolutePath(path));
	}

	static function comparisonPath(path:String):String {
		var normalized = StringTools.replace(absolute(path), "\\", "/");
		while (normalized.length > 1 && !isWindowsDriveRoot(normalized) && StringTools.endsWith(normalized, "/"))
			normalized = normalized.substr(0, normalized.length - 1);
		return normalized;
	}

	static function isWindowsDriveRoot(path:String):Bool {
		return path.length == 3 && path.charAt(1) == ":" && path.charAt(2) == "/";
	}

	static function isWithin(path:String, parent:String):Bool {
		final childValue = comparisonPath(path);
		final parentValue = comparisonPath(parent);
		return childValue == parentValue || StringTools.startsWith(childValue, parentValue + "/");
	}

	static function relativeTo(path:String, parent:String):String {
		final childValue = comparisonPath(path);
		final parentValue = comparisonPath(parent);
		if (childValue == parentValue)
			return "";
		if (!StringTools.startsWith(childValue, parentValue + "/"))
			throw '$path is not inside $parent';
		return childValue.substr(parentValue.length + 1);
	}

	static function appendRelative(parent:String, relative:String):String {
		return relative.length == 0 ? parent : Path.join([parent, relative]);
	}

	static function compareShortestPathFirst(left:String, right:String):Int {
		final leftValue = comparisonPath(left);
		final rightValue = comparisonPath(right);
		if (leftValue.length != rightValue.length)
			return leftValue.length - rightValue.length;
		return comparePathNames(leftValue, rightValue);
	}

	static function comparePathNames(left:String, right:String):Int {
		return left < right ? -1 : left > right ? 1 : 0;
	}

	static function pathToken(value:String):String {
		final out = new StringBuf();
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			out.addChar((code >= "0".code && code <= "9".code)
				|| (code >= "A".code && code <= "Z".code)
				|| (code >= "a".code && code <= "z".code) ? code : "_".code);
		}
		return out.toString();
	}
}
