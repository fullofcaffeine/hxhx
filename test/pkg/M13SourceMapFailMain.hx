package pkg;

class M13SourceMapFailMain {
	static function main() {
		// Intentionally inject invalid OCaml to trigger a dune/ocamlc error.
		//
		// This file is used by the M13 source-map integration test to ensure that
		// `-D ocaml_sourcemap=directives` causes OCaml error locations to point back
		// to this `.hx` file/line (best-effort).
		untyped __ocaml__("((\"not an int\") : int)");
	}
}

