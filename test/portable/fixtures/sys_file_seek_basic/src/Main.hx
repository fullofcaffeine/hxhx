import sys.io.FileSeek;

class Main {
	static function seekName(value:FileSeek):String {
		return switch (value) {
			case SeekBegin: "begin";
			case SeekCur: "cur";
			case SeekEnd: "end";
		};
	}

	static function main() {
		Sys.println(seekName(SeekBegin));
		Sys.println(seekName(SeekCur));
		Sys.println(seekName(SeekEnd));
	}
}
