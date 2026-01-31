/**
	Entry point for the Stage 2 “Haxe-in-Haxe compiler” skeleton.

	Why:
	- This is not yet a real Haxe compiler; it’s a place to accumulate the real
	  architecture incrementally while staying runnable in CI (compile → dune
	  build → run).
	- Keeping it as an `examples/` app gives us a realistic acceptance harness,
	  beyond unit tests and golden output.
**/
class Main {
	static function main() {
		Sys.println("stage=2");

		final driver = new CompilerDriver();
		driver.run();

		Sys.println("OK hih-compiler");
	}
}

