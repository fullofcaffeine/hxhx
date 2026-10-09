import backend.ocaml.HxhxOcamlTargetFunctionAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;
import reflaxe.ocaml.target.OcamlTargetStaticCallFact;
import sys.io.File;

/** Prove shared method-body agreement separately from the unfinished whole-program route. */
class SharedInstanceMethodBodyFixture {
	static function main():Void {
		final path = "test/reflaxe_ocaml_shared_instance_values/source/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final stock = StockInstanceValuesMacro.expected();
		var compared = 0;
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions()) {
				final owner = cls.getSemanticInfo();
				if (owner == null)
					throw "instance method lost its declaring class";
				if (owner.getShortName() != "Sink" || HxFunctionDecl.getName(fn.getSourceDeclaration()) != "put")
					continue;
				final matches = stock.filter(row -> row.owner == "Sink" && row.name == "put");
				final fact = HxhxOcamlTargetFunctionAdapter.fromFunction(owner, fn);
				if (matches.length != 1 || !matches[0].admitted || fact == null)
					throw "both adapters must admit the original nullable instance method";
				if (fact.role != InstanceMethod
					|| fact.getCanonicalIdentity() != matches[0].identity
					|| new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact)) != matches[0].syntax)
					throw "shared method role, facts or syntax differ between hosts";
				// The class emitter adds the receiver; this signature covers only source arguments.
				if (new OcamlASTPrinter().printType(OcamlTargetFunctionLowerer.lower(fact, "portable").signature) != "Obj.t -> int")
					throw "shared instance method lost its nullable signature or captured its receiver too early";
				final wrongStaticCall = new OcamlTargetStaticCallFact({
					moduleId: fact.moduleId,
					sourceTypeName: fact.sourceTypeName,
					sourceFunctionName: fact.sourceFunctionName,
					argumentTypeDisplays: fact.copyArgumentTypeDisplays(),
					returnTypeDisplay: fact.returnTypeDisplay
				});
				if (wrongStaticCall.matchesFunction(fact))
					throw "an instance method cannot satisfy a static call even with identical value types";
				compared++;
			}
		if (compared != 1 || CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "instance method inventory or original typed revision changed";
		Sys.println("REFLAXE_OCAML_SHARED_INSTANCE_METHOD_BODY:PASS");
	}
}
