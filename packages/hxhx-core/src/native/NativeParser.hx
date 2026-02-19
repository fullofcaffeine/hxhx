package native;

/**
	Native OCaml parser hook for the Stage 2 `hih-compiler` example.

	Why:
	- Keeps the “native frontend” escape hatch available while we reimplement more of
	  the real compiler into Haxe.
	- Lets us validate the end-to-end integration seam: Haxe → OCaml emission →
	  dune build/link → calls into native OCaml modules.

	What:
	- Parses the same tiny module subset as `HxParser` and returns a versioned,
	  line-based protocol string that we rehydrate into `HxModuleDecl`.

	How:
	- The backing OCaml module lives in `std/runtime/HxHxNativeParser.ml`.
	- Field-level `@:native` maps the Haxe method name to OCaml’s
	  `parse_module_decl` convention.
**/
@:native("HxHxNativeParser")
extern class NativeParser {
	@:native("parse_module_decl")
	public static function parseModuleDecl(source:String):String;

	/**
			Parse a module while hinting which class name we expect to treat as the
			“main” class for this file.

			Why
			- Haxe modules can contain multiple types (multiple `class` declarations).
		- During bring-up we still model `HxModuleDecl` as “one main class + methods”.
		- The unhinted hook (`parse_module_decl`) can only pick a heuristic default,
		  which is often wrong for upstream-shaped modules (e.g. `CommandFailure` then
		  `System` in the same file).

			What
			- `expectedMainClass` should typically be the file basename without extension
			  (e.g. `System` for `System.hx`).
		- The native side will select that class (if present) and return its method
		  summaries / body slices for Stage 2/3.

			How
			- Implemented by `parse_module_decl_with_expected` in
			  `std/runtime/HxHxNativeParser.ml`.
	**/
	@:native("parse_module_decl_with_expected")
	public static function parseModuleDeclWithExpected(source:String, expectedMainClass:String):String;
}
