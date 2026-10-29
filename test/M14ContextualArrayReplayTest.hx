/**
	Checked Array literals keep their selected storage type across call replay.
	Their original record and null children remain visible, while comprehensions
	must validate every yield before the same context can be retained.
 */
class M14ContextualArrayReplayTest {
	static function main():Void {
		checkOccurrences();
		final declarations = 'enum Kind{Named(name:String);}typedef Row={var name:String;var ?type:Kind;};'
			+ 'typedef Rows=Array<Row>;enum Form{Vars(rows:Rows);}';
		final helpers = 'class Main{static function take(rows:Rows):Int{return rows.length;}'
			+ 'static function required(rows:Array<{name:String,type:Kind}>):Int{return rows.length;}'
			+ 'static function strings(values:Array<String>):Int{return values.length;}';
		for (entry in [
			{name: "enum_null_field", body: 'var result:Form=Vars([{name:"x",type:null}]);', accepted: true},
			{name: "function_null_field", body: 'take([{name:"x",type:null}]);', accepted: true},
			{name: "required_null_field", body: 'required([{name:"x",type:null}]);', accepted: true},
			{name: "typed_intermediate", body: 'var rows:Rows=[{name:"x",type:null}];take(rows);', accepted: true},
			{name: "comprehension_null_field", body: 'take([for(name in ["x"]) {name:name,type:null}]);', accepted: true},
			{name: "comprehension_wrong_primitive", body: 'strings([for(name in ["x"]) 1]);', accepted: false},
			{name: "comprehension_wrong_yes", body: 'strings([for(name in ["x"]) if(name=="x") 1 else name]);', accepted: false},
			{name: "comprehension_wrong_no", body: 'strings([for(name in ["x"]) if(name=="x") name else 1]);', accepted: false},
			{name: "comprehension_wrong_nested", body: 'strings([for(name in ["x"]) for(value in [1]) value]);', accepted: false},
			{name: "comprehension_wrong_field", body: 'take([for(name in ["x"]) {name:name,type:"wrong"}]);', accepted: false},
			{name: "map_is_not_array", body: 'strings([for(name in ["x"]) name=>name]);', accepted: false},
			{name: "literal_wrong_field", body: 'take([{name:"x",type:"wrong"}]);', accepted: false},
			{name: "missing_required_field", body: 'required([{name:"x"}]);', accepted: false},
			{name: "declared_dynamic_array", body: 'var values:Array<Dynamic>=[];take(values);', accepted: false}
		]) {
			final root = ".tmp/contextual-array-replay-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = declarations + helpers + 'static function main():Void{' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final status = upstream.exitCode();
			upstream.close();
			if ((status == 0) != entry.accepted)
				throw "upstream contextual Array acceptance differs: " + entry.name + output + errors;
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
			} catch (error:TyperError) {
				if (entry.accepted)
					throw error;
				if (error.message.indexOf("not compatible") < 0
					&& error.message.indexOf("No compatible") < 0
					&& !(entry.name == "missing_required_field" && error.message == "missing object literal field type"))
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "local contextual Array acceptance differs: " + entry.name;
			if (typed != null)
				checkTypedChildren(typed, entry.name);
			// These checks observe typing. A separate retained comprehension
			// projection limit is not permission to skip or weaken its conversion.
			Sys.println("CONTEXTUAL_ARRAY_REPLAY:PASS " + entry.name);
		}
		checkRuntime(declarations + helpers);
	}

	/** Exact source occurrences and candidate copies keep independent ownership. */
	static function checkOccurrences():Void {
		final scope = new TyFunctionEnv("array-context-replay", [], [], TyType.unknown(), TyType.unknown());
		final inference = scope.getInference();
		final array = new TyNominalTypeId("Array");
		final selected = TyType.nominal(array, [TyType.anonymous(["name"], [TyType.fromHintText("String")])]);
		final original:HxExpr = EArrayDecl([EAnon(["name"], [EString("x")])]);
		final other:HxExpr = EArrayDecl([EAnon(["name"], [EString("x")])]);
		inference.contextualCollection(original, selected);
		final candidate = scope.copyForInference();
		candidate.getInference().contextualCollection(other, selected);
		if (!inference.expressionType(other, TyType.unknown(), scope).isUnknown())
			throw "rejected candidate leaked its collection occurrence";
		final different = TyType.nominal(array, [TyType.fromHintText("Int")]);
		if (inference.contextualCollection(original, different).getSemanticKey() != selected.getSemanticKey())
			throw "a later context replaced the authoritative original occurrence";
		inference.seal([]);
		if (inference.expressionType(original, different, scope).getSemanticKey() != selected.getSemanticKey())
			throw "sealed replay ignored its original collection occurrence";
		if (!inference.expressionType(other, TyType.unknown(), scope).isUnknown())
			throw "sealed replay fabricated an occurrence for an equal-shaped array";
		var missingRejected = false;
		try {
			inference.contextualCollection(other, selected);
		} catch (error:String) {
			missingRejected = error == "contextual collection occurrence is absent from sealed inference";
		}
		if (!missingRejected)
			throw "sealed inference allowed a new collection fact";
		final signature = (type:TyType) -> new TyFunSig("choose", true, ["values"], [type], [false], [false], TyType.fromHintText("Void"), HxPos.unknown());
		if (TyCallArgumentContext.shared([signature(selected), signature(different)], 1)[0] != null)
			throw "disagreeing overloads published a shared collection context";
		Sys.println("CONTEXTUAL_ARRAY_REPLAY:PASS occurrence_candidate_sealing");
	}

	/** Storage context must not erase the authored record or its null-valued child. */
	static function checkTypedChildren(typed:TypedModule, name:String):Void {
		var arrays = 0;
		var records = 0;
		var nulls = 0;
		var selected = 0;
		function inspect(expression:TypedExpr):Void {
			if (expression.getTag() == ArrayDecl)
				arrays++;
			if (expression.getTag() == Anonymous)
				records++;
			if (expression.getTag() == NullValue)
				if (expression.getType().isNullLiteral())
					nulls++;
				else
					throw "context erased an original null child type";
			final declaration = expression.getDeclaration();
			if (declaration != null && declaration.getIsEnumConstructor() && declaration.getSignature().getName() == "Vars") {
				if (declaration.getOwner().getCanonicalName() != "Main.Form")
					throw "contextual Array changed the selected enum owner";
				final expected = declaration.getSignature().getArgs()[0];
				final argument = expression.getExpressions()[1].getType();
				if (argument.getSemanticKey() != expected.getSemanticKey()
					|| argument.getAliasDefinition() != expected.getAliasDefinition())
					throw "Array argument lost the exact selected storage context";
				final fields = TyAliasExpansion.revealNonNullable(TypedArrayLiteral.elementType(argument)).getAnonymousFields();
				final types = fields.filter(field -> field.name == "type");
				if (types.length != 1 || !types[0].isOptional || types[0].type.getNominalIdentity().getCanonicalName() != "Main.Kind")
					throw "Array storage context lost optional-field or enum identity";
				selected++;
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		function statement(value:TypedStmt):Void {
			for (expression in value.getExpressions())
				inspect(expression);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				if (HxFunctionDecl.getName(method.getSourceDeclaration()) == "main")
					for (body in method.getBody().getStatements())
						statement(body);
		if (arrays == 0 || records == 0 || nulls == 0 || (name == "enum_null_field" && selected != 1))
			throw "contextual Array replay lost original children or call selection: " + name;
	}

	/** Compare real generated JavaScript with upstream, including constructor payload replay. */
	static function checkRuntime(prefix:String):Void {
		final root = ".tmp/contextual-array-replay-runtime";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = prefix
			+ 'static function main():Void{trace(take([{name:"direct",type:null}]));'
			+ 'var value:Form=Vars([{name:"enum",type:null}]);switch(value){case Vars(rows):trace(rows[0].name);trace(rows[0].type==null);}'
			+ 'var kind:Kind=Named("payload");switch(kind){case Named(name):trace(name);}'
			+ 'trace(strings([for(name in ["x","y"]) name]));}}';
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		final expected = "1\nenum\ntrue\npayload\n2\n";
		final expectedUpstream = expected.split("\n")
			.filter(line -> line != "")
			.map(line -> path + ":1: " + line + "\n")
			.join("");
		if (status != 0 || output != expectedUpstream || errors != "")
			throw "upstream contextual Array runtime differs: " + output + errors;
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("CONTEXTUAL_ARRAY_REPLAY:PASS generated_runtime");
	}
}
