/** One predicted module rebuild with a deterministic explanation path. **/
class CompilerDependencyInvalidation {
	public final modulePath:String;
	public final reasonPath:Array<String>;

	public function new(modulePath:String, reasonPath:Array<String>) {
		this.modulePath = modulePath == null ? "" : StringTools.trim(modulePath);
		this.reasonPath = reasonPath == null ? [] : reasonPath.copy();
		if (this.modulePath.length == 0 || this.reasonPath.length == 0)
			throw "compiler invalidation requires a module and at least one reason";
	}

	public function describe():String
		return modulePath + ": " + reasonPath.join(" -> ");
}
