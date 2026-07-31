import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		final root = "tmp_file_system_portable";
		final nested = root + "/nested";
		final original = root + "/before.txt";
		final renamed = root + "/after.txt";

		if (FileSystem.exists(renamed))
			FileSystem.deleteFile(renamed);
		if (FileSystem.exists(original))
			FileSystem.deleteFile(original);
		if (FileSystem.exists(nested))
			FileSystem.deleteDirectory(nested);
		if (FileSystem.exists(root))
			FileSystem.deleteDirectory(root);

		FileSystem.createDirectory(nested);
		File.saveContent(original, "hello");
		final originalExists = FileSystem.exists(original);
		FileSystem.rename(original, renamed);

		final st = FileSystem.stat(renamed);
		final entries = FileSystem.readDirectory(root);
		Sys.println("exists=" + originalExists);
		Sys.println("size=" + st.size);
		Sys.println("mtime_null=" + (st.mtime == null));
		Sys.println("mtime_positive=" + (st.mtime.getTime() > 0));
		Sys.println("full_path_contains_root=" + (FileSystem.fullPath(root).indexOf(root) >= 0));
		Sys.println("absolute_path_contains_root=" + (FileSystem.absolutePath(root).indexOf(root) >= 0));
		Sys.println("directory=" + FileSystem.isDirectory(root));
		Sys.println("renamed=" + (!FileSystem.exists(original) && FileSystem.exists(renamed) && File.getContent(renamed) == "hello"));
		Sys.println("entries=" + (entries.indexOf("after.txt") >= 0 && entries.indexOf("nested") >= 0));

		FileSystem.deleteFile(renamed);
		FileSystem.deleteDirectory(nested);
		FileSystem.deleteDirectory(root);
		Sys.println("cleaned=" + !FileSystem.exists(root));
	}
}
