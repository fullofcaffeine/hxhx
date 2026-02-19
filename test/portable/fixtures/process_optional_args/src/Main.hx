class Main {
	static function main() {
		// Omitted args + omitted detached (should compile and work).
		final p1 = new sys.io.Process("true");
		final code1 = p1.exitCode();
		p1.close();
		Sys.println("code1=" + code1);

		// Explicit null args + detached=false (should compile and work).
		final p2 = new sys.io.Process("true", null, false);
		final code2 = p2.exitCode();
		p2.close();
		Sys.println("code2=" + code2);

		// Non-empty args + detached=false (exercise stdout).
		final p3 = new sys.io.Process("sh", ["-lc", "echo hi"], false);
		final line = p3.stdout.readLine();
		p3.close();
		Sys.println("out=" + line);
	}
}
