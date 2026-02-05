class Main {
	static function main() {
		final line = Sys.stdin().readLine();
		Sys.stdout().writeString("in=" + line + "\n");
		Sys.stderr().writeString("err=" + line + "\n");
		Sys.stdout().flush();
		Sys.stderr().flush();
	}
}

