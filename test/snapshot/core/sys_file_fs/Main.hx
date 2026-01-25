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

		Sys.println(FileSystem.exists(p));
	}
}

