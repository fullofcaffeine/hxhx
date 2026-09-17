/** Compare the authored registry contract with upstream and both generated Neko layouts. */
class M14NekoRuntimeTypeRegistryIntegrationTest {
	static function main():Void {
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertRuntimeFixture("test/neko_runtime_type_registry", true);
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertRuntimeFixture("test/neko_core_runtime_types", true);
		assertForgedTypeObjects();
		assertFloatLiteralRepresentation();
		Sys.println("NEKO_RUNTIME_TYPE_REGISTRY:PASS");
	}

	/**
		Observe the native representation produced from semantic Float constants.

		The runtime fixture covers parsed source. This observer also supplies NaN
		and infinities directly, as compile-time evaluation can produce those values.
		Native predicates here are independently authored expectations, not compiler
		output snapshots; every value must remain a Float and preserve its behavior.
	**/
	static function assertFloatLiteralRepresentation():Void {
		final cases:Array<{name:String, value:Float, predicate:String}> = [
			{name: "integral", value: 1.0, predicate: "value == 1.0"},
			{name: "positive-zero", value: 0.0, predicate: "1.0 / value > 0"},
			{name: "negative-zero", value: -0.0, predicate: "1.0 / value < 0"},
			{name: "nan", value: Math.NaN, predicate: "value != value"},
			{name: "positive-infinity", value: Math.POSITIVE_INFINITY, predicate: "value > 1.0 && 1.0 / value == 0.0"},
			{name: "negative-infinity", value: Math.NEGATIVE_INFINITY, predicate: "value < -1.0 && 1.0 / value == 0.0"},
			{name: "small-exponent", value: 1e-20, predicate: 'value == $$float("1e-20")'},
			{name: "large-exponent", value: 1e30, predicate: 'value == $$float("1e30")'},
			{name: "int-boundary", value: 2147483647.0, predicate: 'value == $$float("2147483647")'}
		];
		final source = new Array<String>();
		final expected = new StringBuf();
		for (entry in cases) {
			final literal = @:privateAccess backend.vm.NekoTargetCore.renderFloatLiteral(entry.value);
			source.push("var value = " + literal + ";");
			source.push('$$print(${haxe.Json.stringify(entry.name)}, ":", $$typeof(value) == $$tfloat, ":", ${entry.predicate}, "\\n");');
			expected.add(entry.name + ":true:true\n");
		}
		final root = ".tmp/neko_float_literals_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/main.neko", source.join("\n"));
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("nekoc", [root + "/main.neko"]);
		final output = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("neko", [root + "/main.n"]);
		if (output != expected.toString())
			throw "Float literal representation changed: " + root + "\n" + output;
		for (file in sys.FileSystem.readDirectory(root))
			sys.FileSystem.deleteFile(root + "/" + file);
		sys.FileSystem.deleteDirectory(root);
	}

	/** Native-boundary inputs can imitate object fields but must not acquire canonical type identity. */
	static function assertForgedTypeObjects():Void {
		final module = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project("class Parent {} class Main {}");
		final program = new backend.vm.NekoTypedProgramProjection("registry-boundary", [module]);
		final source = ["var symbols = $new(null);"];
		backend.vm.NekoRuntimeTypeRegistry.renderDefinition(source, program, [module], "symbols");
		backend.vm.NekoRuntimeTypeRegistry.renderPrelude(source, "symbols", program);
		// This observer supplies deliberately malformed native objects directly to
		// the runtime boundary. Compiler typing and class graphs remain Haxe-owned.
		for (line in [
			'var real = __hxhx_runtime_type("nominal:Main.Parent");',
			'var instance = $$new(null);',
			'instance.__hxhx_runtime_type = real;',
			'var fake = $$new(null);',
			'fake.identity = "nominal:Main.Parent";',
			'fake.name = "Parent";',
			'fake.kind = "class";',
			'$$print(__hxhx_is_of_type(instance, real), "\\n");',
			'$$print(__hxhx_is_of_type(instance, fake), "\\n");',
			'$$print(__hxhx_is_of_type(instance, "Parent"), "\\n");',
			'var enumValue = $$new(null);',
			'enumValue.__hx_ctor = "Parent";',
			'$$print(__hxhx_type_get_class(enumValue) == null, "\\n");'
		])
			source.push(line);
		final root = ".tmp/neko_registry_boundary_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/main.neko", source.join("\n"));
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("nekoc", [root + "/main.neko"]);
		final output = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("neko", [root + "/main.n"]);
		if (output != "true\nfalse\nfalse\ntrue\n")
			throw "fabricated native object acquired type identity: " + root;
		for (file in sys.FileSystem.readDirectory(root))
			sys.FileSystem.deleteFile(root + "/" + file);
		sys.FileSystem.deleteDirectory(root);
	}
}
