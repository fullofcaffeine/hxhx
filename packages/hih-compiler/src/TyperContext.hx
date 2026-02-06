/**
	Per-module typing context for Stage 3 bootstrap typing.

	Why
	- `TyperIndex` is global, but expression typing also needs local context:
	  - current package/imports (to resolve short type names)
	  - current class (to type `this.x`)
	  - the current file path (for diagnostics)

	What
	- A small record-like object that threads through `TyperStage` during typing.

	How
	- This is intentionally simple and deterministic. When the real Haxe-in-Haxe
	  typer lands, this will evolve toward upstream’s module typing environment.
**/
class TyperContext {
	final index:TyperIndex;
	final filePath:String;
	final modulePath:String;
	final packagePath:String;
	final imports:Array<String>;
	final classFullName:String;

	public function new(index:TyperIndex, filePath:String, modulePath:String, packagePath:String, imports:Array<String>, classFullName:String) {
		this.index = index;
		this.filePath = filePath == null || filePath.length == 0 ? "<unknown>" : filePath;
		this.modulePath = modulePath == null ? "" : modulePath;
		this.packagePath = packagePath == null ? "" : packagePath;
		this.imports = imports == null ? [] : imports;
		this.classFullName = classFullName == null ? "" : classFullName;
	}

	/**
		Non-inline getters for cross-module use.

		Why
		- The OCaml build uses dune’s `-opaque`, which can make direct record-label
		  access across compilation units fragile during bootstrap.
		- Exposing accessors keeps downstream stages deterministic.
	**/
	public function getIndex():TyperIndex return index;
	public function getFilePath():String return filePath;
	public function getModulePath():String return modulePath;
	public function getPackagePath():String return packagePath;
	public function getImports():Array<String> return imports;
	public function getClassFullName():String return classFullName;

	public function resolveType(typePath:String):Null<TyClassInfo> {
		return index == null ? null : index.resolveTypePath(typePath, packagePath, imports);
	}

	public function currentClass():Null<TyClassInfo> {
		return classFullName.length == 0 ? null : resolveType(classFullName);
	}
}
