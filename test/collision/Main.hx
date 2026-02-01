class Main {
	static function main() {
		// Force both modules to be reachable in the same compilation.
		Sys.println(a.b.C.id());
		Sys.println(a_b.C.id());
	}
}

