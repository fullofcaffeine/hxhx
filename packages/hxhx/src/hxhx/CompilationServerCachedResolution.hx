package hxhx;

/** Internal module-lookup entry justified by exact current filesystem observations. **/
class CompilationServerCachedResolution {
	public final key:String;
	public final lookupIdentity:String;
	public final observationRevision:String;
	public final filePath:Null<String>;
	public final retainedBytesEstimate:Int;

	public function new(key:String, lookupIdentity:String, observationRevision:String, filePath:Null<String>, retainedBytesEstimate:Int) {
		this.key = key;
		this.lookupIdentity = lookupIdentity;
		this.observationRevision = observationRevision;
		this.filePath = filePath;
		this.retainedBytesEstimate = retainedBytesEstimate;
	}
}
