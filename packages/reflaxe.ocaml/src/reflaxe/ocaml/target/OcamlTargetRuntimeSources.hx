package reflaxe.ocaml.target;

import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramFile;
import sys.io.File;

/**
	Packages the checked runtime selected by target-owned requirements.

	The host supplies the installed runtime directory. This boundary validates its
	catalog and freezes the verified source bytes before any output is published.
	Neither source paths nor the host working directory enter semantic identities.
**/
class OcamlTargetRuntimeSources {
	final catalog:RuntimeSourceManifestSnapshot;
	final contents:Map<String, String> = [];

	public function new(runtimeDirectory:String) {
		catalog = RuntimeSourceManifest.load(runtimeDirectory);
		for (entry in catalog.modules)
			for (file in entry.files) {
				final bytes = File.getBytes(Path.join([runtimeDirectory, file.path]));
				if ("sha256:" + Sha256.make(bytes).toHex() != file.sha256)
					throw 'OCaml runtime source "${file.path}" changed after catalog validation.';
				final text = bytes.toString();
				if ("sha256:" + Sha256.make(haxe.io.Bytes.ofString(text)).toHex() != file.sha256)
					throw 'OCaml runtime source "${file.path}" cannot be preserved as source text.';
				contents.set(file.path, text);
			}
	}

	/** Select only the checked application closure and its declared native libraries. **/
	public function select(roots:Array<String>, profile:String):Array<OcamlTargetProgramFile> {
		final modules = RuntimeSourceManifest.resolveClosure(catalog, roots, profile, false);
		final files = new Array<OcamlTargetProgramFile>();
		final libraries = new Array<String>();
		for (entry in modules) {
			for (library in entry.duneLibraries)
				if (!libraries.contains(library))
					libraries.push(library);
			for (file in entry.files) {
				final text = contents.get(file.path);
				if (text == null)
					throw 'OCaml runtime source "${file.path}" was not captured.';
				final sourceText:String = text;
				files.push({
					path: "runtime/" + file.path,
					kind: "runtime-source",
					contents: sourceText,
					sha256: Sha256.make(haxe.io.Bytes.ofString(sourceText)).toHex()
				});
			}
		}
		if (modules.length != 0) {
			libraries.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			final dune = "(library\n (name hx_runtime)\n (wrapped false)\n (modules "
				+ modules.map(entry -> entry.module).join(" ")
				+ ")\n"
				+ (libraries.length == 0 ? "" : " (libraries " + libraries.join(" ") + ")\n")
				+ ")\n";
			files.push({
				path: "runtime/dune",
				kind: "runtime-dune",
				contents: dune,
				sha256: Sha256.encode(dune)
			});
		}
		return files;
	}
}
