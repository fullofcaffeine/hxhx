/** Interface parents must remain distinct from the superclass constructor chain. */
class M14InterfaceInheritanceFactsIntegrationTest {
	static function typeSource(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, _ -> false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader);
	}

	static function graph(source:String):TypedBackendClassGraph {
		final module = typeSource(source);
		final facts = [
			for (declaration in module.getBackendProjection().getClasses()) declaration.requireSemanticFacts()
		];
		return new TypedBackendClassGraph("interface-test", facts);
	}

	static function reject(action:Void->Void, message:String):Void {
		var rejected = false;
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "missing graph rejection: " + message;
	}

	static function check(module:HxModuleDecl):Void {
		for (declaration in HxModuleDecl.getClasses(module))
			if (HxClassDecl.getName(declaration) == "Diamond") {
				if (HxClassDecl.getExtendsPath(declaration) != "")
					throw "an interface parent was stored as a superclass constructor edge";
				if (HxClassDecl.getInterfaceExtendsPaths(declaration).join(",") != "Left,Right")
					throw "multiple interface parents lost their source order or identity";
				return;
			}
		throw "missing Diamond declaration";
	}

	static function main():Void {
		final source = sys.io.File.getContent("test/runtime_type_assignability/Main.hx");
		check(new HxParser(source).parseModule("Main"));
		check(ParserStage.parse(source, "Main.hx").getDecl());
		final scanned = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, "Main");
		var found = false;
		for (declaration in scanned)
			if (HxClassDecl.getName(declaration) == "Diamond") {
				found = true;
				if (HxClassDecl.getExtendsPath(declaration) != ""
					|| HxClassDecl.getInterfaceExtendsPaths(declaration).join(",") != "Left,Right")
					throw "helper-class scan changed interface parent ownership";
			}
		if (!found)
			throw "helper-class scan lost Diamond";
		final integrityModule = ParserStage.parse(source, "Main.hx");
		final integrityBefore = ParsedModuleIntegrity.revision(integrityModule);
		for (declaration in HxModuleDecl.getClasses(integrityModule.getDecl()))
			if (HxClassDecl.getName(declaration) == "Diamond") {
				final copy = HxClassDecl.getInterfaceExtendsPaths(declaration);
				copy.pop();
				if (HxClassDecl.getInterfaceExtendsPaths(declaration).length != 2)
					throw "copied interface paths mutated a parsed header";
				declaration.interfaceExtendsPaths.pop();
			}
		if (ParsedModuleIntegrity.revision(integrityModule) == integrityBefore)
			throw "parsed-module integrity ignored a changed interface parent";
		final membership = graph(source);
		final diamond = membership.findNode("Main.Diamond");
		if (diamond == null || !diamond.isInterface || diamond.superClassIdentity != null || diamond.interfaceTypes.length != 2)
			throw "typed graph lost the interface kind or its two parents";
		final closure = membership.requireAssignableTypes("Main.Child");
		final expected = [
			"Main.Child",
			"Main.Parent",
			"Main.Diamond",
			"Main.Left",
			"Main.Right",
			"Main.Root"
		];
		if (closure.length != expected.length)
			throw "runtime membership lost or repeated a diamond ancestor";
		for (node in closure)
			if (expected.indexOf(node.classIdentity) < 0)
				throw "runtime membership contains an unrelated type: " + node.classIdentity;
		final constructors = membership.requireLineage("Main.Child");
		if (constructors.length != 2 || constructors[0].classIdentity != "Main.Child" || constructors[1].classIdentity != "Main.Parent")
			throw "interface membership changed superclass constructor order";
		diamond.interfaceTypes.pop();
		if (membership.findNode("Main.Diamond").interfaceTypes.length != 2)
			throw "returned interface arrays mutated the graph";
		final changed = graph(StringTools.replace(source, "extends Left extends Right", "extends Right"));
		if (changed.getCanonicalIdentity() == membership.getCanonicalIdentity())
			throw "interface edits did not change graph identity";
		final beforeRevision = CompilerTypedModuleRevision.fromTypedModule(typeSource(source));
		final afterRevision = CompilerTypedModuleRevision.fromTypedModule(typeSource(StringTools.replace(source, "extends Left extends Right",
			"extends Right")));
		if (beforeRevision.publicInterfaceRevision == afterRevision.publicInterfaceRevision)
			throw "interface edits did not change the public module revision";
		final generic = graph("interface Root<T> {} interface Branch<T> extends Root<T> {} class Box<T> implements Branch<T> {} class Main {}");
		for (name in ["Main.Branch", "Main.Box"]) {
			final facts = generic.findClassFacts(name);
			final parameter = facts.getTypeParameterIds()[0];
			final argument = facts.getInterfaceTypes()[0].getTypeArguments()[0].getTypeParameterIdentity();
			if (argument == null || argument.getCanonicalKey() != parameter.getCanonicalKey())
				throw "an interface parent lost the owning generic binder: " + name;
		}
		if (generic.requireAssignableTypes("Main.Box").length != 3)
			throw "generic interface membership lost a nominal ancestor";
		reject(() -> graph("interface A extends B {} interface B extends A {} class Main {}"), "interface inheritance cycle");
		reject(() -> graph("class Plain {} interface A extends Plain {} class Main {}"), "interface parent is not an interface");
		final missing = graph("interface A extends Missing {} class Main {}");
		reject(() -> missing.requireAssignableTypes("Main.A"), "cannot identify interface parent");
		Sys.println("INTERFACE_INHERITANCE_FACTS:PASS");
	}
}
