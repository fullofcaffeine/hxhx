import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		final args = Sys.args();
		Sys.println(args.length);

		Sys.println(Sys.time());
		Sys.println(Sys.cpuTime());

		final p = "tmp.txt";
		File.saveContent(p, "hello");
		Sys.println(File.getContent(p));

		final st = FileSystem.stat(p);
		Sys.println(st.size);
		Sys.println(st.mtime == null);
		Sys.println(st.mtime.getTime() > 0);

		Sys.println(FileSystem.exists(p));
	}
}
