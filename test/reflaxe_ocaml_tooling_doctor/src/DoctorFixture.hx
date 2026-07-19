import haxe.Json;
import haxe.io.Path;
import reflaxe.ocaml.tooling.CommandResult;
import reflaxe.ocaml.tooling.DoctorCheck;
import reflaxe.ocaml.tooling.DoctorProbe;
import reflaxe.ocaml.tooling.DoctorReport;
import reflaxe.ocaml.tooling.DoctorStatus;
import reflaxe.ocaml.tooling.ReflaxeOcamlDoctor;

using StringTools;

/** Proves doctor capability, compatibility, and fail-closed decisions without changing the host toolchain. **/
class DoctorFixture {
	static function main():Void {
		testVerifiedEnvironment();
		testSourceOnlyEnvironment();
		testNativeRequiresOcamlopt();
		testWrongHaxeFailsSource();
		testCompatibleUnverifiedToolchain();
		testPackageVersionMismatch();
		Sys.println("REFLAXE_OCAML_DOCTOR_MODEL_FIXTURE:PASS");
	}

	static function testVerifiedEnvironment():Void {
		final probe = healthyProbe();
		final report = inspect(probe, "compiler");
		assert(report.summary.exitCode == 0, "verified compiler capability should pass");
		assert(report.capabilities.sourceGeneration, "verified source generation missing");
		assert(report.capabilities.nativeBuild, "verified native build missing");
		assert(report.capabilities.compilerAuthoring, "verified compiler authoring missing");
		assert(report.capabilities.hxhxHost, "verified hxhx host missing");
		assert(report.capabilities.reproduciblePackaging, "verified packaging inputs missing");
		assert(report.capabilities.verifiedReleaseLane, "exact hosted lane was not recognized");
		assert(findCheck(report, "runtime-manifest").status == DoctorStatus.Skip, "future runtime manifest must remain explicit");
		final parsed:Dynamic = Json.parse(ReflaxeOcamlDoctor.renderJson(report));
		assert(Reflect.field(parsed, "schemaVersion") == 1, "doctor JSON schema missing");
		assert(ReflaxeOcamlDoctor.renderHuman(report).contains("Requested `compiler` capability: READY"), "human readiness summary missing");
	}

	static function testSourceOnlyEnvironment():Void {
		final probe = healthyProbe();
		for (command in ["ocamlc", "ocamlopt", "dune", "ocamlfind"]) {
			probe.miss(command);
		}
		final source = inspect(probe, "source");
		assert(source.summary.exitCode == 0 && source.capabilities.sourceGeneration, "missing native tools should not hide source readiness");
		assert(!source.capabilities.nativeBuild, "native capability survived missing tools");
		final native = inspect(probe, "native");
		assert(native.summary.exitCode == 1 && !native.summary.ready, "required native capability did not fail closed");
	}

	static function testNativeRequiresOcamlopt():Void {
		final probe = healthyProbe();
		probe.miss("ocamlopt");
		final report = inspect(probe, "native");
		assert(report.summary.exitCode == 1, "native capability survived a missing native compiler");
		assert(findCheck(report, "ocamlopt").status == DoctorStatus.Warn, "missing native compiler warning missing");
	}

	static function testWrongHaxeFailsSource():Void {
		final probe = healthyProbe();
		probe.answer("haxe", ["--version"], "4.2.5\n");
		final report = inspect(probe, "source");
		assert(report.summary.exitCode == 1, "unsupported Haxe did not fail source capability");
		assert(findCheck(report, "haxe").status == DoctorStatus.Fail, "unsupported Haxe check did not fail");
	}

	static function testCompatibleUnverifiedToolchain():Void {
		final probe = healthyProbe();
		probe.answer("ocamlc", ["-version"], "5.4.0\n");
		probe.answer("ocamlopt", ["-version"], "5.4.0\n");
		probe.answer("dune", ["--version"], "3.21.0\n");
		final report = inspect(probe, "native");
		assert(report.summary.exitCode == 0 && report.capabilities.nativeBuild, "compatible newer toolchain should remain usable");
		assert(!report.capabilities.verifiedReleaseLane, "unverified versions were presented as hosted evidence");
		assert(findCheck(report, "ocaml").status == DoctorStatus.Warn, "unverified OCaml warning missing");
		assert(findCheck(report, "dune").status == DoctorStatus.Warn, "unverified Dune warning missing");
	}

	static function testPackageVersionMismatch():Void {
		final probe = healthyProbe();
		probe.answer("haxelib", ["path", "reflaxe.ocaml"], "/pkg/src/\n-D reflaxe.ocaml=9.9.9\n");
		final report = inspect(probe, "source");
		assert(report.summary.exitCode == 1, "package version mismatch did not fail source capability");
		assert(findCheck(report, "target-package").status == DoctorStatus.Fail, "package mismatch diagnostic missing");
	}

	static function inspect(probe:FakeDoctorProbe, required:String):DoctorReport {
		return ReflaxeOcamlDoctor.inspect(probe, "/pkg", "/project", "1.2.3", required);
	}

	static function healthyProbe():FakeDoctorProbe {
		final probe = new FakeDoctorProbe("Mac");
		probe.answer("uname", ["-m"], "arm64\n");
		probe.answer("haxe", ["--version"], "4.3.7\n");
		probe.answer("haxelib", ["version"], "4.1.1\n");
		probe.answer("haxelib", ["path", "reflaxe"], "/reflaxe/src/\n-D reflaxe=4.0.0-beta\n");
		probe.answer("haxelib", ["path", "reflaxe.ocaml"], "/pkg/src/\n-D reflaxe.ocaml=1.2.3\n");
		probe.answer("ocamlc", ["-version"], "5.2.1\n");
		probe.answer("ocamlopt", ["-version"], "5.2.1\n");
		probe.answer("dune", ["--version"], "3.24.0\n");
		probe.answer("ocamlfind", ["printconf"], "Effective configuration\n");
		probe.answer("opam", ["--version"], "2.4.0\n");
		probe.answer("ocamlfind", ["query", "compiler-libs.common"], "/switch/compiler-libs\n");
		probe.answer("hxhx", ["--version"], "4.3.7\n");
		probe.directory("/pkg/std/runtime", ["HxArray.ml", "HxRuntime.ml", "HxString.ml"]);
		probe.file("/pkg/std/runtime/HxArray.ml", "");
		probe.file("/pkg/std/runtime/HxRuntime.ml", "");
		probe.file("/pkg/std/runtime/HxString.ml", "");
		probe.directory("/project", ["demo.opam.locked"]);
		probe.file("/project/demo.opam.locked", "");
		return probe;
	}

	static function findCheck(report:DoctorReport, id:String):DoctorCheck {
		for (entry in report.checks) {
			if (entry.id == id) {
				return entry;
			}
		}
		throw 'doctor check not found: $id';
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) {
			throw message;
		}
	}
}

private class FakeDoctorProbe implements DoctorProbe {
	final commands:Map<String, CommandResult> = [];
	final missing:Map<String, Bool> = [];
	final files:Map<String, String> = [];
	final directories:Map<String, Array<String>> = [];
	final environmentValues:Map<String, String> = [];
	final platform:String;

	public function new(platform:String) {
		this.platform = platform;
	}

	public function answer(command:String, args:Array<String>, stdout:String, code:Int = 0, stderr:String = ""):Void {
		commands.set(key(command, args), {code: code, stdout: stdout, stderr: stderr});
		missing.remove(command);
	}

	public function miss(command:String):Void {
		missing.set(command, true);
	}

	public function file(path:String, contents:String):Void {
		files.set(normalize(path), contents);
	}

	public function directory(path:String, entries:Array<String>):Void {
		final sorted = entries.copy();
		sorted.sort(compareStrings);
		directories.set(normalize(path), sorted);
	}

	public function run(command:String, args:Array<String>):CommandResult {
		if (missing.exists(command)) {
			return {code: 127, stdout: "", stderr: 'missing $command'};
		}
		return commands.get(key(command, args)) ?? {code: 127, stdout: "", stderr: 'unconfigured $command'};
	}

	public function findExecutable(command:String):Null<String> {
		return missing.exists(command) ? null : '/bin/$command';
	}

	public function exists(path:String):Bool {
		final normalized = normalize(path);
		return files.exists(normalized) || directories.exists(normalized);
	}

	public function isDirectory(path:String):Bool {
		return directories.exists(normalize(path));
	}

	public function readDirectory(path:String):Array<String> {
		final entries = directories.get(normalize(path));
		return entries == null ? [] : entries.copy();
	}

	public function readFile(path:String):Null<String> {
		return files.get(normalize(path));
	}

	public function absolutePath(path:String):String {
		return normalize(path.startsWith("/") ? path : Path.join(["/project", path]));
	}

	public function systemName():String {
		return platform;
	}

	public function environment(name:String):Null<String> {
		return environmentValues.get(name);
	}

	static function key(command:String, args:Array<String>):String {
		return command + "\n" + args.join("\n");
	}

	static function normalize(path:String):String {
		return Path.removeTrailingSlashes(Path.normalize(path));
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
