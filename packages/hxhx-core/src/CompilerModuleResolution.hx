/**
	Records one exact-case module lookup and the filesystem observations that justify it.

	`filePath` is the source file selected from the ordered class paths, or null
	when no matching module exists. `observationRevision` changes when the exact
	filename checked at any class-path position appears, disappears, changes kind,
	or selects a different file. This lets a long-lived compiler notice a newly
	added, deleted, renamed, or higher-priority module without treating unrelated
	directory entries as compiler inputs.
**/
class CompilerModuleResolution {
	public final lookupIdentity:String;
	public final observationRevision:String;
	public final filePath:Null<String>;
	public final selectedClassPathIndex:Int;
	public final usedSecondaryTypeFallback:Bool;

	public function new(lookupIdentity:String, observationRevision:String, filePath:Null<String>, selectedClassPathIndex:Int, usedSecondaryTypeFallback:Bool) {
		this.lookupIdentity = lookupIdentity;
		this.observationRevision = observationRevision;
		this.filePath = filePath;
		this.selectedClassPathIndex = selectedClassPathIndex;
		this.usedSecondaryTypeFallback = usedSecondaryTypeFallback;
	}

	/** Convert one successful lookup into the path-safe origin carried through typing. **/
	public function toOrigin(requestedModulePath:String):CompilerModuleOrigin {
		if (filePath == null || selectedClassPathIndex < 0)
			throw "missing module resolution has no source origin";
		return new CompilerModuleOrigin(requestedModulePath, selectedClassPathIndex, usedSecondaryTypeFallback);
	}
}
