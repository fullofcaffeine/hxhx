/**
	Request-local facts about source, module lookup, and parser reuse.

	The report is measurement data only. Compiler stages never use these counters
	to decide whether a cached value is correct. Cache implementations update the
	counters after their identity checks; direct filesystem providers remain
	disabled and report zero reuse.
**/
class CompilerSourceProviderReport {
	public final cacheEnabled:Bool;
	public var sourceHits(default, null):Int;
	public var sourceMisses(default, null):Int;
	public var sourceBytesRead(default, null):Int;
	public var resolutionHits(default, null):Int;
	public var resolutionMisses(default, null):Int;
	public var parserHits(default, null):Int;
	public var parserMisses(default, null):Int;
	public var evictions(default, null):Int;
	public var retainedEntries(default, null):Int;
	public var retainedBytesEstimate(default, null):Int;

	final missReasons:haxe.ds.StringMap<Int>;

	public function new(cacheEnabled:Bool) {
		this.cacheEnabled = cacheEnabled;
		sourceHits = 0;
		sourceMisses = 0;
		sourceBytesRead = 0;
		resolutionHits = 0;
		resolutionMisses = 0;
		parserHits = 0;
		parserMisses = 0;
		evictions = 0;
		retainedEntries = 0;
		retainedBytesEstimate = 0;
		missReasons = new haxe.ds.StringMap<Int>();
	}

	public function recordSourceHit():Void
		sourceHits += 1;

	public function recordSourceMiss(reason:String):Void {
		sourceMisses += 1;
		recordMissReason(reason);
	}

	public function recordSourceBytesRead(count:Int):Void
		sourceBytesRead += count > 0 ? count : 0;

	public function recordResolutionHit():Void
		resolutionHits += 1;

	public function recordResolutionMiss(reason:String):Void {
		resolutionMisses += 1;
		recordMissReason(reason);
	}

	public function recordParserHit():Void
		parserHits += 1;

	public function recordParserMiss(reason:String):Void {
		parserMisses += 1;
		recordMissReason(reason);
	}

	public function setRetainedState(entries:Int, bytesEstimate:Int, evictions:Int):Void {
		retainedEntries = entries > 0 ? entries : 0;
		retainedBytesEstimate = bytesEstimate > 0 ? bytesEstimate : 0;
		this.evictions = evictions > 0 ? evictions : 0;
	}

	public function totalHits():Int
		return sourceHits + resolutionHits + parserHits;

	public function totalMisses():Int
		return sourceMisses + resolutionMisses + parserMisses;

	public function sortedMissReasons():Array<String> {
		final reasons = new Array<String>();
		for (reason in missReasons.keys())
			reasons.push(reason);
		reasons.sort(compareStrings);
		return reasons;
	}

	public function missReasonCount(reason:String):Int {
		final count = missReasons.get(reason);
		return count == null ? 0 : count;
	}

	function recordMissReason(reason:String):Void {
		final normalized = reason == null || StringTools.trim(reason).length == 0 ? "unspecified" : StringTools.trim(reason);
		final previous = missReasons.get(normalized);
		missReasons.set(normalized, (previous == null ? 0 : previous) + 1);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
