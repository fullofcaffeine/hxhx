/**
	Typed module environment skeleton.

	Why:
	- The Haxe compiler types code at the module boundary, with imports and
	  per-module caches/incremental rebuild behavior.
	- Even as a stub, the typed module should carry enough information to power:
	  - deterministic acceptance dumps
	  - future analyzer/DCE stages

	What:
	- Package path and import/using directives (carried through from parsing).
	- A typed representation of the module’s “main class” (for now).
**/
class TyModuleEnv {
	final packagePath:String;
	final directives:Array<HxModuleDirective>;
	final resolvedDirectives:Array<TyModuleDirective>;
	final mainClass:TyClassEnv;

	public function new(packagePath:String, directives:Array<HxModuleDirective>, mainClass:TyClassEnv, ?resolvedDirectives:Array<TyModuleDirective>) {
		this.packagePath = packagePath;
		this.directives = directives == null ? [] : directives.copy();
		this.resolvedDirectives = resolvedDirectives == null ? [] : resolvedDirectives.copy();
		this.mainClass = mainClass;
	}

	public function getPackagePath():String
		return packagePath;

	public function getDirectives():Array<HxModuleDirective>
		return directives.copy();

	/** Return the typed meaning of each directive without exposing retained storage. **/
	public function getResolvedDirectives():Array<TyModuleDirective>
		return resolvedDirectives.copy();

	public function getMainClass():TyClassEnv
		return mainClass;
}
