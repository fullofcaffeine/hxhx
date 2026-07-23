/**
	Provides source files and parsed modules to one compiler request.

	ResolverStage and ModuleLoader both need to find an exact-case Haxe module,
	read its source, and parse source after conditional-compilation filtering.
	Keeping those operations behind one request-scoped object gives the native
	server one place to add validated reuse without making the resolver, typer, or
	target emitter own cache policy.

	This is deliberately one concrete class rather than a Haxe interface. Current
	Reflaxe OCaml interface dispatch casts concrete object records to a different
	field layout, which is unsafe when the concrete class stores its own data. A
	server request supplies typed callbacks instead; direct builds use the ordinary
	filesystem/parser implementation.
**/
class CompilerSourceProvider {
	var resolveModuleCallback:(classPaths:Array<String>, modulePath:String) -> CompilerModuleResolution;
	var readSourceCallback:(filePath:String) -> Null<String>;
	var parseFilteredSourceCallback:(filteredSource:String, filePath:String) -> ParsedModule;
	var readDirectoryCallback:(path:String) -> Array<String>;
	var isFileCallback:(path:String) -> Bool;
	var prepareFinishCallback:(requestSucceeded:Bool) -> Void;
	var finishCallback:(requestSucceeded:Bool) -> Void;
	var reportCallback:() -> CompilerSourceProviderReport;

	/** Create the uncached provider used by a direct compiler request. **/
	public function new() {
		final filesystem = new FilesystemCompilerSourceProvider();
		readSourceCallback = filesystem.readSource;
		parseFilteredSourceCallback = filesystem.parseFilteredSource;
		readDirectoryCallback = filesystem.readDirectory;
		isFileCallback = filesystem.isFile;
		prepareFinishCallback = filesystem.prepareFinish;
		finishCallback = filesystem.finish;
		reportCallback = filesystem.report;
		resolveModuleCallback = (classPaths, modulePath) -> CompilerSourceResolver.resolve(readDirectoryCallback, isFileCallback, classPaths, modulePath);
	}

	/**
		Create a provider backed by one server request's validated cache view.

		The callbacks are a typed adapter boundary, not a second compiler owner.
		They may reuse values only after their identities and lifetimes are checked.
	**/
	public static function fromCallbacks(resolveModule:(classPaths:Array<String>, modulePath:String) -> CompilerModuleResolution,
			readSource:(filePath:String) -> Null<String>, parseFilteredSource:(filteredSource:String, filePath:String) -> ParsedModule,
			readDirectory:(path:String) -> Array<String>, isFile:(path:String) -> Bool, prepareFinish:(requestSucceeded:Bool) -> Void,
			finish:(requestSucceeded:Bool) -> Void, report:() -> CompilerSourceProviderReport):CompilerSourceProvider {
		if (resolveModule == null || readSource == null || parseFilteredSource == null || readDirectory == null || isFile == null || finish == null
			|| prepareFinish == null || report == null)
			throw "compiler source provider callbacks must all be present";
		final provider = new CompilerSourceProvider();
		provider.resolveModuleCallback = resolveModule;
		provider.readSourceCallback = readSource;
		provider.parseFilteredSourceCallback = parseFilteredSource;
		provider.readDirectoryCallback = readDirectory;
		provider.isFileCallback = isFile;
		provider.prepareFinishCallback = prepareFinish;
		provider.finishCallback = finish;
		provider.reportCallback = report;
		return provider;
	}

	/** Resolve a Haxe module and preserve the exact path-selection facts. **/
	public function resolveModule(classPaths:Array<String>, modulePath:String):CompilerModuleResolution {
		return resolveModuleCallback(classPaths, modulePath);
	}

	/** Convenience view for existence checks that do not construct a resolved module. **/
	public function resolveModuleFile(classPaths:Array<String>, modulePath:String):Null<String> {
		return resolveModule(classPaths, modulePath).filePath;
	}

	/** Read one selected source file, or return null when it cannot be read. **/
	public function readSource(filePath:String):Null<String> {
		return readSourceCallback(filePath);
	}

	/** Parse source after the caller has applied the effective conditional defines. **/
	public function parseFilteredSource(filteredSource:String, filePath:String):ParsedModule {
		return parseFilteredSourceCallback(filteredSource, filePath);
	}

	/** Read the directory entries visible at this point in the request. **/
	public function readDirectory(path:String):Array<String> {
		return readDirectoryCallback(path);
	}

	/** Return whether the path currently names a regular source file. **/
	public function isFile(path:String):Bool {
		return isFileCallback(path);
	}

	/** Validate successful-request candidates before generated output becomes visible. **/
	public function prepareFinish(requestSucceeded:Bool):Void {
		prepareFinishCallback(requestSucceeded);
	}

	/** Publish complete reusable values after output succeeds, or discard candidates. **/
	public function finish(requestSucceeded:Bool):Void {
		finishCallback(requestSucceeded);
	}

	/** Return truthful request-local cache measurements without changing decisions. **/
	public function report():CompilerSourceProviderReport {
		return reportCallback();
	}
}
