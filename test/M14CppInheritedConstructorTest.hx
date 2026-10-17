/** Execute real inherited construction under forced collection and native sanitizers. */
class M14CppInheritedConstructorTest {
	static function main():Void {
		assertOwnership();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		for (throwing in [false, true]) {
			final root = "test/oracle/cpp_inherited_constructor" + (throwing ? "_throw" : "") + "_seed";
			if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", throwing ? "Upstream" : "Main", "--interp"]) != 0)
				throw "upstream inherited construction contract differs";
			M14CppManagedStartupExecutionTest.runFixture({
				sourceRoot: root,
				output: ".tmp/cpp-inherited-constructor" + (throwing ? "-throw" : ""),
				observer: "test/cpp_managed_heap/" + (throwing ? "InstanceInitializerThrowObserver.cpp" : "InstanceInitializerCaptureObserver.cpp")
			});
		}
		Sys.println("CPP_INHERITED_CONSTRUCTOR:PASS");
	}

	/** Forwarding authorizes exact child fields without permitting another application's fields. */
	static function assertOwnership():Void {
		final path = "test/oracle/cpp_inherited_constructor_seed/Main.hx";
		final source = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(source, TyperIndex.build([source]));
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final storage = new backend.cpp.CppManagedClassStorage(program);
		final selected = new haxe.ds.StringMap<backend.cpp.CppManagedFunctionApplication>();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (fn in owner.getFunctions())
					for (entry in fn.getConstructorCatalog().getEntries())
						if (!entry.getIsSuperCall())
							selected.set(entry.getConstructedType().getNominalIdentity().getCanonicalName(), storage.constructorApplication(entry));
		final child = selected.get("Main.Child");
		final explicit = selected.get("Main.Explicit");
		final base = selected.get("Main.Base");
		final sibling = selected.get("Main.Sibling");
		if (child == null || explicit == null || child.projection == explicit.projection)
			throw "inherited ownership fixture lost its distinct constructor bodies";
		if (base == null
			|| sibling == null
			|| child.projection != base.projection
			|| child.projection != sibling.projection
			|| child.identity == base.identity
			|| child.identity == sibling.identity
			|| base.identity == sibling.identity)
			throw "constructor entries conflated distinct initializer obligations";
		final forwarded = child.getForwardedTypes();
		forwarded.resize(0);
		if (child.getForwardedTypes().length != 2)
			throw "constructor application exposed mutable forwarding obligations";
		final fields = storage.constructorInitializers(child.projection, child);
		if ([for (field in fields) field.projection.getField().getName()].join(",") != "child,middle,base")
			throw "constructor application lost exact field order";
		var rejected = false;
		try {
			storage.constructorInitializers(child.projection, explicit);
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf("another application") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "constructor accepted another application's initializer obligations";
		rejected = false;
		try {
			new backend.cpp.CppManagedInitializerFunctions({
				projection: explicit.projection,
				application: explicit,
				classes: storage,
				rootSymbol: "entry",
				symbolPrefix: "hxhx_function_entry"
			}, fields[0], "hxhx_function_foreign");
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf("exact constructor owner") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "constructor accepted a field from another forwarding application";
	}
}
