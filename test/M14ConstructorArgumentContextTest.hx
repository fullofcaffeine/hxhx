import sys.io.File;

/** Constructor parameters guide original operands before inference, while exact owners and later selection stay authoritative. */
class M14ConstructorArgumentContextTest {
	static final providers = [
		{path: "Access.hx", source: 'enum Access{Public;Named(value:String);}'},
		{path: "Other.hx", source: 'enum Other{Public;}'},
		{path: "Choice.hx", source: 'enum Choice<T>{None;Some(value:T);}'}
	];

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function write(name:String, source:String):String {
		final root = ".tmp/constructor-argument-context-" + name;
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		for (provider in providers)
			File.saveContent(root + "/" + provider.path, provider.source);
		return root;
	}

	static function upstream(root:String, accepted:Bool):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		require((status == 0) == accepted, "upstream constructor contract differs: " + root + output);
	}

	static function walk(typed:TypedModule, visit:TypedExpr->Void):Void {
		function expression(value:TypedExpr):Void {
			visit(value);
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
	}

	/** Inspect the selected constructor and original enum occurrence, including inherited owner specialization. */
	static function check(name:String, source:String, accepted:Bool, ?enumOwner:String, ?ownerArgument:String):Void {
		final root = write(name, source);
		upstream(root, accepted);
		var typed:Null<TypedModule> = null;
		try {
			typed = M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			require(error.message.indexOf("compatib") >= 0
				|| error.message.indexOf("conflict") >= 0
				|| error.message.indexOf("should be") >= 0,
				"unrelated constructor rejection: "
				+ name
				+ ": "
				+ error.message);
		}
		require((typed != null) == accepted, "local constructor contract differs: " + name);
		if (typed != null) {
			var constructors = 0;
			var enums = 0;
			if (name == "method_binder")
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Box"
							&& HxFunctionDecl.getName(method.getSourceDeclaration()) == "new") {
							final parameter = method.getEnvironment().getParams()[0].getType();
							final identity = TyTypeParameterId.method(new TyNominalTypeId("Main.Box"), false, "new", 0, 0, "T");
							require(parameter.getFunctionArguments()[0].getTypeParameterIdentity().equals(identity)
								&& parameter.getFunctionReturn().getTypeParameterIdentity().equals(identity),
								"constructor method binder identity changed");
						}
			walk(typed, value -> {
				if (value.getTag() == NewValue) {
					final application = value.getConstructorApplication();
					// Generic constructor-method publication is a separate existing gap;
					// this control checks that context does not make its open binder rigid.
					if (name == "method_binder") {
						require(value.getExpressions()[0].getType().getSemanticKey() == "function:(primitive:Int)->primitive:Int",
							"generic constructor callback context became rigid");
						constructors++;
						return;
					}
					require(application != null,
						"constructor lost its checked application: "
						+ name
						+ ": "
						+ value.getType().getSemanticKey()
						+ ": "
						+ value.getExpressions().map(child -> child.getType().getSemanticKey()).join(";"));
					final declaration = application.getDeclaration();
					require(declaration.getOwner().getCanonicalName() == "Main.Box"
						&& declaration.getSignature().getName() == "new"
						&& !declaration.getIsStatic(),
						"constructor declaration changed owner");
					require(application.getOwnerType().getNominalIdentity().equals(declaration.getOwner()), "applied constructor owner differs");
					if (ownerArgument != null) {
						final bindings = application.getOwnerArguments();
						require(bindings.length == 1 && bindings[0].argument.getSemanticKey() == ownerArgument,
							"constructor lost exact owner argument: " + name);
						require(bindings[0].parameter.equals(TyTypeParameterId.nominal(declaration.getOwner(), 0, "T")), "owner binder identity changed");
					}
					if (name == "owner_caller")
						require(application.getOwnerArguments()[0].argument.getTypeParameterIdentity()
						.equals(TyTypeParameterId.method(new TyNominalTypeId("Main"), true, "make", 0, 0, "T")),
							"caller binder identity changed");
					constructors++;
				}
				final field = value.getFieldInfo();
				if (field != null && field.getOwner().getCanonicalName() == enumOwner) {
					require(field.getCanonicalKey() == enumOwner + "#static#" + field.getName(), "enum field identity changed");
					require(TyAliasExpansion.revealNonNullable(value.getType()).getNominalIdentity().equals(field.getOwner()),
						"enum application changed owner");
					enums++;
				}
				if (value.getTag() == Call
					&& value.getDeclaration() != null
					&& value.getDeclaration().getSignature().getName() == "Named") {
					require(value.getDeclaration().getOwner().getCanonicalName() == "Access", "payload selected wrong enum");
					enums++;
				}
			});
			require(constructors > 0, "no original construction observed: " + name);
			if (enumOwner != null)
				require(enums > 0, "no original enum operand observed: " + name);
			typed.getBackendProjection();
		}
		Sys.println("CONSTRUCTOR_ARGUMENT_CONTEXT:PASS " + name);
	}

	/** Different overload rows, rest operands, and omitted positions cannot supply one positional expected type. */
	static function checkAdmission():Void {
		final source = 'class Box{@:overload(function(access:Other,values:Array<Int>):Void{})public function new(access:Access,values:Array<String>){}}'
			+ 'class Rest{public function new(access:Access,...values:String){}}class Main{static function main():Void{}}';
		final modules = [new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"))].concat([
			for (provider in providers)
				new ResolvedModule(provider.path.substr(0, provider.path.length - 3), provider.path, ParserStage.parse(provider.source, provider.path))
		]);
		final index = TyperIndex.build(modules);
		final owner = index.getByFullName("Main.Box");
		final signatures = owner.instanceMethodCandidates("new");
		require(signatures.length == 2, "authored constructor overload inventory changed");
		final contexts = TyCallArgumentContext.shared(signatures, 2,
			signatures.map(signature -> owner.declarationForSignature(signature).getTypeParameterIds()), index);
		require(contexts[0] == null && contexts[1] == null, "differing constructor rows acquired guessed context");
		require(TyCallArgumentContext.shared(signatures, 1, null, index)[0] == null, "omitted constructor position acquired context");
		require(TyCallArgumentContext.shared(index.getByFullName("Main.Rest").instanceMethodCandidates("new"), 2, null, index)[0] == null,
			"rest constructor acquired fixed positional context");
		Sys.println("CONSTRUCTOR_ARGUMENT_CONTEXT:PASS admission");
	}

	/** Invalid applications have a separate baseline validation gap; they must gain no early enum context here. */
	static function checkNoContext():Void {
		for (entry in [
			{name: "missing_operand", declaration: 'class Box{public function new(access:Access,values:Array<String>){}}', allocation: 'new Box(Public)'},
			{name: "excess_operand", declaration: 'class Box{public function new(access:Access,values:Array<String>){}}', allocation: 'new Box(Public,[],7)'},
			{name: "partial", declaration: 'class Box<A,B>{public function new(access:Access,values:Array<String>){}}', allocation: 'new Box<Int>(Public,[])'},
			{
				name: "excess_type",
				declaration: 'class Box<T>{public function new(access:Access,values:Array<String>){}}',
				allocation: 'new Box<Int,String>(Public,[])'
			},
			{name: "empty_type", declaration: 'class Box<T>{public function new(access:Access,values:Array<String>){}}', allocation: 'new Box<>(Public,[])'},
			{
				name: "alias_missing",
				declaration: 'class Box<T>{public function new(access:Access,values:Array<String>){}}typedef Alias=Box;',
				allocation: 'new Alias(Public,[])'
			}
		]) {
			final source = entry.declaration + 'class Main{static function main():Void{' + entry.allocation + ';}}';
			final root = write(entry.name, source);
			upstream(root, false);
			final path = root + "/Main.hx";
			final loaded = @:privateAccess M14Stage3RuntimeFixture.loadContext({source: source, path: path, root: root});
			final context = new TyperContext(loaded.index, path, "Main", "", [], "Main", loaded.loader);
			final scope = new TyFunctionEnv("main", [], [], TyType.fromHintText("Void"), TyType.fromHintText("Void"), "Main#static#main", null, false, 0, true);
			var original = 0;
			for (owner in HxModuleDecl.getClasses(ResolvedModule.getParsed(loaded.main).getDecl()))
				for (method in HxClassDecl.getFunctions(owner))
					TypedBackendSourceWalk.functionDeclaration(method, expression -> switch expression {
						case ENew(written, arguments):
							final type = @:privateAccess TyperStage.typeFromHintInContext(written, context, scope);
							final contexts = @:privateAccess TyperStage.constructorArgumentContexts(written, type, arguments, scope, context);
							require(contexts.length == arguments.length && contexts.filter(type -> type != null).length == 0,
								"invalid original application acquired early context");
							original++;
						case _:
					}, _ -> {});
			require(original == 1, "original invalid construction was not observed");
			var typed:Null<TypedModule> = null;
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
			} catch (error:TyperError) {
				// Existing later checks may already reject the invalid source. The
				// admission assertion above must not require invalid source acceptance.
			}
			var found = false;
			if (typed != null)
				walk(typed, value -> {
					if (value.getTag() == NewValue) {
						require(value.getConstructorApplication() == null,
							"invalid application gained a constructor proof: "
							+ entry.name
							+ ": "
							+ value.getTexts().join(";")
							+ ": "
							+ value.getExpressions().map(child -> child.getType().getSemanticKey()).join(";"));
						final argument = value.getExpressions()[0];
						require(argument.getFieldInfo() == null && argument.getType().getSemanticKey() == "primitive:String",
							"invalid application gained synthesized owner/enum context");
						found = true;
					}
				});
			require(typed == null || found, "invalid application boundary was not observed");
			Sys.println("CONSTRUCTOR_ARGUMENT_CONTEXT:PASS no_context_" + entry.name);
		}
	}

	/** Observe original argument order, one visit to argument blocks, and payloads from two distinct enum owners. */
	static function checkRuntime():Void {
		final source = 'class Box{public function new(access:Access,values:Array<String>){Main.effects+="c";switch(access){case Public:trace("public");case Named(value):trace(value);}trace(values[0]);}}'
			+ 'class OtherBox{public function new(access:Other){Main.effects+="o";switch(access){case Public:trace("other");}}}'
			+ 'class Main{public static var effects:String="";static function text():String{effects+="v";return "payload";}'
			+ 'static function main():Void{new Box(Named(text()),{var marker="item";effects+="a";[marker];});new OtherBox(Public);trace(effects);}}';
		final root = write("runtime", source);
		final expected = "payload\nitem\nother\nvaco\n";
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final errors = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		require(status == 0, "upstream runtime generation failed: " + errors);
		final node = new sys.io.Process("node", [root + "/upstream.js"]);
		final output = node.stdout.readAll().toString();
		final stderr = node.stderr.readAll().toString();
		final exit = node.exitCode();
		node.close();
		require(exit == 0
			&& stderr == ""
			&& output == expected.split("\n")
				.filter(line -> line != "")
				.map(line -> root + "/Main.hx:1: " + line + "\n")
				.join(""),
			"upstream runtime differs: "
			+ output
			+ stderr);
		final modules = [
			new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"))
		].concat([
			for (provider in providers.slice(0, 2))
				new ResolvedModule(provider.path.substr(0, provider.path.length - 3), root + "/" + provider.path,
					ParserStage.parse(provider.source, root + "/" + provider.path))
		]);
		final index = TyperIndex.build(modules);
		JsRuntimeFixture.assertProgramRuntime(new MacroExpandedProgram([for (module in modules) TyperStage.typeResolvedModule(module, index)], false), "Main",
			expected);
		Sys.println("CONSTRUCTOR_ARGUMENT_CONTEXT:PASS generated_runtime");
	}

	static function main():Void {
		checkAdmission();
		final box = 'class Box{public function new(access:Access,values:Array<String>){}}';
		for (entry in [
			{name: "implicit", body: 'new Box(Public,[]);'},
			{name: "payload", body: 'new Box(Named("ok"),[]);'},
			{name: "qualified", body: 'new Box(Access.Public,[]);'},
			{name: "block", body: 'new Box(Public,{var marker="ok";[marker];});'},
			{name: "local_body", body: 'function make():Void{new Box(Public,[]);}make();'}
		])
			check(entry.name, box + 'class Main{static function main():Void{' + entry.body + '}}', true, "Access");
		for (entry in [
			{name: "wrong_owner", body: 'new Box(Other.Public,[]);'},
			{name: "wrong_string", body: 'new Box("wrong",[]);'}
		])
			check(entry.name, box + 'class Main{static function main():Void{' + entry.body + '}}', false);
		check("nullable_alias",
			'typedef Selected=Null<Access>;class Box{public function new(access:Selected,values:Array<String>){}}class Main{static function main():Void{new Box(Public,[]);}}',
			true, "Access");
		check("owner_omitted",
			'class Box<T>{public function new(access:Access,values:Array<T>){}}class Main{static function main():Void{var box:Box<Int>=new Box(Public,[7]);}}',
			true, "Access", "primitive:Int");
		final generic = 'class Box<T>{public function new(choice:Choice<T>,values:Array<T>){}}';
		check("owner_written", generic + 'class Main{static function main():Void{new Box<String>(None,[]);}}', true, "Choice", "primitive:String");
		check("owner_caller",
			generic + 'class Main{static function make<T>(value:T):Box<T>{return new Box<T>(None,[value]);}static function main():Void{make("ok");}}', true,
			"Choice");
		check("method_binder",
			'class Box{public function new<T>(callback:T->T){}}class Main{static function main():Void{new Box(function(value:Int):Int{return value+1;});}}',
			true);
		check("alias", generic + 'typedef Alias=Box<String>;class Main{static function main():Void{new Alias(None,[]);}}', true, "Choice", "primitive:String");
		check("default_alias", generic + 'typedef Alias<T=String>=Box<T>;class Main{static function main():Void{new Alias(None,[]);}}', true, "Choice",
			"primitive:String");
		check("inherited", generic + 'class Child extends Box<String>{}class Main{static function main():Void{new Child(None,[]);}}', true, "Choice",
			"primitive:String");
		checkNoContext();
		checkRuntime();
	}
}
