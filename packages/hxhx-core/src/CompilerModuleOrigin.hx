/**
	Path-safe identity of the source module selected from ordered class paths.

	The absolute file path remains available on `ResolvedModule` for diagnostics and
	file reads. This record keeps only compiler-relevant logical facts, so dependency
	reports and future cache keys do not leak a developer's workspace path.

	`sourceIdentity` deliberately normalizes direct and secondary-type lookups that
	select the same Haxe source module. For example, resolving `pack.Mod` directly
	and resolving `pack.Mod.SubType` through `pack/Mod.hx` name the same source
	origin even though the lookup routes differ. Synthetic origins used by focused
	in-memory tests remain distinct from every real class-path source.
**/
class CompilerModuleOrigin {
	public final requestedModulePath:String;
	public final sourceModulePath:String;
	public final selectedClassPathIndex:Int;
	public final usedSecondaryTypeFallback:Bool;
	public final isSynthetic:Bool;

	final sourceIdentity:String;

	public function new(requestedModulePath:String, selectedClassPathIndex:Int, usedSecondaryTypeFallback:Bool, isSynthetic:Bool = false) {
		this.requestedModulePath = normalize(requestedModulePath);
		this.selectedClassPathIndex = selectedClassPathIndex;
		this.usedSecondaryTypeFallback = usedSecondaryTypeFallback;
		this.isSynthetic = isSynthetic;
		if (this.requestedModulePath.length == 0)
			throw "module source origin requires a requested module path";
		if (selectedClassPathIndex < 0)
			throw "module source origin requires a selected class-path slot";
		sourceModulePath = usedSecondaryTypeFallback ? parentModule(this.requestedModulePath) : this.requestedModulePath;
		if (sourceModulePath.length == 0)
			throw "secondary-type module origin requires a parent source module";
		sourceIdentity = isSynthetic ? CompilerCacheIdentity.encode(["synthetic-module-origin-v1", sourceModulePath]) : CompilerCacheIdentity.encode(["module-source-origin-v1", sourceModulePath, Std.string(selectedClassPathIndex)]);
	}

	/** Create the ordinary direct-file origin used by focused in-memory fixtures. **/
	public static function direct(modulePath:String, selectedClassPathIndex:Int):CompilerModuleOrigin
		return new CompilerModuleOrigin(modulePath, selectedClassPathIndex, false);

	/** Create a path-independent origin for tests or direct parsed-module entry points. **/
	public static function synthetic(modulePath:String):CompilerModuleOrigin {
		final normalized = normalize(modulePath);
		final safeModule = normalized.length == 0 ? "<synthetic-module>" : normalized;
		return new CompilerModuleOrigin(safeModule, 0, false, true);
	}

	/** Exact path-safe source identity used by module revisions and cache admission. **/
	public function getSourceIdentity():String
		return sourceIdentity;

	/** Beginner-readable description that never includes an absolute filesystem path. **/
	public function describeSource():String
		return isSynthetic ? sourceModulePath + "@synthetic" : sourceModulePath + "@classpath[" + selectedClassPathIndex + "]";

	/** Explain the lookup route while keeping the normalized source identity separate. **/
	public function describeLookup():String
		return requestedModulePath
			+ "->"
			+ describeSource()
			+ (isSynthetic ? ":synthetic" : (usedSecondaryTypeFallback ? ":secondary-type" : ":direct"));

	static function parentModule(modulePath:String):String {
		final dot = modulePath.lastIndexOf(".");
		return dot < 0 ? "" : modulePath.substr(0, dot);
	}

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
