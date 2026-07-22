package hxhx;

/** Internal parsed-module entry with the structural description used to detect later mutation. **/
class CompilationServerCachedParse {
	public final key:String;
	public final logicalPath:String;
	public final inputRevision:String;
	public final parsed:ParsedModule;
	public final integrityRevision:String;
	public final retainedBytesEstimate:Int;

	public function new(key:String, logicalPath:String, inputRevision:String, parsed:ParsedModule, integrityRevision:String, retainedBytesEstimate:Int) {
		this.key = key;
		this.logicalPath = logicalPath;
		this.inputRevision = inputRevision;
		this.parsed = parsed;
		this.integrityRevision = integrityRevision;
		this.retainedBytesEstimate = retainedBytesEstimate;
	}
}
