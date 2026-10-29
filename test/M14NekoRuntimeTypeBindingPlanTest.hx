/** Native-boundary observations isolate binding identity from standard-library startup. */
class M14NekoRuntimeTypeBindingPlanTest {
	static function main():Void {
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertExecutableProjections();
		@:privateAccess M14NekoRuntimeTypeRegistryIntegrationTest.assertForgedTypeObjects();
		@:privateAccess M14NekoRuntimeTypeRegistryIntegrationTest.assertFloatLiteralRepresentation();
		final module = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project("class Parent {} class Main {}");
		final program = new backend.vm.NekoTypedProgramProjection("mutable-type-bindings", [module]);
		final source = ["var symbols = $new(null);"];
		backend.vm.NekoRuntimeTypeRegistry.renderDefinition(source, program, [module], "symbols");
		backend.vm.NekoRuntimeTypeRegistry.renderPrelude(source, "symbols", program);
		// Replacement objects deliberately have no compiler metadata. Primitive
		// predicates use current bindings; nominal instances retain original facts.
		for (line in [
			'var old = __hxhx_runtime_type("core:Int");',
			'var cell = __hxhx_runtime_type_cell("core:Int");',
			'cell[0] = $$new(null);',
			'$$print(__hxhx_is_of_type(1, cell[0]), "\\n");',
			'$$print(__hxhx_is_of_type(1, old), "\\n");',
			'cell[0] = null; $$print(__hxhx_is_of_type(1, null), "\\n");',
			'cell[0] = 7; $$print(__hxhx_is_of_type(1, 7), "\\n");',
			'cell[0] = __hxhx_runtime_type("core:Bool");',
			'$$print(__hxhx_is_of_type(1, cell[0]) && __hxhx_is_of_type(true, cell[0]), "\\n");',
			'cell[0] = old;',
			'var parent = __hxhx_runtime_type("nominal:Main.Parent");',
			'var instance = $$new(null); instance.__hxhx_runtime_type = parent;',
			'__hxhx_runtime_type_cell("nominal:Main.Parent")[0] = $$new(null);',
			'$$print(__hxhx_type_get_class(instance) == parent, "\\n");',
			'$$print(__hxhx_is_of_type(instance, parent), "\\n");',
			'$$print(__hxhx_is_of_type(instance, __hxhx_runtime_type("nominal:Main.Parent")), "\\n");'
		])
			source.push(line);
		final root = ".tmp/neko_runtime_type_binding_plan";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.neko", source.join("\n"));
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("nekoc", [root + "/Main.neko"]);
		final output = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("neko", [root + "/Main.n"]);
		if (output != "true\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n")
			throw "runtime binding registry differs: " + output;
		Sys.println("NEKO_RUNTIME_TYPE_BINDING_PLAN:PASS");
	}
}
