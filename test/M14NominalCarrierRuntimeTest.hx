import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import sys.FileSystem;
import sys.io.File;

/** Compile an independent native observer against the exact locked runtime sources. */
class M14NominalCarrierRuntimeTest {
	static function main():Void {
		final root = "packages/reflaxe.ocaml/std/runtime";
		final snapshot = RuntimeSourceManifest.load(root);
		final modules = RuntimeSourceManifest.resolveClosure(snapshot, ["HxType"], "portable", false);
		final order = ["HxRuntime", "HxArray", "HxString", "HxIterator", "HxAnon", "HxEnum", "HxType"];
		if (modules.length != order.length)
			throw "nominal observer runtime closure changed";
		final output = ".tmp/nominal-carrier-runtime";
		FileSystem.createDirectory(output);
		final files = new Array<String>();
		final copied = new Array<String>();
		for (name in order) {
			final matches = modules.filter(module -> module.module == name);
			if (matches.length != 1)
				throw "nominal observer lacks runtime module " + name;
			final module = matches[0];
			if (module.files.length != 1 || module.files[0].path != name + ".ml")
				throw "nominal observer runtime source layout changed";
			for (dependency in module.dependencies)
				if (copied.indexOf(dependency) < 0)
					throw "nominal observer runtime dependency order changed";
			final path = output + "/" + module.files[0].path;
			File.copy(root + "/" + module.files[0].path, path);
			files.push(path);
			copied.push(name);
		}
		final observer = output + "/Observer.ml";
		File.copy("test/nominal_carrier_runtime/Observer.ml", observer);
		final executable = output + "/observer.exe";
		if (Sys.command("ocamlopt", ["-I", output].concat(files).concat([observer, "-o", executable])) != 0)
			throw "nominal carrier observer did not compile";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", executable]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "NOMINAL_CARRIER_RUNTIME:PASS\n" || stderr != "")
			throw "nominal carrier observer failed: " + stdout + stderr;
		Sys.print(stdout);
	}
}
