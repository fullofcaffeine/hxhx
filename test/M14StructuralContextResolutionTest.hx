/** Context resolution must change child types without changing structural member declarations. */
class M14StructuralContextResolutionTest {
	static function main():Void {
		checkDeclarationFacts();
		for (entry in [
			{
				name: "inferred",
				result: "",
				target: "Methods<Int>",
				accepted: true
			},
			{
				name: "explicit",
				result: ":Array<Methods<Int>>",
				target: "Methods<Int>",
				accepted: true
			},
			{
				name: "method_to_variable",
				result: ":Array<Fields<Int>>",
				target: "Methods<Int>",
				accepted: false
			},
			{
				name: "wrong_result",
				result: ":Array<Methods<String>>",
				target: "Methods<Int>",
				accepted: false
			}
		]) {
			final root = ".tmp/structural-context-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'typedef Methods<T>={function get():T;function text():String;};'
				+ 'typedef Fields<T>={var get:()->T;var text:()->String;};'
				+ 'class Main{static function wrap(value:'
				+ entry.target
				+ ')'
				+ entry.result
				+ '{return [value];}static function main():Void{'
				+ 'var value:Methods<Int>={get:function():Int{return 7;},text:function():String{return "seven";}};'
				+ 'var values=wrap(value);trace(values[0].get());trace(values[0].text());}}';
			sys.io.File.saveContent(path, source);
			final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted)
				throw "upstream structural context differs: " + entry.name + stdout + stderr;
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
				typed.getBackendProjection();
			} catch (error:TyperError) {
				if (entry.accepted || error.message.indexOf("array element") < 0)
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "local structural context differs: " + entry.name;
			if (typed != null) {
				var observed = false;
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						if (method.getDeclaration().getSignature().getName() == "wrap") {
							final element = TyAliasExpansion.reveal(method.getEnvironment().getReturnType().getTypeArguments()[0]);
							for (field in element.getAnonymousFields())
								switch field.kind {
									case Method([]):
									case _:
										throw "inferred array result erased structural method kind";
								}
							observed = element.getAnonymousFields().length == 2;
						}
				if (!observed)
					throw "structural context observer missed inferred result declaration";
				M14Stage3RuntimeFixture.observe({command: "node", arguments: [root + "/upstream.js"], expected: path + ":1: 7\n" + path + ":1: seven\n"});
				JsRuntimeFixture.assertRuntime(typed, "Main", "7\nseven\n");
			}
			Sys.println("STRUCTURAL_CONTEXT:PASS " + entry.name);
		}
	}

	/** Preserve declaration facts and exact binder identities while resolving a genuinely unresolved child. */
	static function checkDeclarationFacts():Void {
		final owner = new TyNominalTypeId("Main.Marker");
		final binder = TyTypeParameterId.method(owner, false, "map", 0, 0, "T");
		final position = new HxPos(42, 3, 8);
		final stable = TyType.declaredAnonymous([
			{
				name: "map",
				type: TyType.functionType([TyType.typeParameter(binder)], TyType.typeParameter(binder)),
				kind: Method([binder]),
				isOptional: false,
				visibility: Public,
				metadata: [":methodMarker"],
				position: position
			},
			{
				name: "count",
				type: TyType.fromHintText("Int"),
				kind: Variable(true, "default", "never"),
				isOptional: true,
				visibility: Private,
				metadata: [":fieldMarker"],
				position: position
			}
		]);
		final resolved = @:privateAccess TyperStage.resolveTypeInContext(stable, null);
		if (resolved.getSemanticKey() != stable.getSemanticKey())
			throw "context resolution changed structural access, optionality, final status or method binders";
		for (index in 0...stable.getAnonymousFields().length) {
			final before = stable.getAnonymousFields()[index];
			final after = resolved.getAnonymousFields()[index];
			if (after.metadata.join(",") != before.metadata.join(",") || after.position != position)
				throw "context resolution dropped structural metadata or source position";
		}
		final fields = resolved.getAnonymousFields();
		final method = fields.filter(field -> field.name == "map")[0];
		switch method.kind {
			case Method([actual]) if (actual.equals(binder) && method.type.getFunctionReturn().getTypeParameterIdentity().equals(binder)):
			case _:
				throw "context resolution replaced exact method binder";
		}

		final source = "class Marker<T>{}class Main{}";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final context = new TyperContext(index, "Main.hx", "Main", "", [], "Main");
		final unresolved = TyType.declaredAnonymous([
			{
				name: "get",
				type: TyType.functionType([TyType.unresolved("T", [])], TyType.unresolved("Marker", [TyType.unresolved("T", [])])),
				kind: Method([binder]),
				isOptional: false,
				visibility: Public,
				metadata: [":resolvedMarker"],
				position: position
			}
		]);
		final childResolved = @:privateAccess TyperStage.resolveTypeInContext(unresolved, context, [binder]);
		final get = childResolved.getAnonymousFields()[0];
		final result = get.type.getFunctionReturn();
		if (result.getNominalIdentity() == null
			|| !result.getNominalIdentity().equals(owner)
			|| get.metadata[0] != ":resolvedMarker"
			|| !result.getTypeArguments()[0].getTypeParameterIdentity().equals(binder)
			|| !get.type.getFunctionArguments()[0].getTypeParameterIdentity().equals(binder))
			throw "structural declaration preservation skipped actual child resolution";
		switch get.kind {
			case Method([actual]) if (actual.equals(binder)):
			case _:
				throw "actual child resolution erased its method declaration";
		}
		Sys.println("STRUCTURAL_CONTEXT:PASS declaration_identity_and_child_resolution");
	}
}
