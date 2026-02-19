/**
	A resolved, parsed module in the Stage 2 “Haxe-in-Haxe compiler” skeleton.

	Why:
	- As we move beyond “parse a single string”, we need a stable *module graph*
	  representation to thread through the pipeline stages (parse → type → macros → emit).
	- We keep this as a nominal class (not a `typedef {...}`) to avoid coupling the
	  acceptance example to structural typing features while `hxhx` is still bootstrapping.

	What:
	- `modulePath`: logical Haxe module path (e.g. `demo.Util`).
	- `filePath`: the resolved `.hx` file path on disk (relative or absolute).
	- `parsed`: the `ParsedModule` produced by `ParserStage`.

	How:
	- `ResolverStage` is responsible for constructing these by searching `-cp`
	  classpaths, then parsing the resulting sources.
**/
class ResolvedModule {
	public final modulePath:String;
	public final filePath:String;
	public final parsed:ParsedModule;

	public function new(modulePath:String, filePath:String, parsed:ParsedModule) {
		this.modulePath = modulePath;
		this.filePath = filePath;
		this.parsed = parsed;
	}

	/**
		Accessor used by other modules during bootstrap.

		Why:
		- Our current OCaml backend favors minimal type annotations in generated code.
		- OCaml record field labels can be unavailable in a compilation unit unless the
		  defining module is fully typechecked first (dune may compile units in a way
		  that trips this for record-field access through erased generics).
		- A plain function call keeps those record-field accesses inside the defining
		  module, avoiding fragile cross-unit label resolution during bring-up.
	**/
	public static function getParsed(m:ResolvedModule):ParsedModule {
		return m.parsed;
	}

	/**
		See `getParsed` for the bootstrap motivation.
	**/
	public static function getFilePath(m:ResolvedModule):String {
		return m.filePath;
	}

	/**
		See `getParsed` for the bootstrap motivation.
	**/
	public static function getModulePath(m:ResolvedModule):String {
		return m.modulePath;
	}
}
