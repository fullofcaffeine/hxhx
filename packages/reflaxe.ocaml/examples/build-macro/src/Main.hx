package;

@:build(BuildMacro.addGeneratedField())
class Main {
	static function main() {
		Sys.println("generated=" + generated());
		Sys.println("OK build-macro");
	}
}
