/** Signature-only imports must be ready before a caller retains its selected method. */
class M14SignatureDependencyLoadingIntegrationTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final root = ".tmp/signature_dependencies_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final sources = [
			{name: "Main", source: 'class Main { static function main():Void Sys.println(Api.accept("text")); }'},
			{name: "Api",
				source: 'class Api { public static function accept(value:Box):Bool return true;'
				+ ' public static function nested(value:Envelope<Box>):Envelope<Box> return value;'
				+ ' public static function callback(value:Box->Box):Box->Box return value;'
				+ ' public static function cycle(value:Left):Right return null; }'},
			{name: "Box", source: 'abstract Box(Dynamic) from Dynamic {}'},
			{name: "Other", source: 'class Other {} class Box {}'},
			{name: "Envelope", source: 'class Envelope<T> { public var value:T; }'},
			{name: "Left", source: 'class Left { public var right:Right; }'},
			{name: "Right", source: 'class Right { public var left:Left; }'},
			{name: "T", source: 'This file must not load for a local type parameter.'}
		];
		for (entry in sources)
			sys.io.File.saveContent(root + "/" + entry.name + ".hx", entry.source);
		final upstream = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		check(upstream == "true\n", "upstream signature dependency contract differs");
		for (shallow in [false, true]) {
			final resolved = shallow ? ResolverStage.parseProjectRootsShallow([root],
				["Main", "Other"]) : ResolverStage.parseProjectRoots([root], ["Main", "Other"]);
			final index = TyperIndex.build(resolved);
			check(index.resolveTypePath("Box", "", []) == null, "an unrelated module's secondary type must not capture an unloaded root type");
			check(index.resolveTypePath("missing.Box", "", []) == null, "a missing qualified type must not resolve by its final name");
			final prepared = new Array<String>();
			final loader = new ModuleLoader([root], new haxe.ds.StringMap<String>(), index, _ -> false, !shallow, null, module -> {
				final name = ResolvedModule.getModulePath(module);
				check(index.getDeclaredByModulePath(name).length == 0, "signature provider became visible before request preparation");
				prepared.push(name);
				return module;
			});
			loader.markResolvedAlready(resolved);
			final provider = loader.ensureTypeAvailable("Api", "", []);
			check(provider != null, "Api did not load");
			final method = provider.staticMethod("accept");
			check(method != null
				&& method.getArgs()[0].getSemanticKey() == "nominal:Box", "signature-only Box dependency remained unresolved");
			final selected = provider.declarationForSignature(method);
			check(selected != null
				&& selected.getIdentity().getCanonicalKey() == "Api#static:accept(required:nominal:Box)->primitive:Bool#0",
				"signature dependency lost the exact method identity");
			check(provider.staticMethod("nested").getArgs()[0].getSemanticKey() == "nominal:Envelope<nominal:Box>"
				&& provider.staticMethod("nested").getReturnType().getSemanticKey() == "nominal:Envelope<nominal:Box>",
				"nested signature arguments or return type remained unresolved");
			final callback = provider.staticMethod("callback").getArgs()[0];
			check(callback.isFunction()
				&& callback.getFunctionArguments()[0].getSemanticKey() == "nominal:Box"
				&& callback.getFunctionReturn().getSemanticKey() == "nominal:Box",
				"function signature dependencies remained unresolved");
			check(index.getByFullName("Envelope").fieldType("value").isTypeParameter() && index.getByFullName("T") == null,
				"a local type parameter loaded a same-spelled module");
			check(index.getByFullName("Left").fieldType("right").getSemanticKey() == "nominal:Right"
				&& index.getByFullName("Right").fieldType("left").getSemanticKey() == "nominal:Left",
				"cyclic signature types did not resolve");
			final added = loader.drainNewModules();
			check([for (module in added) if (ResolvedModule.getModulePath(module) == "Box") module].length == 1, "signature dependency must load once");
			check([for (name in prepared) if (name == "Box") name].length == 1, "signature dependency must be prepared once");
			for (module in resolved.concat(added))
				TyperStage.typeResolvedModule(module, index, loader);
			check(index.getByFullName("Api").declarationForSignature(method) == selected, "typing replaced a prepared declaration");
		}
		for (entry in sources)
			sys.FileSystem.deleteFile(root + "/" + entry.name + ".hx");
		sys.FileSystem.deleteDirectory(root);
		Sys.println("SIGNATURE_DEPENDENCY_LOADING:PASS");
	}
}
