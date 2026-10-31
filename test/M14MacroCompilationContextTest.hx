import sys.FileSystem;
import sys.io.File;

/**
	A macro compilation context compiles a project's macro classes with `macro` and `eval` defined.

	Upstream Haxe types macro code in a separate macro context, where `#if macro` and `#if eval`
	branches are active. hxhx builds a project-macro plugin by compiling the macro classes in such a
	context. This test checks the three pieces that decide which modules see those defines:

	- `MacroCompilationContext` itself: a module resolved through a macro classpath is a macro
	  module; a module resolved through a nested ordinary classpath (for example a standard-library
	  root inside the project directory) is not; `haxe.macro.*` modules always are.
	- The eager resolver (`ResolverStage.parseProjectRoots`) and the lazy loader (`ModuleLoader`)
	  both apply that decision before parsing.
	- The `--hxhx-macro-classpath <dir>` request flag: a native program compiled from such a
	  classpath calls a method declared only under `#if eval` and runs its `#if macro` branch.
**/
class M14MacroCompilationContextTest {
	static final root = ".tmp/m14-macro-compilation-context";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function write(path:String, content:String):Void {
		FileSystem.createDirectory(haxe.io.Path.directory(path));
		File.saveContent(path, content);
	}

	static function functionNames(module:ResolvedModule):Array<String> {
		final out = new Array<String>();
		for (cls in HxModuleDecl.getClasses(ResolvedModule.getParsed(module).getDecl()))
			for (fn in HxClassDecl.getFunctions(cls))
				out.push(HxFunctionDecl.getName(fn));
		return out;
	}

	static function moduleNamed(modules:Array<ResolvedModule>, path:String):ResolvedModule {
		for (module in modules)
			if (ResolvedModule.getModulePath(module) == path)
				return module;
		throw "module not resolved: " + path;
	}

	static function absolute(path:String):String
		return haxe.io.Path.normalize(FileSystem.fullPath(path));

	static function main():Void {
		final macroRoot = root + "/macro";
		final nestedStd = macroRoot + "/vendor-std";
		final tool = "class Tool {\n"
			+ "\tpublic static function mode():String {\n"
			+ "\t\t#if macro\n\t\treturn \"macro\";\n\t\t#else\n\t\treturn \"target\";\n\t\t#end\n"
			+ "\t}\n"
			+ "\t#if eval\n\tpublic static function evalOnly():String\n\t\treturn \"eval\";\n\t#end\n"
			+ "}\n";
		write(macroRoot + "/Tool.hx", tool);
		write(macroRoot + "/Lazy.hx", tool.split("class Tool").join("class Lazy"));
		write(nestedStd + "/StdThing.hx", tool.split("class Tool").join("class StdThing"));
		write(macroRoot + "/Main.hx", "class Main {\n\tstatic function main():Void {\n\t\tSys.println(Tool.evalOnly() + \" \" + Tool.mode());\n\t}\n}\n");

		final classPaths = [absolute(macroRoot), absolute(nestedStd)];
		final context = MacroCompilationContext.forMacroClassPaths([absolute(macroRoot)], classPaths);
		final ordinary = MacroCompilationContext.standardMacroModulesOnly();

		require(context.isMacroModule("Tool", absolute(macroRoot) + "/Tool.hx"), "a macro classpath module is not a macro module");
		require(!context.isMacroModule("StdThing", absolute(nestedStd) + "/StdThing.hx"), "a nested ordinary classpath module was treated as a macro module");
		require(context.isMacroModule("haxe.macro.Expr", "/std/haxe/macro/Expr.hx"), "haxe.macro modules lost the macro context");
		require(ordinary.isMacroModule("haxe.macro.Expr", "/std/haxe/macro/Expr.hx"), "the ordinary context lost haxe.macro modules");
		require(!ordinary.isMacroModule("Tool", absolute(macroRoot) + "/Tool.hx"), "the ordinary context treated a project module as macro");

		final base = new haxe.ds.StringMap<String>();
		base.set("sys", "1");
		final macroDefines = context.definesFor("Tool", absolute(macroRoot) + "/Tool.hx", base);
		require(macroDefines.get("macro") == "1" && macroDefines.get("eval") == "1", "macro module defines lack macro or eval");
		require(macroDefines.get("sys") == "1", "macro module defines dropped the request defines");
		require(!base.exists("macro"), "macro module defines changed the request defines");
		require(context.definesFor("StdThing", absolute(nestedStd) + "/StdThing.hx", base) == base, "ordinary modules must reuse the request defines");

		final eager = ResolverStage.parseProjectRoots(classPaths, ["Tool", "StdThing"], base, null, context);
		require(functionNames(moduleNamed(eager, "Tool")).indexOf("evalOnly") >= 0, "the resolver did not apply the macro context");
		require(functionNames(moduleNamed(eager, "StdThing")).indexOf("evalOnly") < 0, "the resolver applied the macro context to an ordinary root");
		final shallow = ResolverStage.parseProjectRootsShallow(classPaths, ["Tool"], base, null, context);
		require(functionNames(moduleNamed(shallow, "Tool")).indexOf("evalOnly") >= 0, "the shallow resolver did not apply the macro context");
		final ordinaryEager = ResolverStage.parseProjectRoots(classPaths, ["Tool"], base);
		require(functionNames(moduleNamed(ordinaryEager, "Tool")).indexOf("evalOnly") < 0, "the default resolver applied a macro context");

		final loader = new ModuleLoader(classPaths, base, TyperIndex.buildHeaders([]), null, false, null, null, context);
		loader.ensureTypeAvailable("Lazy", "", []);
		final lazy = loader.drainNewModules();
		require(lazy.length == 1 && functionNames(lazy[0]).indexOf("evalOnly") >= 0, "the lazy loader did not apply the macro context");

		// The request flag: a native program whose classpath is a macro classpath runs the macro branches.
		final out = root + "/native";
		final request = hxhx.CompilationRequestContext.server(1);
		final code = hxhx.Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-out",
			out,
			"--hxhx-macro-classpath",
			macroRoot,
			"-main",
			"Main"
		], request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		require(code == 0, "a macro classpath compile failed:\n" + output.toString());
		final process = new sys.io.Process(out + "/out.exe", []);
		final printed = process.stdout.readAll().toString();
		final exit = process.exitCode();
		process.close();
		require(exit == 0 && printed == "eval macro\n", "the macro classpath program printed `" + printed + "` (exit " + exit + ")");

		Sys.println("MACRO_COMPILATION_CONTEXT:PASS");
	}
}
