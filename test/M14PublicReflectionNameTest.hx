/** Public reflection names follow selected declarations rather than lookup spellings. */
class M14PublicReflectionNameTest {
	/** The independent compiler and runtime must finish successfully before output counts as evidence. */
	static function observe(command:String, arguments:Array<String>):String {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr != "")
			throw "reflection observer failed: " + stdout + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	static function program(source:ResolvedModule):MacroExpandedProgram {
		final index = TyperIndex.build([source]);
		return new MacroExpandedProgram([TyperStage.typeResolvedModule(source, index)], false);
	}

	static function facts(index:TyperIndex, identity:String):TypedBackendClassSemanticFacts {
		final info = index.getByFullName(identity);
		if (info == null)
			throw "missing reflection declaration: " + identity;
		return new TypedBackendClassSemanticFacts(info, null, [], null, info.getEnumDeclaration());
	}

	static function rejected(action:Void->Void, message:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "reflection name accepted unsupported declaration: " + message;
	}

	static function module(path:String, source:String):ResolvedModule
		return new ResolvedModule(path, path.split(".").join("/") + ".hx", ParserStage.parse(source, path.split(".").join("/") + ".hx"));

	static function main():Void {
		final root = "test/oracle/public_reflection_names_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		if (StringTools.trim(observe("haxe", ["--version"])) != "4.3.7")
			throw "public reflection contract requires Haxe 4.3.7";
		if (observe("haxe", ["-cp", root, "-main", "Main", "--interp"]) != expected)
			throw "upstream interpreter reflection names changed";
		final output = ".tmp/public_reflection_names_" + Std.string(Date.now().getTime());
		sys.FileSystem.createDirectory(output);
		observe("haxe", ["-cp", root, "-main", "Main", "-js", output + "/main.js"]);
		if (observe("node", [output + "/main.js"]) != expected)
			throw "upstream JavaScript reflection names changed";
		observe("haxe", ["-cp", root, "-main", "ExternNames", "-js", output + "/extern.js"]);
		if (observe("node", [output + "/extern.js"]) != "Array\nundefined\n")
			throw "extern reflection stopped depending on host metadata";
		final modules = [
			for (name in ["model.Types", "other.Types", "Selection"]) {
				final path = root + "/" + name.split(".").join("/") + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(sys.io.File.getContent(path), path));
			}
		];
		final index = TyperIndex.build(modules);
		for (entry in [
			{identity: "model.Types", name: "model.Types"},
			{identity: "model.Types.PublicLeaf", name: "model.PublicLeaf"},
			{identity: "model.Types.Hidden", name: "model._Types.Hidden"},
			{identity: "model.Types.PublicEnum", name: "model.PublicEnum"},
			{identity: "model.Types.HiddenEnum", name: "model._Types.HiddenEnum"},
			{identity: "model.Types.Renamed", name: "RenamedNative"},
			{identity: "model.Types.Ordinary", name: "model.Ordinary"},
			{identity: "other.Types.PublicLeaf", name: "other.PublicLeaf"}
		]) {
			final selected = facts(index, entry.identity);
			if (selected.requirePublicReflectionName() != entry.name || selected.getClassIdentity() != entry.identity)
				throw "public name changed declaration identity: " + entry.identity;
		}
		rejected(() -> facts(index, "model.Types.Specialized").requirePublicReflectionName(), "specialized");
		final loader = new ModuleLoader([root], new haxe.ds.StringMap(), index, _ -> false);
		loader.markResolvedAlready(modules);
		final selected = TyperStage.typeResolvedModule(modules[2], index, loader);
		final projected = selected.getBackendProjection().getClasses()[0];
		for (fn in projected.getFunctions()) {
			final name = HxFunctionDecl.getName(fn.getDeclaration());
			final occurrences = fn.getRuntimeTypeCatalog().getEntries();
			if (name == "shadow") {
				if (occurrences.length != 0)
					throw "a local alias became a reflected type";
			} else {
				final identity = name == "left" ? "model.Types.PublicLeaf" : "other.Types.PublicLeaf";
				if (occurrences.length != 1 || occurrences[0].getTarget().requireDeclarationIdentity().getCanonicalName() != identity)
					throw "import alias selected a different reflection owner";
			}
		}

		final baseline = module("sample.Types", "package sample; class Types {} class Leaf {}");
		final privateVersion = module("sample.Types", "package sample; class Types {} private class Leaf {}");
		final renamedVersion = module("sample.Types", 'package sample; class Types {} @:native("HostLeaf") class Leaf {}');
		final baselineFacts = facts(TyperIndex.build([baseline]), "sample.Types.Leaf");
		final baselineProgram = program(baseline);
		for (revision in [privateVersion, renamedVersion]) {
			if (facts(TyperIndex.build([revision]), "sample.Types.Leaf").getCanonicalIdentity() == baselineFacts.getCanonicalIdentity())
				throw "public-name change retained a stale semantic fingerprint";
			if (program(revision).getTypedProgramRevision().getCanonicalIdentity() == baselineProgram.getTypedProgramRevision().getCanonicalIdentity())
				throw "public-name change retained a stale program revision";
		}
		final cpp = new backend.cpp.CppTypedProgramProjection(baselineProgram);
		final ownedClass = cpp.requireClassIdentity("sample.Types.Leaf");
		if (cpp.requireClass(ownedClass).requireSemanticFacts().requirePublicReflectionName() != "sample.Leaf")
			throw "native projection lost the shared reflection name";
		final foreign = new backend.cpp.CppTypedProgramProjection(program(module("sample.Types", "package sample; class Types {} class Leaf {}")));
		rejected(() -> cpp.requireClass(foreign.requireClassIdentity("sample.Types.Leaf")), "foreign class declaration");
		final namedSource = HxModuleDecl.getClasses(ResolvedModule.getParsed(renamedVersion).getDecl())[1];
		final nameIndex = TyperIndex.build([renamedVersion]);
		HxClassDecl.getMetadata(namedSource).push('@:native("MutatedHost")');
		if (facts(nameIndex, "sample.Types.Leaf").requirePublicReflectionName() != "HostLeaf")
			throw "source metadata mutation changed the indexed reflection name";
		for (entry in [
			{source: "extern class Host {}", message: "extern"},
			{source: '@:native("TargetHost") extern class Host {}', message: "extern"},
			{source: "@:nativeGen class Host {}", message: "nativeGen"},
			{source: "@:generic class Host<T> {}", message: "specialized"}
		]) {
			final unsupported = TyperIndex.build([module("Host", entry.source)]);
			rejected(() -> facts(unsupported, "Host").requirePublicReflectionName(), entry.message);
		}
		final noClass = TyperIndex.build([module("Marker", "abstract Marker(Int) {}")]);
		rejected(() -> facts(noClass, "Marker").requirePublicReflectionName(), "abstract declarations");
		Sys.println("PUBLIC_REFLECTION_NAMES:PASS");
	}
}
