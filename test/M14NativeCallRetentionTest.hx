import backend.BackendRegistrationSpec;
import backend.BackendRegistry;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;
import hxhx.Stage3Compiler;

/** A real driver request must use the winning provider's native-call policy. */
class M14NativeCallRetentionTest {
	static function main():Void
		run();

	public static function run():Void {
		if (backend.cpp.CppNativeCallPolicy.forBackend(BackendRegistry.descriptorForTarget("cpp-native")) == null)
			throw "builtin C++ lost its native call policy";
		for (builtin in [false, true]) {
			NativeCallRetentionProvider.observed = false;
			final output = ".tmp/native-call-retention-" + (builtin ? "builtin" : "plugin");
			if (sys.FileSystem.exists(output))
				@:privateAccess JsRuntimeFixture.removeOutput(output);
			var arguments = [
				"--hxhx-backend",
				"cpp-native",
				"--hxhx-no-run",
				"--hxhx-out",
				output,
				"-cp",
				"test/oracle/cpp_managed_map_type_seed/src",
				"-main",
				"Main"
			];
			if (!builtin)
				arguments = arguments.concat(["-D", "hxhx_backend_provider=NativeCallRetentionProvider"]);
			final code = Stage3Compiler.run(arguments);
			if (code != 0 || NativeCallRetentionProvider.observed == builtin)
				throw "driver did not prove the selected provider's native call policy";
			if (builtin) {
				final process = new sys.io.Process(output + "/Main", []);
				final stdout = process.stdout.readAll().toString();
				final stderr = process.stderr.readAll().toString();
				final status = process.exitCode();
				process.close();
				if (status != 0
					|| stderr != ""
					|| stdout != sys.io.File.getContent("test/oracle/cpp_managed_map_type_seed/expected.stdout"))
					throw "production native Map output differs: " + stdout + stderr;
			} else if (sys.io.File.getContent(output + "/observed.txt") != "haxe.Constraints.IMap")
				throw "provider observation artifact differs from its exact selected declaration";
			@:privateAccess JsRuntimeFixture.removeOutput(output);
		}
		BackendRegistry.clearDynamicRegistrations();
		if (backend.cpp.CppNativeCallPolicy.forBackend(BackendRegistry.descriptorForTarget("cpp-native")) == null)
			throw "request cleanup did not restore the builtin native call policy";
		Sys.println("NATIVE_CALL_RETENTION_DRIVER:PASS");
	}
}

/** Observe prepared call ownership without pretending to implement native Map execution. */
class NativeCallRetentionProvider implements ITargetBackendProvider {
	public static var observed:Bool = false;

	public function new() {}

	public function registrations():Array<BackendRegistrationSpec> {
		final builtin = backend.cpp.CppNativeBackend.descriptor();
		final descriptor:backend.TargetDescriptor = {
			id: builtin.id,
			implId: "fixture/native-call-retention",
			abiVersion: builtin.abiVersion,
			priority: builtin.priority + 1,
			description: "Observe provider-owned call preparation",
			capabilities: {
				supportsNoEmit: false,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: false
			},
			requires: builtin.requires
		};
		return [
			{
				descriptor: descriptor,
				create: () -> new TargetCoreBackend(descriptor, observe)
			}
		];
	}

	static function observe(program:backend.GenIrProgram, context:backend.BackendContext):backend.EmitResult {
		final expected = "haxe.Constraints.IMap";
		var calls = 0;
		for (module in program.getTypedModules())
			if (module.getSourceOrigin().sourceModulePath == "Main")
				for (owner in module.getBackendProjection().getClasses())
					for (fn in owner.getFunctions())
						if (HxFunctionDecl.getName(fn.getDeclaration()) == "contextualValue")
							for (statement in fn.getBody())
								TypedBackendSourceWalk.statement(statement, expression -> {
									final call = fn.findInstanceCall(expression);
									if (call == null)
										return;
									if (call.getDeclaration().getOwner().getCanonicalName() != expected
										|| call.getDeclaration().getSignature().getName() != "get")
										throw "driver used another provider's call preparation";
									calls++;
								}, _ -> {});
		if (calls != 1)
			throw "provider observation did not reach the exact Map call";
		program.assertTypedBodyRevisionsCurrent();
		observed = true;
		sys.FileSystem.createDirectory(context.outputDir);
		final path = context.outputDir + "/observed.txt";
		sys.io.File.saveContent(path, expected);
		return new backend.EmitResult(path, [new backend.EmitArtifact("call-observation", path)], false);
	}
}
