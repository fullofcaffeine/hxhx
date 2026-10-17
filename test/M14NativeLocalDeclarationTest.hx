import backend.BackendContext;
import backend.BackendRegistry;
import backend.source.SourceNativeFunctionLocals;
import backend.source.SourceNativeTarget;
import backend.source.SourceTargetCommon;

/** Compare typed declaration behavior with upstream, then compile and execute both native targets. */
class M14NativeLocalDeclarationTest {
	public static function main():Void {
		final root = ".tmp/native_local_declarations_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final cases = [
			{name: "int", body: "var value:Int; if (flag) value = 3; else value = 4; return value;", expected: "3:4"},
			{name: "float", body: "var value:Float; if (flag) value = 1.5; else value = 2.5; return value > 2 ? 2 : 1;", expected: "1:2"},
			{name: "string", body: "var value:String; if (flag) value = 'left'; else value = null; return value == null ? 0 : 1;", expected: "1:0"},
			{name: "bool", body: "var value:Bool; if (flag) value = true; else value = false; return value ? 1 : 0;", expected: "1:0"},
			{name: "nullable", body: "var value:Null<Int>; if (flag) value = 3; else value = null; return value == null ? 0 : 1;", expected: "1:0"},
			{name: "nominal", body: "var value:Holder; if (flag) value = new Holder(); else value = null; return value == null ? 0 : 1;", expected: "1:0"},
			{name: "initialized", body: "var value:Int = 5; if (flag) value = 6; return value;", expected: "6:5"},
			{name: "explicit_null", body: "var value:Null<Int> = null; if (flag) value = 6; return value == null ? 0 : 1;", expected: "1:0"},
			{name: "nested", body: "var result = 0; while (flag) { var value:Int; value = 7; result = value; break; } return result;", expected: "7:0"},
			{
				name: "switch",
				body: "var result = 0; switch (flag ? 1 : 2) { case 1: var value:Int; value = 8; result = value; default: result = 2; } return result;",
				expected: "8:2"
			},
			{name: "shadow", body: "var value = 1; if (flag) { var value:Int; value = 4; return value; } return value;", expected: "4:1"}
		];
		for (entry in cases) {
			final directory = root + "/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final source = "class Main { static function probe(flag:Bool):Int {"
				+ entry.body
				+ "} static function main() { Sys.println(probe(true) + ':' + probe(false)); } } class Holder { public function new() {} }";
			sys.io.File.saveContent(directory + "/Main.hx", source);
			expect(run("haxe", ["-cp", directory, "-main", "Main", "--interp"]), entry.expected);
			final program = typeProgram(source);
			final projection = program.getTypedModules()[0].getBackendProjection().getClasses()[0].getFunctions()[0];
			for (target in [Java, Cs]) {
				final locals = new SourceNativeFunctionLocals({
					target: target,
					program: program,
					projection: projection,
					noRoot: false
				});
				final body = SourceTargetCommon.renderNativeFunctionBody(locals, projection.getBody(), "").join("\n");
				final java = target == Java;
				final harness = "class Holder {} class Probe { static int probe("
					+ (java ? "boolean" : "bool")
					+ " flag) {"
					+ body
					+ "} "
					+ (java ? "public static void main(String[] args){System.out.println" : "static void Main(){System.Console.WriteLine")
					+ "(probe(true) + \":\" + probe(false));}}";
				final path = directory + (java ? "/Probe.java" : "/Probe.cs");
				sys.io.File.saveContent(path, harness);
				run(java ? "javac" : "mcs", java ? [path] : ["-out:" + directory + "/Probe.exe", path]);
				expect(run(java ? "java" : "mono", java ? ["-cp", directory, "Probe"] : [directory + "/Probe.exe"]), entry.expected);
			}
			var rejected = false;
			try {
				new SourceNativeFunctionLocals({
					target: Java,
					program: typeProgram(source),
					projection: projection,
					noRoot: false
				});
			} catch (error:String) {
				rejected = error.indexOf("exact program function projection") >= 0;
			}
			if (!rejected)
				throw "foreign function projection was accepted";
		}
		checkUnassignedRead(root);
		checkProduction(root);
		Sys.println("NATIVE_LOCAL_DECLARATIONS:PASS");
	}

	/** An unassigned read must remain an error; emission must not invent an initial value. */
	static function checkUnassignedRead(root:String):Void {
		final directory = root + "/negative";
		sys.FileSystem.createDirectory(directory);
		final source = "class Main { static function probe():Int {var value:Int; return value;} static function main() {probe();} }";
		sys.io.File.saveContent(directory + "/Main.hx", source);
		run("haxe", ["-cp", directory, "-main", "Main", "--interp"], "used without being initialized");
		final program = typeProgram(source);
		final projection = program.getTypedModules()[0].getBackendProjection().getClasses()[0].getFunctions()[0];
		for (target in [Java, Cs]) {
			final body = SourceTargetCommon.renderNativeFunctionBody(new SourceNativeFunctionLocals({
				target: target,
				program: program,
				projection: projection,
				noRoot: false
			}), projection.getBody(), "").join("\n");
			final java = target == Java;
			final path = directory + (java ? "/Probe.java" : "/Probe.cs");
			sys.io.File.saveContent(path, "class Probe {static int probe(){" + body + "}}");
			run(java ? "javac" : "mcs", java ? [path] : ["-target:library", "-out:" + directory + "/Probe.dll", path],
				java ? "might not have been initialized" : "unassigned local variable");
		}
	}

	/** Exercise the public backend route, including main and a called helper, without a handwritten harness. */
	static function checkProduction(root:String):Void {
		final source = "class Main { static function helper():Int { var local:Int; local = 9; return local; }"
			+ " static function main() { var value:Int; value = 7; Sys.println(value); Sys.println(helper()); } }";
		final directory = root + "/production";
		sys.FileSystem.createDirectory(directory);
		sys.io.File.saveContent(directory + "/Main.hx", source);
		expect(run("haxe", ["-cp", directory, "-main", "Main", "--interp"]), "7\n9");
		for (target in ["java-native", "cs-native"]) {
			final result = BackendRegistry.requireForTarget(target)
				.emit(typeProgram(source), new BackendContext(directory + "/" + target, null, "Main", true, true, new haxe.ds.StringMap<String>()));
			expect(run(target == "java-native" ? "java" : "mono", target == "java-native" ? ["-jar", result.entryPath] : [result.entryPath]), "7\n9");
		}
	}

	static function typeProgram(source:String):MacroExpandedProgram {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false);
	}

	static function expect(actual:String, expected:String):Void {
		if (StringTools.trim(actual) != expected)
			throw "native local result differs: " + actual + " expected " + expected;
	}

	/** Require a specific diagnostic for negative cases, so an unrelated tool failure cannot pass. */
	static function run(command:String, args:Array<String>, ?diagnostic:String):String {
		final process = new sys.io.Process(command, args);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (diagnostic == null ? code != 0 : code == 0 || (output + error).indexOf(diagnostic) < 0)
			throw command + " failed contract: " + output + error;
		return output;
	}
}
