package hxhx;

/** Internal immutable source-text entry retained by one native wait server. **/
class CompilationServerCachedSource {
	public final key:String;
	public final logicalPath:String;
	public final contentRevision:String;
	public final source:String;
	public final retainedBytesEstimate:Int;

	public function new(key:String, logicalPath:String, contentRevision:String, source:String, retainedBytesEstimate:Int) {
		this.key = key;
		this.logicalPath = logicalPath;
		this.contentRevision = contentRevision;
		this.source = source;
		this.retainedBytesEstimate = retainedBytesEstimate;
	}
}
