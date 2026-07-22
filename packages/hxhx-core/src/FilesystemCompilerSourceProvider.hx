/**
	Uncached filesystem/parser provider used by direct builds and as the cache miss path.

	Filesystem observations are taken when requested. A macro or another compiler
	step may create a source directory or file during the same request, so this
	provider must not retain an earlier missing-directory result.
**/
class FilesystemCompilerSourceProvider {
	final providerReport:CompilerSourceProviderReport;

	public function new() {
		providerReport = new CompilerSourceProviderReport(false);
	}

	public function readSource(filePath:String):Null<String> {
		if (filePath == null || filePath.length == 0)
			return null;
		return try {
			if (!sys.FileSystem.exists(filePath) || sys.FileSystem.isDirectory(filePath))
				null;
			else
				sys.io.File.getContent(filePath);
		} catch (_:haxe.io.Error) {
			null;
		} catch (_:String) {
			null;
		}
	}

	public function parseFilteredSource(filteredSource:String, filePath:String):ParsedModule {
		return ParserStage.parse(filteredSource, filePath);
	}

	public function readDirectory(path:String):Array<String> {
		if (path == null || path.length == 0)
			return [];
		final entries = try {
			if (!sys.FileSystem.exists(path) || !sys.FileSystem.isDirectory(path))
				[];
			else
				sys.FileSystem.readDirectory(path);
		} catch (_:haxe.io.Error) {
			[];
		} catch (_:String) {
			[];
		}
		entries.sort(compareStrings);
		return entries;
	}

	public function isFile(path:String):Bool {
		if (path == null || path.length == 0)
			return false;
		return try {
			sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path);
		} catch (_:haxe.io.Error) {
			false;
		} catch (_:String) {
			false;
		}}

	public function prepareFinish(_requestSucceeded:Bool):Void {}

	public function finish(_requestSucceeded:Bool):Void {}

	public function report():CompilerSourceProviderReport
		return providerReport;

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
