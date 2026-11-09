class Main {
	static function main() {
		// Upstream Haxe 4.3.7 (`haxe --interp`) prints pi=3.14159265358979312.
		// The OCaml target used to print OCaml's 12-digit string_of_float text,
		// 3.14159265359, and this expectation recorded that. It now follows
		// upstream's Float text (haxe_ocaml-iffj5).
		Sys.println("pi=" + Math.PI);
		Sys.println("roundNegHalf=" + Math.round(-0.5));
		Sys.println("isNaN=" + (Math.isNaN(Math.NaN) ? "true" : "false"));
		Sys.println("isFiniteInf=" + (Math.isFinite(Math.POSITIVE_INFINITY) ? "true" : "false"));
		Sys.println("OK math_basic");
	}
}
