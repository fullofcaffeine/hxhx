import backend.ocaml.HxhxOcamlTargetProgramAdapter;
import haxe.ds.StringMap;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;

/**
	Compiles one small ordinary Haxe program through the native `hxhx` host facts.

	The fixture deliberately calls the Haxe-authored parser and typer directly so
	Stage3 target emission cannot participate. The resulting immutable program is
	then adapted and lowered by the same standalone target core used by the builtin
	`ocaml-native` backend.
**/
class NativeProgramHostFixture {
	/** Parse, type, adapt, lower, publish, and build the requested main module. **/
	static function main():Void {
		final args = Sys.args();
		if (args.length != 2)
			throw "usage: NativeProgramHostFixture <source-root> <output-directory>";
		final sourceRoot = haxe.io.Path.normalize(args[0]);
		final outputDirectory = haxe.io.Path.normalize(args[1]);
		final defines = new StringMap<String>();
		defines.set("ocaml", "1");
		defines.set("reflaxe_ocaml", "1");

		final resolved = ResolverStage.parseProjectRoots([sourceRoot], ["Main"], defines);
		if (resolved.length == 0)
			throw "native program host fixture resolved no modules";
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([sourceRoot], defines, index);
		loader.markResolvedAlready(resolved);

		var typedModules = new Array<TypedModule>();
		final pending = resolved.copy();
		var cursor = 0;
		while (cursor < pending.length) {
			typedModules.push(TyperStage.typeResolvedModule(pending[cursor], index, loader, true));
			cursor++;
			for (module in loader.drainNewModules())
				pending.push(module);
		}
		typedModules = TypedAbstractOperatorLowering.lowerModules(typedModules, index);
		final sourceModules = [for (module in pending) ResolvedModule.getModulePath(module)];
		sourceModules.sort(compareText);
		final program = new MacroExpandedProgram(typedModules, false);
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(program, "Main");
		final plan = OcamlTargetProgramCore.lower(request);
		final executable = OcamlTargetProgramPublisher.publish(plan, outputDirectory, "native-hxhx", true);
		Sys.println("native_hxhx_diagnostics=0");
		Sys.println("native_hxhx_source_modules=" + sourceModules.join(","));
		Sys.println("native_hxhx_shared_target_executable=" + executable);
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
