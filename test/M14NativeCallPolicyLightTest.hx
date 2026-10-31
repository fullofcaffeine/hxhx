/**
	The Stage3 OCaml native-call policy and the shared runtime-fixture helper compile without the OCaml emitter.

	Why
	- `M14Stage3RuntimeFixture` prepares programs with the production Stage3
	  native-call policy. Neko and other target tests share that helper and
	  compile without `reflaxe.ocaml` on the classpath. When the helper and the
	  policy read the backend identity from `OcamlStage3Backend`, which loads
	  `EmitterStage`, those compiles failed with
	  "Type not found : reflaxe.ocaml.ast.OcamlASTPrinter".

	What
	- `test/m14_native_call_policy_light_test.hxml` has no `reflaxe.ocaml`
	  class path, so compiling this test is the main check.
	- At run time, only the builtin Stage3 OCaml identity selects the OCaml
	  policy; another OCaml backend id or implementation id selects none.
**/
class M14NativeCallPolicyLightTest {
	static function withIdentity(id:String, implId:String):backend.TargetDescriptor {
		final base = backend.cpp.CppNativeBackend.descriptor();
		return {
			id: id,
			implId: implId,
			abiVersion: base.abiVersion,
			priority: base.priority,
			description: base.description,
			capabilities: base.capabilities,
			requires: base.requires
		};
	}

	static function main():Void {
		// Keep the shared runtime-fixture helper in this reflaxe-free compile.
		final fixture:Class<M14Stage3RuntimeFixture> = M14Stage3RuntimeFixture;
		if (fixture == null)
			throw "shared runtime fixture helper is missing";
		final policy = backend.ocaml.Stage3OcamlNativeCallPolicy;
		if (policy.forBackend(withIdentity(policy.TARGET_ID, policy.IMPL_ID)) == null)
			throw "the builtin Stage3 OCaml backend lost its native call policy";
		if (policy.forBackend(withIdentity("ocaml-native", "builtin/reflaxe-ocaml")) != null)
			throw "another OCaml backend must expand the authored Map bodies";
		if (policy.forBackend(withIdentity(policy.TARGET_ID, "plugin/ocaml-stage3")) != null)
			throw "a plugin implementation must not receive the builtin native call policy";
		Sys.println("M14_NATIVE_CALL_POLICY_LIGHT:PASS");
	}
}
