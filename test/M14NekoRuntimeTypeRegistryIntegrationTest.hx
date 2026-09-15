/** Compare the authored registry contract with upstream and both generated Neko layouts. */
class M14NekoRuntimeTypeRegistryIntegrationTest {
	static function main():Void {
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertRuntimeFixture("test/neko_runtime_type_registry", true);
		assertForgedTypeObjects();
		Sys.println("NEKO_RUNTIME_TYPE_REGISTRY:PASS");
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
