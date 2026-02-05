/**
	Typed module environment skeleton.

	Why:
	- The Haxe compiler types code at the module boundary, with imports and
	  per-module caches/incremental rebuild behavior.
	- Even as a stub, the typed module should carry enough information to power:
	  - deterministic acceptance dumps
	  - future analyzer/DCE stages

	What:
	- Package path and imports (carried through from parsing).
	- A typed representation of the module’s “main class” (for now).
**/
class TyModuleEnv {
	final packagePath:String;
	final imports:Array<String>;
	final mainClass:TyClassEnv;

	public function new(packagePath:String, imports:Array<String>, mainClass:TyClassEnv) {
		this.packagePath = packagePath;
		this.imports = imports;
		this.mainClass = mainClass;
	}

	public function getPackagePath():String return packagePath;
	public function getImports():Array<String> return imports;
	public function getMainClass():TyClassEnv return mainClass;
}

