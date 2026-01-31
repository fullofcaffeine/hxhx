import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		final p = "tmp_stat_portable.txt";
		File.saveContent(p, "hello");

		final st = FileSystem.stat(p);
		Sys.println("size=" + st.size);
		Sys.println("mtime_null=" + (st.mtime == null));
		Sys.println("mtime_positive=" + (st.mtime.getTime() > 0));
	}
}

