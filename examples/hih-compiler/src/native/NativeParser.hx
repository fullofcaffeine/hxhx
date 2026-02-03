package native;

/**
	Native OCaml parser hook for the Stage 2 `hih-compiler` example.

	Why:
	- Keeps the “native frontend” escape hatch available while we port more of
	  the real compiler into Haxe.
	- Lets us validate the end-to-end integration seam: Haxe → OCaml emission →
	  dune build/link → calls into native OCaml modules.

	What:
	- Parses the same tiny module subset as `HxParser` and returns a line-based
	  record that we rehydrate into `HxModuleDecl`.

	How:
	- The backing OCaml module lives in `std/runtime/HxHxNativeParser.ml`.
	- Field-level `@:native` maps the Haxe method name to OCaml’s
	  `parse_module_decl` convention.
**/
@:native("HxHxNativeParser")
extern class NativeParser {
	@:native("parse_module_decl")
	public static function parseModuleDecl(source:String):String;
}

