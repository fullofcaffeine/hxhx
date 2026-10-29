import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import sys.FileSystem;
import sys.io.File;

/**
	Checks native identity-map behavior against independently supplied carriers.

	The manifest verifies the production runtime before copying its exact closure.
	The observer needs OCaml to test physical identity, GC and opaque native values;
	Haxe allocation selection and compiler ownership remain separate contracts.
**/
class ObjectMapIdentityRuntimeTest {
	static function main():Void {
		final root = "packages/reflaxe.ocaml/std/runtime";
		final snapshot = RuntimeSourceManifest.load(root);
		final modules = RuntimeSourceManifest.resolveClosure(snapshot, ["HxMap", "HxType"], "portable", false);
		final order = [
			"HxRuntime",
			"HxArray",
			"HxString",
			"HxIterator",
			"HxAnon",
			"HxMap",
			"HxEnum",
			"HxType"
		];
		if (modules.length != order.length)
			throw "object map identity observer runtime closure changed";
		final output = ".tmp/object-map-identity-runtime";
		FileSystem.createDirectory(output);
		final files:Array<String> = [];
		final copied:Array<String> = [];
		for (name in order) {
			final matches = modules.filter(module -> module.module == name);
			if (matches.length != 1)
				throw "object map identity observer lacks runtime module " + name;
			final module = matches[0];
			if (module.files.length != 1 || module.files[0].path != name + ".ml")
				throw "object map identity observer runtime source layout changed";
			for (dependency in module.dependencies)
				if (!copied.contains(dependency))
					throw "object map identity observer runtime dependency order changed";
			final path = output + "/" + module.files[0].path;
			File.copy(root + "/" + module.files[0].path, path);
			files.push(path);
			copied.push(name);
		}
		final observer = output + "/Observer.ml";
		File.copy("test/object_map_identity_runtime/Observer.ml", observer);
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
			throw "object map identity observer did not compile";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", executable]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "OBJECT_MAP_IDENTITY_RUNTIME:PASS\n" || stderr != "")
			throw "object map identity observer failed: " + stdout + stderr;
		Sys.print(stdout);
	}
}
