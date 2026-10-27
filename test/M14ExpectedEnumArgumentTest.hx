import sys.io.File;

/** Expected parameters select exact enum values without changing lexical shadowing or field declarations. */
class M14ExpectedEnumArgumentTest {
	static final providers = [
		{path: "Flag.hx", source: 'enum Flag{Yes;No;Named(value:String);}'},
		{path: "Other.hx", source: 'enum Other{Yes;No;}'},
		{path: "Choice.hx", source: 'enum Choice<T>{None;Some(value:T);}'},
		{path: "Functions.hx", source: 'function Yes():Flag{return Flag.Yes;}'}
	];

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Each source is checked independently by upstream and by the production declaration loader. */
	static function check(name:String, source:String, accepted:Bool, ?fieldOwner:String, ?appliedArgument:String):Void {
		final root = ".tmp/expected-enum-argument-" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		for (provider in providers)
			File.saveContent(root + "/" + provider.path, provider.source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		final output = upstream.stdout.readAll().toString() + upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		require((status == 0) == accepted, "upstream enum argument contract differs: " + name + output);
		var typed:Null<TypedModule> = null;
		try {
			typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			require(error.message.indexOf("compatible") >= 0 || error.message.indexOf("should be") >= 0,
				"unrelated rejection in "
				+ name
				+ ": "
				+ error.message);
		}
		require((typed != null) == accepted, "local enum argument contract differs: " + name);
		if (typed != null) {
			var fields = 0;
			var calls = 0;
			function expression(value:TypedExpr):Void {
				final field = value.getFieldInfo();
				if (field != null
					&& field.getOwner().getCanonicalName() == fieldOwner
					&& (field.getName() == "Yes" || field.getName() == "None")) {
					require(field.getCanonicalKey() == fieldOwner + "#static#" + field.getName(), "selected field identity changed");
					require(value.getType().getNominalIdentity().getCanonicalName() == fieldOwner, "value and selected enum owners disagree");
					if (appliedArgument != null) {
						require(value.getType().getTypeArguments()[0].getSemanticKey() == TyType.fromHintText(appliedArgument).getSemanticKey(),
							"enum value lost its concrete owner application");
						require(field.getType().getTypeArguments()[0].getTypeParameterIdentity() != null,
							"applying an enum value mutated its original generic field declaration");
					}
					fields++;
				}
				final declaration = value.getDeclaration();
				if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "take") {
					require(declaration.getOwner().getCanonicalName() == "Main", "parameter context changed the selected callable");
					final parameter = TyAliasExpansion.revealNonNullable(declaration.getSignature().getArgs()[0]);
					require(parameter.getNominalIdentity() != null, "selected parameter lost its exact enum declaration");
					calls++;
				}
				for (child in value.getExpressions())
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (body in method.getBody().getStatements())
						statement(body);
			if (fieldOwner != null)
				require(fields > 0, "no exact singleton field was published: " + name);
			require(calls > 0, "no exact take declaration was published: " + name);
			typed.getBackendProjection();
		}
		Sys.println("EXPECTED_ENUM_ARGUMENT:PASS " + name);
	}

	/** Only unanimous complete indexed enum applications can guide the first operand visit. */
	static function checkContexts():Void {
		final source = 'typedef Selected=Null<Choice<String>>;class Main{static function take(value:Selected):Void{}}';
		final modules = [new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"))].concat([
			for (provider in providers)
				new ResolvedModule(provider.path.substr(0, provider.path.length - 3), provider.path, ParserStage.parse(provider.source, provider.path))
		]);
		final index = TyperIndex.build(modules);
		final selected = index.getByFullName("Main").staticMethod("take").getArgs()[0];
		function signature(type:TyType, rest:Bool = false):TyFunSig {
			return new TyFunSig("take", true, ["value"], [type], [false], [rest], TyType.fromHintText("Void"), HxPos.unknown());
		}
		final context = TyCallArgumentContext.shared([signature(selected), signature(selected)], 1, null, index)[0];
		require(context != null
			&& context.getSemanticKey() == selected.getSemanticKey()
			&& context.getAliasDefinition() == selected.getAliasDefinition(),
			"shared enum context lost its exact nullable alias");
		final owner = new TyNominalTypeId("Choice");
		final method = new TyTypeParameterId("enum-method", 0, "T");
		final cases = [
			[
				signature(selected),
				signature(TyType.nominal(owner, [TyType.fromHintText("Int")]))
			],
			[
				signature(TyType.nominal(new TyNominalTypeId("Flag"), [])),
				signature(TyType.nominal(new TyNominalTypeId("Other"), []))
			],
			[signature(TyType.nominal(owner, [TyType.unknown()]))],
			[signature(TyType.fromHintText("Choice<String>"))],
			[signature(TyType.nominal(new TyNominalTypeId("Missing"), []))],
			[signature(selected, true)]
		];
		for (signatures in cases)
			require(TyCallArgumentContext.shared(signatures, 1, null, index)[0] == null, "unsupported enum context escaped consensus");
		require(TyCallArgumentContext.shared([signature(selected)], 1)[0] == null, "enum context lacked an authentic declaration index");
		require(TyCallArgumentContext.shared([signature(selected)], 0, null, index).length == 0, "omitted argument invented an enum context");
		require(TyCallArgumentContext.shared([signature(TyType.nominal(owner, [TyType.typeParameter(method)]))], 1, [[method]], index)[0] == null,
			"method-owned enum binder became a rigid expected argument");
		Sys.println("EXPECTED_ENUM_ARGUMENT:PASS consensus_and_binders");
	}

	/** Observe exact enum owners, payloads, and call order after real JavaScript generation. */
	static function checkRuntime():Void {
		final source = 'import Other;class Main{static var effects:String="";'
			+ 'static function take(value:Flag):Void{effects+="f";switch(value){case Yes:trace("flag");case No:trace("no");case Named(text):trace(text);}}'
			+ 'static function other(value:Other):Void{effects+="o";switch(value){case Yes:trace("other");case No:trace("no");}}'
			+ 'static function text():String{effects+="v";return "payload";}'
			+ 'static function main():Void{take(Yes);other(Yes);take(Named(text()));take(Flag.Yes);trace(effects);}}';
		final root = ".tmp/expected-enum-argument-runtime";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		for (provider in providers)
			File.saveContent(root + "/" + provider.path, provider.source);
		final expected = "flag\nother\npayload\nflag\nfovff\n";
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		require(status == 0
			&& errors == ""
			&& output == expected.split("\n")
				.filter(line -> line != "")
				.map(line -> root + "/Main.hx:1: " + line + "\n")
				.join(""),
			"upstream enum runtime differs: "
			+ output
			+ errors);
		final modules = [
			new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"))
		].concat([
			for (provider in providers.slice(0, 2))
				new ResolvedModule(provider.path.substr(0, provider.path.length - 3), root + "/" + provider.path,
					ParserStage.parse(provider.source, root + "/" + provider.path))
		]);
		final index = TyperIndex.build(modules);
		final typed = [for (module in modules) TyperStage.typeResolvedModule(module, index)];
		JsRuntimeFixture.assertProgramRuntime(new MacroExpandedProgram(typed, false), "Main", expected);
		Sys.println("EXPECTED_ENUM_ARGUMENT:PASS generated_runtime");
	}

	static function main():Void {
		checkContexts();
		final base = 'class Main{static function take(value:Flag):Bool{return true;}';
		for (entry in [
			{
				name: "implicit",
				prefix: "",
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "other_enum",
				prefix: 'import Other;',
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "explicit_other_field",
				prefix: 'import Other.Yes;',
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "module_function",
				prefix: 'import Functions;',
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "explicit_function",
				prefix: 'import Functions.Yes;',
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "same_module_enum",
				prefix: 'enum Other{Yes;No;}',
				members: "",
				body: 'take(Yes);',
				accepted: true
			},
			{
				name: "local_annotation",
				prefix: "",
				members: "",
				body: 'var value:Flag=Yes;take(value);',
				accepted: true
			},
			{
				name: "return",
				prefix: "",
				members: 'static function selected():Flag{return Yes;}',
				body: 'take(selected());',
				accepted: true
			},
			{
				name: "qualified",
				prefix: "",
				members: "",
				body: 'take(Flag.Yes);',
				accepted: true
			},
			{
				name: "local_shadow",
				prefix: "",
				members: "",
				body: 'var Yes:String="shadow";take(Yes);',
				accepted: false
			},
			{
				name: "current_field",
				prefix: "",
				members: 'static var Yes:String="shadow";',
				body: 'take(Yes);',
				accepted: false
			},
			{
				name: "current_method",
				prefix: 'import Other;',
				members: 'static function Yes():Flag{return Flag.Yes;}',
				body: 'take(Yes);',
				accepted: false
			},
			{
				name: "same_module_function",
				prefix: 'function Yes():Flag{return Flag.Yes;}',
				members: "",
				body: 'take(Yes);',
				accepted: false
			},
			{
				name: "no_context",
				prefix: "",
				members: "",
				body: 'var value=Yes;take(value);',
				accepted: false
			},
			{
				name: "qualified_wrong_owner",
				prefix: "",
				members: "",
				body: 'take(Other.Yes);',
				accepted: false
			},
			{
				name: "wrong_primitive",
				prefix: "",
				members: "",
				body: 'take("wrong");',
				accepted: false
			},
			{
				name: "payload",
				prefix: "",
				members: "",
				body: 'take(Named("payload"));',
				accepted: true
			}
		])
			check(entry.name, entry.prefix + base + entry.members + 'static function main():Void{' + entry.body + '}}',
				entry.accepted, entry.accepted && entry.name != "payload" ? "Flag" : null);
		check("instance",
			'class Main{function new(){}function take(value:Flag):Bool{return true;}function observe():Void{take(Yes);}static function main():Void{new Main().observe();}}',
			true, "Flag");
		for (member in ['var Yes:String="shadow";', 'function Yes():Flag{return Flag.Yes;}'])
			check("instance_shadow_"
				+ (member.indexOf("function") == 0 ? "method" : "field"),
				'class Main{'
				+ member
				+
				'function new(){}function take(value:Flag):Bool{return true;}function observe():Void{take(Yes);}static function main():Void{new Main().observe();}}',
				false);
		check("no_context_import", 'import Other;class Main{static function take(value:Other):Void{}static function main():Void{var value=Yes;take(value);}}',
			true, "Other");
		check("nullable_alias", 'typedef Selected=Null<Flag>;class Main{static function take(value:Selected):Void{}static function main():Void{take(Yes);}}',
			true, "Flag");
		for (body in ['take(None);', 'take(Choice.None);'])
			check("generic_"
				+ (body.indexOf("Choice") >= 0 ? "qualified" : "implicit"),
				'class Main{static function take(value:Choice<String>):Void{}static function main():Void{'
				+ body
				+ '}}', true, "Choice", "String");
		check("generic_alias",
			'typedef Selected=Null<Choice<String>>;class Main{static function take(value:Selected):Void{}static function main():Void{take(None);}}', true,
			"Choice", "String");
		check("generic_wrong_payload", 'class Main{static function take(value:Choice<String>):Void{}static function main():Void{take(Choice.Some(1));}}',
			false);
		check("inherited_static",
			'class Parent{public var Yes:String="parent";}class Main extends Parent{static function take(value:Flag):Bool{return true;}static function main():Void{take(Yes);}}',
			true, "Flag");
		checkInheritedField();
		checkRuntime();
	}

	/** Sharing field lookup must keep an ordinary inherited owner's generic application. */
	static function checkInheritedField():Void {
		final root = ".tmp/expected-enum-argument-inherited-generic";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'class Parent<T>{public var value:T;public function new(value:T){this.value=value;}}'
			+ 'class Main extends Parent<String>{public function new(){super("ok");}function observe():String{return value;}'
			+ 'static function main():Void{trace(new Main().observe());}}';
		File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		final output = upstream.stdout.readAll().toString() + upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		require(status == 0, "upstream inherited generic field differs: " + output);
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		var found = false;
		function inspect(value:TypedExpr):Void {
			final field = value.getFieldInfo();
			if (field != null && field.getName() == "value" && value.getTag() == NameRead) {
				require(field.getOwner().getCanonicalName() == "Main.Parent"
					&& field.getType().getTypeParameterIdentity() != null
					&& value.getType().getSemanticKey() == TyType.fromHintText("String").getSemanticKey(),
					"inherited field lost its owner binder application");
				found = true;
			}
			for (child in value.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				for (body in method.getBody().getStatements())
					for (value in body.getExpressions())
						inspect(value);
		require(found, "no exact inherited field read was published");
		typed.getBackendProjection();
		Sys.println("EXPECTED_ENUM_ARGUMENT:PASS inherited_generic_field");
	}
}
