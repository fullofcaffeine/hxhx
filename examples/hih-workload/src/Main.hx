import sys.FileSystem;
import sys.io.File;

class Main {
	static function writeProject(dir:String):Void {
		FileSystem.createDirectory(dir);

		// Three simple modules. We keep this “language” tiny on purpose:
		// it’s just enough structure to stress compiler patterns.
		File.saveContent(dir + "/A.mhx", "let x = 20 + 1; let y = x * 2;");
		File.saveContent(dir + "/B.mhx", "let z = 1 + 1 + 1; let w = z * 7;");
		File.saveContent(dir + "/Main.mhx", "let answer = 42;");
	}

	static function main() {
		Sys.println("stage=1");

		final base = "examples/hih-workload/out/data";
		writeProject(base);
		Sys.println("wrote=1");

		final c = new ProjectCompiler();

		Sys.println("compile=first");
		final first = c.compileProject(base);
		Sys.println("files=" + first.stats.files);
		Sys.println("first_pass_parsed=" + first.stats.parsed);

		Sys.println("compile=second");
		final second = c.compileProject(base);
		Sys.println("second_pass_cached=" + second.stats.cached);
		Sys.println("mtime_positive=" + second.stats.mtimePositive);

		// “Run” the project: evaluate the last declaration of Main.mhx.
		// We intentionally keep module ordering irrelevant: scan for Main.
		var i = 0;
		var result = 0;
		while (i < second.modules.length) {
			final m = second.modules[i];
			if (m.getName() == "Main") {
				result = Eval.evalModule(m);
				break;
			}
			i++;
		}

		Sys.println("result=" + result);
		Sys.println("OK hih-workload");
	}
}
