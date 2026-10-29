import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import sys.FileSystem;
import sys.io.File;

/** Builds an independent native observer from the verified production runtime. */
class MethodDispatchRuntimeTest {
	static function main():Void {
		final root = "packages/reflaxe.ocaml/std/runtime";
		final snapshot = RuntimeSourceManifest.load(root);
		final modules = RuntimeSourceManifest.resolveClosure(snapshot, ["HxMethodDispatch"], "portable", false);
		final order = [
			"HxRuntime",
			"HxArray",
			"HxString",
			"HxIterator",
			"HxAnon",
			"HxEnum",
			"HxType",
			"HxMethodDispatch"
		];
		if (modules.length != order.length)
			throw "method dispatch observer runtime closure changed";
		final output = ".tmp/method-dispatch-runtime";
		FileSystem.createDirectory(output);
		final files:Array<String> = [];
		final copied:Array<String> = [];
		for (name in order) {
			final matches = modules.filter(module -> module.module == name);
			if (matches.length != 1)
				throw "method dispatch observer lacks runtime module " + name;
			final module = matches[0];
			if (module.files.length != 1 || module.files[0].path != name + ".ml")
				throw "method dispatch observer runtime source layout changed";
			for (dependency in module.dependencies)
				if (!copied.contains(dependency))
					throw "method dispatch observer runtime dependency order changed";
			final path = output + "/" + module.files[0].path;
			File.copy(root + "/" + module.files[0].path, path);
			files.push(path);
			copied.push(name);
		}
		final observer = output + "/Observer.ml";
		File.copy("test/method_dispatch_runtime/Observer.ml", observer);
		final executable = output + "/observer.exe";
		if (Sys.command("ocamlopt", [
			"-thread",
			"-I",
			"+threads",
			"-I",
			"+unix",
			"unix.cmxa",
			"threads.cmxa",
			"-I",
			output
		].concat(files).concat([observer, "-o", executable])) != 0)
			throw "method dispatch observer did not compile";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", executable]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "METHOD_DISPATCH_RUNTIME:PASS\n" || stderr != "")
			throw "method dispatch observer failed: " + stdout + stderr;
		Sys.print(stdout);
	}
}
