package hxhx;

/**
	Long-lived owner of immutable source text, module lookup, and parser results.

	The catalog is created once per native wait server. Requests can read entries
	that passed exact identity and integrity checks, but they stage new entries
	locally. Only a successful request publishes staged values. Cache eviction is
	performed between serialized requests, never while a request is borrowing a
	parsed module.
**/
class CompilationServerSourceCache {
	static inline final DEFAULT_MAX_BYTES:Int = 64 * 1024 * 1024;
	static inline final MIN_MAX_BYTES:Int = 1024;

	final sourceEntries:haxe.ds.StringMap<CompilationServerCachedSource>;
	final parsedEntries:haxe.ds.StringMap<CompilationServerCachedParse>;
	final resolutionEntries:haxe.ds.StringMap<CompilationServerCachedResolution>;
	final accessTicks:haxe.ds.StringMap<Int>;
	final latestSourceRevisionByPath:haxe.ds.StringMap<String>;
	final latestParserInputByPath:haxe.ds.StringMap<String>;
	final latestResolutionKeyByLookup:haxe.ds.StringMap<String>;
	final latestResolutionPathByLookup:haxe.ds.StringMap<String>;
	final maxBytes:Int;
	var retainedBytesEstimate:Int;
	var accessTick:Int;
	var totalEvictions:Int;

	public function new(?maxBytes:Int) {
		this.maxBytes = normalizedMaxBytes(maxBytes);
		sourceEntries = new haxe.ds.StringMap<CompilationServerCachedSource>();
		parsedEntries = new haxe.ds.StringMap<CompilationServerCachedParse>();
		resolutionEntries = new haxe.ds.StringMap<CompilationServerCachedResolution>();
		accessTicks = new haxe.ds.StringMap<Int>();
		latestSourceRevisionByPath = new haxe.ds.StringMap<String>();
		latestParserInputByPath = new haxe.ds.StringMap<String>();
		latestResolutionKeyByLookup = new haxe.ds.StringMap<String>();
		latestResolutionPathByLookup = new haxe.ds.StringMap<String>();
		retainedBytesEstimate = 0;
		accessTick = 0;
		totalEvictions = 0;
	}

	public function openRequest():CompilerSourceProvider {
		final request = new CompilationServerSourceCacheRequest(findSource, findParsed, findResolution, sourceMissReason, parserMissReason,
			resolutionMissReason, quarantineParsed, publish, snapshotReportState);
		return request.provider();
	}

	/** Discard every reusable entry while keeping the wait server process alive. **/
	public function reset():Void {
		sourceEntries.clear();
		parsedEntries.clear();
		resolutionEntries.clear();
		accessTicks.clear();
		latestSourceRevisionByPath.clear();
		latestParserInputByPath.clear();
		latestResolutionKeyByLookup.clear();
		latestResolutionPathByLookup.clear();
		retainedBytesEstimate = 0;
		accessTick = 0;
		totalEvictions = 0;
	}

	public function findSource(key:String):Null<CompilationServerCachedSource> {
		final entry = sourceEntries.get(key);
		if (entry != null)
			touch("source:" + key);
		return entry;
	}

	public function findParsed(key:String):Null<CompilationServerCachedParse> {
		final entry = parsedEntries.get(key);
		if (entry != null)
			touch("parser:" + key);
		return entry;
	}

	public function findResolution(key:String):Null<CompilationServerCachedResolution> {
		final entry = resolutionEntries.get(key);
		if (entry != null)
			touch("resolution:" + key);
		return entry;
	}

	public function sourceMissReason(logicalPath:String, contentRevision:String):String {
		final previous = latestSourceRevisionByPath.get(logicalPath);
		if (previous == null)
			return "cold";
		return previous == contentRevision ? "evicted" : "source-changed";
	}

	public function parserMissReason(logicalPath:String, inputRevision:String):String {
		final previous = latestParserInputByPath.get(logicalPath);
		if (previous == null)
			return "cold";
		return previous == inputRevision ? "evicted" : "parser-input-changed";
	}

	public function resolutionMissReason(lookupIdentity:String, key:String, filePath:Null<String>):String {
		final previousKey = latestResolutionKeyByLookup.get(lookupIdentity);
		if (previousKey == null)
			return "cold";
		if (previousKey == key)
			return "evicted";
		final previousPath = latestResolutionPathByLookup.get(lookupIdentity);
		return previousPath == pathToken(filePath) ? "resolution-observations-changed" : "origin-shadowed";
	}

	public function quarantineParsed(key:String):Void {
		final entry = parsedEntries.get(key);
		if (entry == null)
			return;
		parsedEntries.remove(key);
		accessTicks.remove("parser:" + key);
		retainedBytesEstimate -= entry.retainedBytesEstimate;
		if (retainedBytesEstimate < 0)
			retainedBytesEstimate = 0;
	}

	/** Publish validated request entries, update recency, and evict to the configured estimate. **/
	public function publish(sources:Array<CompilationServerCachedSource>, parsedModules:Array<CompilationServerCachedParse>,
			resolutions:Array<CompilationServerCachedResolution>, report:CompilerSourceProviderReport):Void {
		final evictionsBefore = totalEvictions;
		for (entry in sources) {
			latestSourceRevisionByPath.set(entry.logicalPath, entry.contentRevision);
			if (sourceEntries.exists(entry.key)) {
				touch("source:" + entry.key);
				continue;
			}
			sourceEntries.set(entry.key, entry);
			retainedBytesEstimate += entry.retainedBytesEstimate;
			touch("source:" + entry.key);
		}
		for (entry in parsedModules) {
			latestParserInputByPath.set(entry.logicalPath, entry.inputRevision);
			if (parsedEntries.exists(entry.key)) {
				touch("parser:" + entry.key);
				continue;
			}
			parsedEntries.set(entry.key, entry);
			retainedBytesEstimate += entry.retainedBytesEstimate;
			touch("parser:" + entry.key);
		}
		for (entry in resolutions) {
			latestResolutionKeyByLookup.set(entry.lookupIdentity, entry.key);
			latestResolutionPathByLookup.set(entry.lookupIdentity, pathToken(entry.filePath));
			if (resolutionEntries.exists(entry.key)) {
				touch("resolution:" + entry.key);
				continue;
			}
			resolutionEntries.set(entry.key, entry);
			retainedBytesEstimate += entry.retainedBytesEstimate;
			touch("resolution:" + entry.key);
		}
		evictToBudget();
		updateReportState(report, totalEvictions - evictionsBefore);
	}

	public function snapshotReportState(report:CompilerSourceProviderReport):Void {
		updateReportState(report, 0);
	}

	function updateReportState(report:CompilerSourceProviderReport, requestEvictions:Int):Void {
		report.setRetainedState(entryCount(), retainedBytesEstimate, requestEvictions);
	}

	function entryCount():Int {
		var count = 0;
		for (_ in sourceEntries.keys())
			count += 1;
		for (_ in parsedEntries.keys())
			count += 1;
		for (_ in resolutionEntries.keys())
			count += 1;
		return count;
	}

	function touch(key:String):Void {
		accessTick += 1;
		accessTicks.set(key, accessTick);
	}

	function evictToBudget():Void {
		if (retainedBytesEstimate <= maxBytes)
			return;
		final candidates = new Array<String>();
		for (key in accessTicks.keys()) {
			final tick = accessTicks.get(key);
			if (tick != null)
				candidates.push(key);
		}
		candidates.sort(compareAccessKeys);
		var index = 0;
		while (retainedBytesEstimate > maxBytes && index < candidates.length) {
			evict(candidates[index]);
			index += 1;
		}
	}

	function compareAccessKeys(left:String, right:String):Int {
		final leftTick = accessTicks.get(left);
		final rightTick = accessTicks.get(right);
		final leftValue = leftTick == null ? 0 : leftTick;
		final rightValue = rightTick == null ? 0 : rightTick;
		if (leftValue < rightValue)
			return -1;
		if (leftValue > rightValue)
			return 1;
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	function evict(key:String):Void {
		accessTicks.remove(key);
		if (StringTools.startsWith(key, "source:")) {
			final entryKey = key.substr("source:".length);
			final entry = sourceEntries.get(entryKey);
			if (entry != null) {
				sourceEntries.remove(entryKey);
				if (latestSourceRevisionByPath.get(entry.logicalPath) == entry.contentRevision)
					latestSourceRevisionByPath.remove(entry.logicalPath);
				retainedBytesEstimate -= entry.retainedBytesEstimate;
			}
		} else if (StringTools.startsWith(key, "parser:")) {
			final entryKey = key.substr("parser:".length);
			final entry = parsedEntries.get(entryKey);
			if (entry != null) {
				parsedEntries.remove(entryKey);
				if (latestParserInputByPath.get(entry.logicalPath) == entry.inputRevision)
					latestParserInputByPath.remove(entry.logicalPath);
				retainedBytesEstimate -= entry.retainedBytesEstimate;
			}
		} else if (StringTools.startsWith(key, "resolution:")) {
			final entryKey = key.substr("resolution:".length);
			final entry = resolutionEntries.get(entryKey);
			if (entry != null) {
				resolutionEntries.remove(entryKey);
				if (latestResolutionKeyByLookup.get(entry.lookupIdentity) == entry.key) {
					latestResolutionKeyByLookup.remove(entry.lookupIdentity);
					latestResolutionPathByLookup.remove(entry.lookupIdentity);
				}
				retainedBytesEstimate -= entry.retainedBytesEstimate;
			}
		}
		if (retainedBytesEstimate < 0)
			retainedBytesEstimate = 0;
		totalEvictions += 1;
	}

	static function pathToken(path:Null<String>):String {
		return path == null ? "<missing>" : path;
	}

	static function normalizedMaxBytes(explicit:Null<Int>):Int {
		if (explicit != null)
			return explicit < MIN_MAX_BYTES ? MIN_MAX_BYTES : explicit;
		final configured = Sys.getEnv("HXHX_NATIVE_SERVER_SOURCE_CACHE_BYTES");
		if (configured == null || StringTools.trim(configured).length == 0)
			return DEFAULT_MAX_BYTES;
		final parsed = Std.parseInt(StringTools.trim(configured));
		return parsed == null || parsed < MIN_MAX_BYTES ? DEFAULT_MAX_BYTES : parsed;
	}
}
