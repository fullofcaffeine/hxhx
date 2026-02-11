package reflaxe.ocaml.ast;

/**
	A lightweight, runtime-safe representation of a Haxe source position.

	Why:
	- Haxe's macro `Position` type is not available in non-macro builds, but parts of the
	  OCaml AST/printer are shared across macro and (future) runtime tooling.
	- For OCaml source mapping we only need a small subset of the position info that is
	  stable and easy to embed in generated output.

	What:
	- `file`: a (preferably) stable, user-facing `.hx` path (often repo-relative).
	- `line`: 1-based line number.
	- `col`:  1-based column number.

	How:
	- Instances are created by `OcamlBuilder` when `-D ocaml_sourcemap` is enabled.
	- The printer can then emit OCaml `# <line> "<file>"` directives so OCaml compiler errors
	  can point back to Haxe source locations (best-effort).
**/
typedef OcamlDebugPos = {
	final file:String;
	final line:Int;
	final col:Int;
}

