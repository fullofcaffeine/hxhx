package hxhx;

import haxe.io.Bytes;
import haxe.io.Path;

/**
	Request-owned view of the long-lived source/module-lookup/parser cache.

	The provider may borrow validated entries, but it stages every observed entry
	until the request finishes successfully. Failed or cancelled requests discard
	their staged values. Parser integrity is checked before publication and reuse.
**/
class CompilationServerSourceCacheRequest {
	final findSourceCallback:(key:String) -> Null<CompilationServerCachedSource>;
	final findParsedCallback:(key:String) -> Null<CompilationServerCachedParse>;
	final findResolutionCallback:(key:String) -> Null<CompilationServerCachedResolution>;
	final sourceMissReasonCallback:(logicalPath:String, contentRevision:String) -> String;
	final parserMissReasonCallback:(logicalPath:String, inputRevision:String) -> String;
	final resolutionMissReasonCallback:(lookupIdentity:String, key:String, filePath:Null<String>) -> String;
	final quarantineParsedCallback:(key:String) -> Void;
	final publishCallback:(sources:Array<CompilationServerCachedSource>, parsedModules:Array<CompilationServerCachedParse>,
		resolutions:Array<CompilationServerCachedResolution>, report:CompilerSourceProviderReport) -> Void;
	final snapshotReportStateCallback:(report:CompilerSourceProviderReport) -> Void;
	final filesystem:FilesystemCompilerSourceProvider;
	final providerReport:CompilerSourceProviderReport;
	final stagedSources:haxe.ds.StringMap<CompilationServerCachedSource>;
	final stagedParsedModules:haxe.ds.StringMap<CompilationServerCachedParse>;
	final stagedResolutions:haxe.ds.StringMap<CompilationServerCachedResolution>;
	var providerView:Null<CompilerSourceProvider>;
	var preparedForSuccess:Bool;
	var finished:Bool;

	public function new(findSource:(key:String) -> Null<CompilationServerCachedSource>, findParsed:(key:String) -> Null<CompilationServerCachedParse>,
			findResolution:(key:String) -> Null<CompilationServerCachedResolution>, sourceMissReason:(logicalPath:String, contentRevision:String) -> String,
			parserMissReason:(logicalPath:String, inputRevision:String) -> String,
			resolutionMissReason:(lookupIdentity:String, key:String, filePath:Null<String>) -> String, quarantineParsed:(key:String) -> Void,
			publish:(sources:Array<CompilationServerCachedSource>, parsedModules:Array<CompilationServerCachedParse>,
			resolutions:Array<CompilationServerCachedResolution>, report:CompilerSourceProviderReport) -> Void,
			snapshotReportState:(report:CompilerSourceProviderReport) -> Void) {
		findSourceCallback = findSource;
		findParsedCallback = findParsed;
		findResolutionCallback = findResolution;
		sourceMissReasonCallback = sourceMissReason;
		parserMissReasonCallback = parserMissReason;
		resolutionMissReasonCallback = resolutionMissReason;
		quarantineParsedCallback = quarantineParsed;
		publishCallback = publish;
		snapshotReportStateCallback = snapshotReportState;
		filesystem = new FilesystemCompilerSourceProvider();
		providerReport = new CompilerSourceProviderReport(true);
		stagedSources = new haxe.ds.StringMap<CompilationServerCachedSource>();
		stagedParsedModules = new haxe.ds.StringMap<CompilationServerCachedParse>();
		stagedResolutions = new haxe.ds.StringMap<CompilationServerCachedResolution>();
		providerView = null;
		preparedForSuccess = false;
		finished = false;
	}

	public function provider():CompilerSourceProvider {
		if (providerView == null)
			providerView = CompilerSourceProvider.fromCallbacks(resolveModule, readSource, parseFilteredSource, readDirectory, isFile, prepareFinish, finish,
				report);
		return providerView;
	}

	public function resolveModule(classPaths:Array<String>, modulePath:String):CompilerModuleResolution {
		ensureOpen();
		final resolution = CompilerSourceResolver.resolve(readDirectory, isFile, classPaths, modulePath);
		final key = CompilerCacheIdentity.encode(["resolution-entry-v2", resolution.lookupIdentity, resolution.observationRevision]);
		final staged = stagedResolutions.get(key);
		if (staged != null) {
			assertResolutionMatches(staged, resolution);
			return resolution;
		}
		final cached = findResolutionCallback(key);
		if (cached != null) {
			assertResolutionMatches(cached, resolution);
			stagedResolutions.set(key, cached);
			providerReport.recordResolutionHit();
			return resolution;
		}

		providerReport.recordResolutionMiss(resolutionMissReasonCallback(resolution.lookupIdentity, key, resolution.filePath));
		final retainedBytesEstimate = resolution.lookupIdentity.length
			+ resolution.observationRevision.length
			+ (resolution.filePath == null ? 0 : resolution.filePath.length)
			+ 256;
		stagedResolutions.set(key,
			new CompilationServerCachedResolution(key, resolution.lookupIdentity, resolution.observationRevision, resolution.filePath,
				resolution.selectedClassPathIndex, resolution.usedSecondaryTypeFallback, retainedBytesEstimate));
		return resolution;
	}

	public function resolveModuleFile(classPaths:Array<String>, modulePath:String):Null<String>
		return resolveModule(classPaths, modulePath).filePath;

	public function readSource(filePath:String):Null<String> {
		ensureOpen();
		if (filePath == null || filePath.length == 0)
			return null;
		if (!filesystem.isFile(filePath))
			return null;
		final bytes = try {
			sys.io.File.getBytes(filePath);
		} catch (_:haxe.io.Error) {
			return null;
		} catch (_:String) {
			return null;
		}
		providerReport.recordSourceBytesRead(bytes.length);
		final logicalPath = normalizePath(filePath);
		final source = bytes.getString(0, bytes.length);
		final contentRevision = CompilerCacheIdentity.encode(["source-content-v2", source]);
		final key = CompilerCacheIdentity.encode(["source-entry-v2", logicalPath, contentRevision]);
		final staged = stagedSources.get(key);
		if (staged != null) {
			return staged.source;
		}
		final cached = findSourceCallback(key);
		if (cached != null) {
			stagedSources.set(key, cached);
			providerReport.recordSourceHit();
			return cached.source;
		}

		providerReport.recordSourceMiss(sourceMissReasonCallback(logicalPath, contentRevision));
		final retainedBytesEstimate = bytes.length + key.length * 2 + 256;
		stagedSources.set(key, new CompilationServerCachedSource(key, logicalPath, contentRevision, source, retainedBytesEstimate));
		return source;
	}

	public function parseFilteredSource(filteredSource:String, filePath:String):ParsedModule {
		ensureOpen();
		final logicalPath = normalizePath(filePath);
		final parserConfiguration = ParserStage.cacheConfigurationRevision();
		final inputRevision = CompilerCacheIdentity.encode(["parser-input-v2", logicalPath, parserConfiguration, filteredSource]);
		final key = inputRevision;
		final staged = stagedParsedModules.get(key);
		if (staged != null) {
			assertParsedIntegrity(staged);
			return staged.parsed;
		}
		final cached = findParsedCallback(key);
		if (cached != null) {
			try {
				assertParsedIntegrity(cached);
			} catch (error:String) {
				quarantineParsedCallback(key);
				throw error;
			}
			stagedParsedModules.set(key, cached);
			providerReport.recordParserHit();
			return cached.parsed;
		}

		providerReport.recordParserMiss(parserMissReasonCallback(logicalPath, inputRevision));
		final parsed = filesystem.parseFilteredSource(filteredSource, filePath);
		final integrityRevision = ParsedModuleIntegrity.revision(parsed);
		final retainedBytesEstimate = Bytes.ofString(filteredSource).length * 2 + key.length * 2 + integrityRevision.length * 2 + 1024;
		stagedParsedModules.set(key, new CompilationServerCachedParse(key, logicalPath, inputRevision, parsed, integrityRevision, retainedBytesEstimate));
		return parsed;
	}

	public function readDirectory(path:String):Array<String> {
		ensureOpen();
		return filesystem.readDirectory(path);
	}

	public function isFile(path:String):Bool {
		ensureOpen();
		return filesystem.isFile(path);
	}

	/** Validate candidate parser trees before the output transaction commits. **/
	public function prepareFinish(requestSucceeded:Bool):Void {
		ensureOpen();
		if (!requestSucceeded || preparedForSuccess)
			return;
		for (entry in parsedValues())
			assertParsedIntegrityOrQuarantine(entry);
		preparedForSuccess = true;
	}

	public function finish(requestSucceeded:Bool):Void {
		if (finished)
			return;
		if (!requestSucceeded) {
			closeRequest(false);
			return;
		}
		try {
			prepareFinish(true);
			publishCallback(sourceValues(), parsedValues(), resolutionValues(), providerReport);
		} catch (error:haxe.Exception) {
			closeRequest(false);
			throw error;
		} catch (error:String) {
			closeRequest(false);
			throw error;
		}
		closeRequest(true);
	}

	function closeRequest(succeeded:Bool):Void {
		finished = true;
		if (!succeeded)
			snapshotReportStateCallback(providerReport);
		stagedSources.clear();
		stagedParsedModules.clear();
		stagedResolutions.clear();
		filesystem.finish(succeeded);
	}

	public function report():CompilerSourceProviderReport
		return providerReport;

	function ensureOpen():Void {
		if (finished)
			throw "compiler source provider is already closed";
	}

	function sourceValues():Array<CompilationServerCachedSource> {
		final values = new Array<CompilationServerCachedSource>();
		for (entry in stagedSources)
			values.push(entry);
		values.sort((left, right) -> left.key < right.key ? -1 : (left.key > right.key ? 1 : 0));
		return values;
	}

	function parsedValues():Array<CompilationServerCachedParse> {
		final values = new Array<CompilationServerCachedParse>();
		for (entry in stagedParsedModules)
			values.push(entry);
		values.sort((left, right) -> left.key < right.key ? -1 : (left.key > right.key ? 1 : 0));
		return values;
	}

	function resolutionValues():Array<CompilationServerCachedResolution> {
		final values = new Array<CompilationServerCachedResolution>();
		for (entry in stagedResolutions)
			values.push(entry);
		values.sort((left, right) -> left.key < right.key ? -1 : (left.key > right.key ? 1 : 0));
		return values;
	}

	static function assertParsedIntegrity(entry:CompilationServerCachedParse):Void {
		final current = ParsedModuleIntegrity.revision(entry.parsed);
		if (current != entry.integrityRevision)
			throw "hxhx: parsed module changed after the cache recorded it; refusing to reuse it";
	}

	function assertParsedIntegrityOrQuarantine(entry:CompilationServerCachedParse):Void {
		try {
			assertParsedIntegrity(entry);
		} catch (error:String) {
			quarantineParsedCallback(entry.key);
			throw error;
		}
	}

	static function assertResolutionMatches(entry:CompilationServerCachedResolution, resolution:CompilerModuleResolution):Void {
		if (entry.lookupIdentity != resolution.lookupIdentity
			|| entry.observationRevision != resolution.observationRevision
			|| entry.filePath != resolution.filePath
			|| entry.selectedClassPathIndex != resolution.selectedClassPathIndex
			|| entry.usedSecondaryTypeFallback != resolution.usedSecondaryTypeFallback)
			throw "hxhx: cached module lookup does not match current filesystem observations";
	}

	static function normalizePath(path:String):String {
		return Path.normalize(sys.FileSystem.absolutePath(path));
	}
}
