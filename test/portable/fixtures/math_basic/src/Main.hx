class Main {
	static function main() {
		Sys.println("pi=" + Math.PI);
		Sys.println("roundNegHalf=" + Math.round(-0.5));
		Sys.println("isNaN=" + (Math.isNaN(Math.NaN) ? "true" : "false"));
		Sys.println("isFiniteInf=" + (Math.isFinite(Math.POSITIVE_INFINITY) ? "true" : "false"));
		Sys.println("OK math_basic");
	}
}

