package suite;

/**
	A module-level `main` that calls project macros the way upstream
	`tests/unit/src/unit/TestMain.hx` does: a package-qualified call as a `for`
	iterable and a same-package call as a statement. `SpecBuilder` is loaded only
	when the macro pass selects these calls.
**/
function main() {
	for (name in suite.SpecBuilder.names("specs"))
		Sys.println(name);
	SpecBuilder.register("issues", "suite.issues");
}
