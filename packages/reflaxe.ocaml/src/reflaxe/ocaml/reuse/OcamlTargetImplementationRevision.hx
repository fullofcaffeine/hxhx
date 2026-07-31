package reflaxe.ocaml.reuse;

#if macro
import haxe.crypto.Sha256;
import haxe.io.BytesOutput;
import haxe.io.Path;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

/**
	Computes the exact path-independent identity of the installed OCaml target.

	The reuse key must change when any target implementation source changes. A
	package version or manually maintained pipeline constant is not enough
	because either can remain unchanged during development. This inventory walks
	the installed `reflaxe/ocaml` source tree on every request and hashes sorted
	relative paths plus their complete bytes. Runtime sources have a separate
	manifest and revision.
**/
class OcamlTargetImplementationRevision {
	public static inline final MODEL = "reflaxe-ocaml-target-source-tree-v1";

	/** Returns the exact lowercase SHA-256 revision of the installed target sources. **/
	public static function current():String {
		final anchor = Context.resolvePath("reflaxe/ocaml/reuse/OcamlTargetImplementationRevision.hx");
		final root = Path.normalize(Path.join([Path.directory(anchor), ".."]));
		final paths = new Array<String>();
		collectSourcePaths(root, "", paths);
		paths.sort(Reflect.compare);
		if (paths.length == 0)
			throw "reflaxe.ocaml: target implementation source inventory is empty";

		final encoded = new BytesOutput();
		encoded.bigEndian = true;
		writeString(encoded, MODEL);
		encoded.writeInt32(paths.length);
		for (relative in paths) {
			final bytes = File.getBytes(Path.join([root, relative]));
			writeString(encoded, relative);
			encoded.writeInt32(bytes.length);
			encoded.write(bytes);
		}
		return "sha256:" + Sha256.make(encoded.getBytes()).toHex();
	}

	static function collectSourcePaths(root:String, relativeDirectory:String, result:Array<String>):Void {
		final directory = relativeDirectory.length == 0 ? root : Path.join([root, relativeDirectory]);
		final names = FileSystem.readDirectory(directory);
		names.sort(Reflect.compare);
		for (name in names) {
			final relative = relativeDirectory.length == 0 ? name : relativeDirectory + "/" + name;
			final absolute = Path.join([root, relative]);
			if (FileSystem.isDirectory(absolute)) {
				collectSourcePaths(root, relative, result);
			} else if (StringTools.endsWith(name, ".hx")) {
				result.push(StringTools.replace(relative, "\\", "/"));
			}
		}
	}

	static function writeString(output:BytesOutput, value:String):Void {
		final bytes = haxe.io.Bytes.ofString(value);
		output.writeInt32(bytes.length);
		output.write(bytes);
	}
}
#end
