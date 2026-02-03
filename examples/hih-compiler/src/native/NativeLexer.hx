package native;

/**
	Native OCaml lexer hook for the Stage 2 `hih-compiler` example.

	Why:
	- Upstream Haxe’s bootstrapping plan (#6843) explicitly suggests keeping
	  the lexer/parser in OCaml initially, while translating/rewriting the rest
	  of the compiler into Haxe.
	- This extern proves that our generated OCaml can call a “real” OCaml module
	  and link it via dune.

	What:
	- `tokenize` returns a newline-separated token stream (a temporary, pragmatic
	  interchange format until we design a proper AST/token marshalling layer).

	How:
	- The backing OCaml module lives in `std/runtime/HxHxNativeLexer.ml` and is
	  copied into the output as part of the `hx_runtime` dune library.
**/
@:native("HxHxNativeLexer")
extern class NativeLexer {
	public static function tokenize(source:String):String;
}

