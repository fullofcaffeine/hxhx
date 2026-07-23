package hxhx;

/** Internal module-lookup entry justified by exact current filesystem observations. **/
class CompilationServerCachedResolution {
	public final key:String;
	public final lookupIdentity:String;
	public final observationRevision:String;
	public final filePath:Null<String>;
	public final selectedClassPathIndex:Int;
	public final usedSecondaryTypeFallback:Bool;
	public final retainedBytesEstimate:Int;

	public function new(key:String, lookupIdentity:String, observationRevision:String, filePath:Null<String>, selectedClassPathIndex:Int,
			usedSecondaryTypeFallback:Bool, retainedBytesEstimate:Int) {
		this.key = key;
		this.lookupIdentity = lookupIdentity;
		this.observationRevision = observationRevision;
		this.filePath = filePath;
		this.selectedClassPathIndex = selectedClassPathIndex;
		this.usedSecondaryTypeFallback = usedSecondaryTypeFallback;
		this.retainedBytesEstimate = retainedBytesEstimate;
	}
}
