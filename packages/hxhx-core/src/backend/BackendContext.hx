package backend;

/**
	Execution context passed from the Stage3 driver into a backend implementation.

	Why
	- Backend emission should not read global process state ad hoc; it should receive
	  the exact run configuration from the driver.
	- This keeps backend behavior deterministic and simplifies testing across targets.

	What
	- `outputDir`: backend-owned working/output directory (already absolute).
	- `outputFileHint`: optional concrete output file path (`-js out.js` style).
	- `mainModule`: root module selected by the CLI (may be empty for macro-only units).
	- `emitFullBodies`: Stage3 bootstrap mode that emits full function bodies.
	- `buildExecutable`: whether the backend should perform build/link after emit.
	- `defines`: effective define map after CLI + library + macro-state merging.

	How
	- This class is intentionally small and immutable.
	- Future target-specific knobs should be added explicitly rather than read from
	  environment variables inside backends.
**/
class BackendContext {
	public final outputDir:String;
	public final outputFileHint:Null<String>;
	public final mainModule:String;
	public final emitFullBodies:Bool;
	public final buildExecutable:Bool;
	public final defines:haxe.ds.StringMap<String>;

	public function new(outputDir:String, outputFileHint:Null<String>, mainModule:String, emitFullBodies:Bool, buildExecutable:Bool,
			defines:haxe.ds.StringMap<String>) {
		this.outputDir = outputDir;
		this.outputFileHint = outputFileHint;
		this.mainModule = mainModule == null ? "" : mainModule;
		this.emitFullBodies = emitFullBodies;
		this.buildExecutable = buildExecutable;
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
	}

	public function hasDefine(name:String):Bool {
		return name != null && name.length > 0 && defines.exists(name);
	}

	public function defineValue(name:String):Null<String> {
		if (name == null || name.length == 0)
			return null;
		return defines.get(name);
	}
}
