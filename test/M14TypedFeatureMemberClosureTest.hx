import sys.io.File;

/** Derive features from entry-point references without supplying expected feature names to the compiler. */
class M14TypedFeatureMemberClosureTest {
	static function main():Void {
		M14QuotationEnumDependenciesTest.run();
		check("FeatureInheritedAllocation", "child:on\nchild\n");
		check("FeatureContract",
			"late:on\ndefine:effect\nabsent:off\nunused:off\nmethod:on\nclass:on\nvalue:effect\nselected\ndefinition-value\nvalue:on\nactive:called\n");
		check("FeatureReferences", "hidden:on\nleaf:on\ncallback:on\ntrue\n");
		check("FeatureRecordCallback", "callback:on\nreceiver:on\ntrue\ntrue\ntrue\n");
		rejectUnownedCallableReads();
		Sys.println("TYPED_FEATURE_MEMBER_CLOSURE:PASS");
	}

	/** A structural exception must not admit missing, mismatched, or declaration-less nominal members. */
	static function rejectUnownedCallableReads():Void {
		final path = "FeatureMissingDeclaration.hx";
		final resolved = new ResolvedModule("FeatureMissingDeclaration", path,
			ParserStage.parse("class FeatureMissingDeclaration { static function main():Void {} }", path));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final owner = module.getTypedClasses()[0];
		final entry = owner.getFunctions()[0];
		final callable = TyType.fromHintText("String->Bool");
		final nominal = TyType.nominal(owner.getSemanticInfo().getIdentity(), [], null);
		final reads = [
			TypedExpr.nameRead("missing", callable, null),
			TypedExpr.fieldRead(TypedExpr.thisValue(nominal, null), "test", callable, null),
			TypedExpr.fieldRead(TypedExpr.thisValue(TyType.anonymous([], []), null), "test", callable, null),
			TypedExpr.fieldRead(TypedExpr.thisValue(TyType.anonymous(["test"], [TyType.fromHintText("Int->Bool")]), null), "test", callable, null),
			TypedExpr.fieldRead(TypedExpr.thisValue(TyType.fromHintText("Dynamic"), null), "test", callable, null)
		];
		for (read in reads) {
			final replacement = entry.withBody(new TypedFunctionBody([TypedStmt.expressionStmt(read, null)], entry.getBody().getSourceFingerprint()));
			final altered = module.withTypedClasses([owner.withFunctions([replacement])]);
			final program = new MacroExpandedProgram([altered], false);
			var diagnostic = "";
			try
				TypedFeatureMemberClosure.retain({
					program: program,
					classes: [],
					functions: [replacement],
					fields: []
				})
			catch (error:haxe.Exception)
				diagnostic = error.message;
			if (diagnostic != "feature member closure requires an exact method-value declaration")
				throw "member closure admitted an unsupported callable read: " + diagnostic;
		}
		Sys.println("TYPED_FEATURE_CALLABLE_NEGATIVES:PASS");
	}

	static function check(name:String, expected:String):Void {
		final path = "test/fixtures/js_feature_intrinsic/" + name + ".hx";
		final resolved = new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "member closure fixture requires one main declaration";
		var diagnostic = "";
		try {
			TypedFeatureMemberClosure.discover({
				program: program,
				classes: [],
				functions: [entries[0].withBody(entries[0].getBody())],
				fields: []
			});
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != "feature member closure requires an owned function")
			throw "member closure accepted a copied entry declaration: " + diagnostic;
		Sys.println("TYPED_FEATURE_MEMBER_OWNERSHIP:PASS");
		final discovery = TypedFeatureMemberClosure.discover({
			program: program,
			classes: [],
			functions: entries,
			fields: []
		});
		final names = discovery.namesFor(program);
		final lowered = TypedFeatureSelection.lower(program, names);
		M14GenericConstructorArgumentTest.assertRuntime(lowered.getTypedModules()[0], name, expected);
		Sys.println("TYPED_FEATURE_MEMBER_CLOSURE:" + name + ":PASS");
	}
}
