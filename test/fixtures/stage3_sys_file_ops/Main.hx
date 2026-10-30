/**
	Reads, writes, lists, and removes files and directories on the OCaml target.

	The program works inside one scratch directory and prints each result, so
	a call that compiles but does nothing, returns a placeholder, or crashes
	produces a visible difference from upstream Haxe. Calls use both the
	imported short names and the fully qualified `sys.io.File` and
	`sys.FileSystem` paths, because Stage3 must route both spellings.
**/

import sys.FileSystem;
import sys.io.File;

class Main {
	static function sorted(values:Array<String>):String {
		values.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		return values.join(",");
	}

	static function main():Void {
		final root = ".tmp/stage3_sys_file_ops_scratch";
		if (FileSystem.exists(root)) {
			for (entry in FileSystem.readDirectory(root + "/nested"))
				FileSystem.deleteFile(root + "/nested/" + entry);
			FileSystem.deleteDirectory(root + "/nested");
			for (entry in FileSystem.readDirectory(root))
				FileSystem.deleteFile(root + "/" + entry);
			FileSystem.deleteDirectory(root);
		}

		Sys.println("exists before " + FileSystem.exists(root));
		FileSystem.createDirectory(root + "/nested");
		Sys.println("exists after " + FileSystem.exists(root));
		Sys.println("root is directory " + FileSystem.isDirectory(root));

		File.saveContent(root + "/a.txt", "alpha\nline two");
		sys.io.File.saveContent(root + "/b.txt", "beta");
		sys.io.File.saveContent(root + "/nested/c.txt", "gamma");

		Sys.println("a.txt = " + File.getContent(root + "/a.txt"));
		Sys.println("b.txt = " + sys.io.File.getContent(root + "/b.txt"));
		Sys.println("a.txt length " + File.getContent(root + "/a.txt").length);
		Sys.println("b.txt length " + sys.io.File.getContent(root + "/b.txt").length);
		Sys.println("a.txt lines " + File.getContent(root + "/a.txt").split("\n").length);
		Sys.println("fromCharCode length " + String.fromCharCode(65).length);
		Sys.println("a.txt is directory " + sys.FileSystem.isDirectory(root + "/a.txt"));
		Sys.println("missing is directory " + FileSystem.isDirectory(root + "/missing"));
		Sys.println("absolute path kept " + FileSystem.absolutePath("/x/../y/./z"));
		Sys.println("absolute root kept " + sys.FileSystem.absolutePath("/"));
		Sys.println("c.txt exists " + sys.FileSystem.exists(root + "/nested/c.txt"));
		Sys.println("root lists " + sorted(FileSystem.readDirectory(root)));
		Sys.println("nested lists " + sorted(sys.FileSystem.readDirectory(root + "/nested")));

		File.saveContent(root + "/a.txt", "rewritten");
		Sys.println("a.txt after rewrite = " + File.getContent(root + "/a.txt"));

		sys.FileSystem.rename(root + "/b.txt", root + "/renamed.txt");
		Sys.println("b.txt exists after rename " + FileSystem.exists(root + "/b.txt"));
		Sys.println("renamed.txt = " + File.getContent(root + "/renamed.txt"));

		File.copy(root + "/renamed.txt", root + "/copy.txt");
		Sys.println("copy.txt = " + sys.io.File.getContent(root + "/copy.txt"));

		FileSystem.deleteFile(root + "/a.txt");
		sys.FileSystem.deleteFile(root + "/nested/c.txt");
		Sys.println("a.txt exists after delete " + FileSystem.exists(root + "/a.txt"));
		Sys.println("root lists after delete " + sorted(FileSystem.readDirectory(root)));

		sys.FileSystem.deleteDirectory(root + "/nested");
		FileSystem.deleteFile(root + "/renamed.txt");
		FileSystem.deleteFile(root + "/copy.txt");
		FileSystem.deleteDirectory(root);
		Sys.println("exists at end " + FileSystem.exists(root));
	}
}
