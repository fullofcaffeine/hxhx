/**
	The hxhx command line, run by the interpreter, for `M14ProjectMacroPluginCacheTest`.

	The plugin cache starts the compiler as a child process. A native hxhx starts itself
	(`hxhx --hxhx-stage3 ...`); the focused test starts this class through `haxe --run` instead, so
	the same Stage3 sources compile the plugin without a source-built hxhx binary.
**/
class M14ProjectMacroPluginTestCompiler {
	static function main():Void {
		Sys.exit(hxhx.Stage3Compiler.run(Sys.args()));
	}
}
