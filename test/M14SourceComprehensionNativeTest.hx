import backend.BackendContext;
import backend.cpp.CppTargetCore;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Require a real collection after source comprehension typing and shared control lowering. */
class M14SourceComprehensionNativeTest {
	static function main():Void {
		final arguments = Stage1Args.parse(["-cp", "test/oracle/source_comprehension_seed/array", "-main", "Main"], true);
		if (arguments == null)
			throw "comprehension fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "cpp"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "cpp", "cpp-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		final pending = resolved.copy();
		final modules = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			final module = pending[cursor++];
			try {
				modules.push(TyperStage.typeResolvedModule(module, index, loader, true));
			} catch (failure:haxe.Exception) {
				throw new haxe.Exception("comprehension program loading " + ResolvedModule.getModulePath(module) + ": " + failure.message, failure);
			}
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		final functions = [
			for (module in modules)
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						if (fn.getBody() != null)
							fn
		];
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final result = CppTargetCore.emit(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(modules, index), false),
			new BackendContext(".tmp/source-comprehension-array", null, "Main", true, true, defines));
		if (!result.builtExecutable)
			throw "comprehension contract requires native execution";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "comprehension lowering changed authored typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stderr.length != 0 || stdout != "a=>b,a=>b\n")
			throw "comprehension runtime differs: " + stdout + stderr;
		Sys.println("SOURCE_COMPREHENSION_NATIVE:PASS");
	}
}
