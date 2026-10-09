/**
	Load Map regression programs through production provider resolution.
	The returned program retains the entire real dependency closure. Keeping this
	loader separate lets declaration checks run without compiling the native smoke
	harness and its unrelated target checks.
 */
function load(sourcePath:String = "test/oracle/cpp_arrow_map_literal_seed/src/Main.hx"):MacroExpandedProgram {
	final fixture = CppResolvedFixture.load({
		sourceRoot: haxe.io.Path.directory(sourcePath),
		mainModule: "Main",
		requiredModules: ["haxe.ds.Map", "haxe.ds.IntMap"]
	});
	return new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
}
