import backend.BackendAbi;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

class M14Stage3EmitDynamicExceptionDiagnosticIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function ensureDirectory(path:String):Void {
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
	}

	static function main():Void {
		final tmpRoot = ".tmp/m14_stage3_emit_dynamic_exception_diagnostic";
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		deleteRecursive(tmpRoot);
		ensureDirectory(tmpRoot);
		ensureDirectory(srcDir);
		File.saveContent(haxe.io.Path.join([srcDir, "Main.hx"]), ["class Main {", "  static function main():Void {}", "}",].join("\n"));

		final code = Stage3Compiler.run([
			"--hxhx-backend",
			"fixture-dynamic-throw",
			"--hxhx-out",
			haxe.io.Path.join([tmpRoot, "out"]),
			"-cp",
			srcDir,
			"-main",
			"Main",
			"-D",
			"hxhx_backend_provider=M14Stage3EmitDynamicExceptionDiagnosticProvider",
		]);
		deleteRecursive(tmpRoot);
		assertTrue(code == 2, "non-string backend emit exception should become a structured Stage3 error code");
	}
}

class M14Stage3EmitDynamicExceptionDiagnosticProvider implements ITargetBackendProvider {
	public function new() {}

	public function registrations():Array<BackendRegistrationSpec> {
		final descriptor:backend.TargetDescriptor = {
			id: "fixture-dynamic-throw",
			implId: "fixture/dynamic-throw",
			abiVersion: BackendAbi.VERSION,
			priority: 1000,
			description: "Fixture backend that throws a non-string emit exception",
			capabilities: {
				supportsNoEmit: false,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: false
			},
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: []
			}
		};
		return [
			{
				descriptor: descriptor,
				create: function() return new TargetCoreBackend(descriptor, emit)
			}
		];
	}

	static function emit(_program:GenIrProgram, _context:BackendContext):EmitResult {
		throw new haxe.Exception("fixture non-string emit failure");
	}
}
