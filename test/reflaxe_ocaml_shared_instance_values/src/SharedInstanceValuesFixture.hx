import backend.BackendContext;
import backend.ocaml.HxhxOcamlTargetFunctionAdapter;
import backend.ocaml.OcamlNativeTargetCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import sys.io.File;

/** Require the original instance-call program through the shared target without Stage3 fallback. */
class SharedInstanceValuesFixture {
	static function main():Void {
		final fixture = "test/reflaxe_ocaml_shared_instance_values";
		if (Sys.command("node_modules/.bin/haxe", ["-cp", fixture + "/source", "-main", "Main", "--interp"]) != 0)
			throw "upstream instance-call assertions failed";
		Sys.println("SHARED_INSTANCE_VALUES:UPSTREAM_PASS");
		final path = fixture + "/source/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final stock = StockInstanceValuesMacro.expected();
		final rejected = new Array<String>();
		var compared = 0;
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions()) {
				final owner = cls.getSemanticInfo();
				if (owner == null)
					throw "instance fixture lost its declaring class";
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				final matches = stock.filter(row -> row.owner == owner.getShortName() && row.name == name);
				if (matches.length != 1)
					throw "instance method inventory differs for " + owner.getShortName() + "." + name;
				final fact = HxhxOcamlTargetFunctionAdapter.fromFunction(owner, fn);
				if (fact == null || !matches[0].admitted) {
					final failure = owner.getShortName() + "." + name + " stock=" + matches[0].admitted + " native=" + (fact != null);
					Sys.println("SHARED_INSTANCE_VALUES:REJECTED " + failure);
					rejected.push(failure);
				} else {
					if (fact.getCanonicalIdentity() != matches[0].identity)
						throw "instance method facts differ for " + owner.getShortName() + "." + name;
					compared++;
				}
			}
		if (rejected.length != 0)
			throw "shared instance-call support is incomplete: " + rejected.join("; ");
		if (compared != 3 || stock.length != compared)
			throw "instance fixture must retain its constructor, method and main";
		final output = ".tmp/shared-instance-values-" + Date.now().getTime() + "-" + Std.random(0x3fffffff);
		final defines = new haxe.ds.StringMap<String>();
		defines.set("reflaxe_ocaml_runtime_directory", sys.FileSystem.absolutePath("packages/reflaxe.ocaml/std/runtime"));
		final context = new BackendContext(sys.FileSystem.absolutePath(output), null, "Main", true, true, defines);
		new OcamlNativeTargetCore().emit(new MacroExpandedProgram([typed], false), context);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "instance adaptation changed the original typed module";
		if (Sys.command(output + "/_build/default/" + OcamlTargetProgramCore.ENTRY_NAME + ".exe", []) != 0)
			throw "generated native application failed its original instance-call assertions";
		Sys.println("REFLAXE_OCAML_SHARED_INSTANCE_VALUES:PASS");
	}
}
