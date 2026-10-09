import backend.ocaml.HxhxOcamlTargetDeclarationAdapter;
import sys.io.File;

/** Keep class construction eligibility distinct before the shared target selects a layout. */
class SharedClassKindsFixture {
	static function main():Void {
		final path = "test/reflaxe_ocaml_shared_instance_values/source/ClassKinds.hx";
		final resolved = new ResolvedModule("ClassKinds", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final request = HxhxOcamlTargetDeclarationAdapter.fromModules(revision, [typed.getBackendProjection()]);
		final stock = StockClassKindsMacro.expected();
		var compared = 0;
		for (cls in request.copyClasses()) {
			final expectedInterface = cls.canonicalIdentity == "ClassKinds#Contract"
				|| cls.canonicalIdentity == "ClassKinds#ChildContract";
			final expectedExtern = cls.canonicalIdentity == "ClassKinds#External";
			final expectedParents = cls.canonicalIdentity == "ClassKinds#Implementation"
				|| cls.canonicalIdentity == "ClassKinds#ChildContract";
			if (cls.isInterface != expectedInterface
				|| cls.isExtern != expectedExtern
				|| cls.copyInterfaceTypeDisplays().length != (expectedParents ? 1 : 0))
				throw "authored class role or applied interface was lost for " + cls.canonicalIdentity;
			if (expectedParents && cls.copyInterfaceTypeDisplays()[0] != "ClassKinds.Contract<Int>")
				throw "applied interface argument changed for " + cls.canonicalIdentity + ": " + cls.copyInterfaceTypeDisplays()[0];
			final matches = stock.filter(row -> row.name == cls.canonicalIdentity);
			if (matches.length != 1
				|| matches[0].identity != cls.getCanonicalIdentity()
				|| matches[0].isInterface != cls.isInterface
				|| matches[0].isExtern != cls.isExtern
				|| matches[0].interfaces != cls.copyInterfaceTypeDisplays().join("|")) {
				final facts = new Array<Null<String>>();
				cls.addIdentity(facts);
				throw "class declarations differ between hosts for " + cls.canonicalIdentity + " stock="
					+ (matches.length == 1 ? matches[0].facts : "missing") + " native=" + haxe.Json.stringify(facts);
			}
			compared++;
		}
		if (compared != 5
			|| stock.length != compared
			|| CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "class-header inventory or original module revision changed";
		Sys.println("REFLAXE_OCAML_SHARED_CLASS_HEADERS:PASS");
	}
}
