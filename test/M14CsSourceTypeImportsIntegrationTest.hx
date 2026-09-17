import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Checks resolved source-class imports through upstream Haxe and generated C# execution. */
class M14CsSourceTypeImportsIntegrationTest {
	static function run(command:String, args:Array<String>):String {
		final process = new Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	static function available(command:String):Bool {
		return Sys.command("sh", ["-c", "command -v " + command + " >/dev/null 2>&1"]) == 0;
	}

	static function main():Void {
		final fixture = "test/cs_source_type_imports";
		final sourceRoot = Path.join([fixture, "src"]);
		final expected = File.getContent(Path.join([fixture, "expected.stdout"]));
		if (run("haxe", ["-cp", sourceRoot, "-main", "app.Main", "--interp"]) != expected)
			throw "upstream source-class import behavior differs from the independent expectation";
		final modules = [
			for (path in [
				"app/Main",
				"app/Local",
				"left/Provider",
				"right/Provider",
				"model/Bundle",
				"RootProvider"
			]) {
				final file = Path.join([sourceRoot, path + ".hx"]);
				new ResolvedModule(StringTools.replace(path, "/", "."), file, ParserStage.parse(File.getContent(file), file));
			}
		];
		final index = TyperIndex.build(modules);
		final program = MacroStage.expandProgram([for (module in modules) TyperStage.typeResolvedModule(module, index)], []);
		final native = available("mono") && (available("mcs") || available("csc"));
		final root = ".tmp/m14_cs_source_type_imports_" + Std.string(Date.now().getTime());
		for (noRoot in [false, true]) {
			final output = Path.join([root, noRoot ? "no-root" : "default"]);
			FileSystem.createDirectory(output);
			final defines = new StringMap<String>();
			if (noRoot)
				defines.set("no_root", "1");
			final result = BackendRegistry.requireForTarget("cs-native").emit(program, new BackendContext(output, null, "app.Main", true, native, defines));
			final source = File.getContent(Path.join(native ? [output, "src", "app", "__HxMain.cs"] : [output, "Main.cs"]));
			if (source.indexOf("global::model.Secondary.visitSecondary()") < 0)
				throw "secondary static call must select the emitted class, not a nested import stub";
			for (alias in [
				"LeftProvider = global::left.Provider",
				"RightProvider = global::right.Provider",
				"SecondaryProvider = global::model.Secondary"
			])
				if (source.indexOf("using " + alias + ";") < 0)
					throw "missing exact source-class alias: " + alias;
			if (native && run("mono", [result.entryPath]) != expected)
				throw "generated C# changed imported constructor behavior";
		}
		Sys.println(native ? "CS_SOURCE_TYPE_IMPORTS:PASS native" : "CS_SOURCE_TYPE_IMPORTS:PASS source only; native tools unavailable");
	}
}
