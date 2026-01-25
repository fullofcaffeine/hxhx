package;

import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		Sys.println("args:" + Sys.args().length);
		Sys.println("env:" + Sys.getEnv("HX_TEST_ENV"));

		final base = "examples/file-io/out/data";
		FileSystem.createDirectory(base);

		final path = base + "/hello.txt";
		File.saveContent(path, "hello");
		Sys.println("content:" + File.getContent(path));

		final bytes = File.getBytes(path);
		Sys.println("bytes:" + bytes.toString());

		final bytesPath = base + "/hello.bytes";
		File.saveBytes(bytesPath, bytes);
		Sys.println("bytes_saved:" + FileSystem.exists(bytesPath));

		final copyPath = base + "/hello_copy.txt";
		File.copy(path, copyPath);
		Sys.println("copy:" + FileSystem.exists(copyPath));

		Sys.println("entries:" + FileSystem.readDirectory(base).length);
	}
}

