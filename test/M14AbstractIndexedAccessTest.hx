/** Declared abstract indexing selects exact helpers without exposing backing storage as an indexing permission. */
class M14AbstractIndexedAccessTest {
	static final getter = '@:op([]) private inline function read(i:Int):T return this[i];';
	static final setter = '@:arrayAccess() private inline function write(i:Int,v:T):T return this[i]=v;';
	static final helpers = 'inline function at(i:Int):T return this[i];inline function put(i:Int,v:T):T return this[i]=v;';
	static final staticGetter = '@:op([]) private static inline function read<T>(b:Buffer<T>,i:Int):T return b.at(i);';
	static final staticSetter = '@:op([]) private static inline function write<T>(b:Buffer<T>,i:Int,v:T):T return b.put(i,v);';

	static function main():Void {
		final cases = [
			{
				name: "instance_read",
				members: getter,
				body: 'var b=new Buffer<Int>();var n:Int=b[0];',
				accepted: true,
				toArray: false
			},
			{
				name: "instance_write",
				members: setter,
				body: 'var b=new Buffer();b[0]=7;var n:Buffer<Int>=b;',
				accepted: true,
				toArray: false
			},
			{
				name: "wrong_index",
				members: getter,
				body: 'var b=new Buffer<Int>();var n:Int=b["bad"];',
				accepted: false,
				toArray: false
			},
			{
				name: "wrong_value",
				members: setter,
				body: 'var b=new Buffer<Int>();b[0]="bad";',
				accepted: false,
				toArray: false
			},
			{
				name: "wrong_result",
				members: getter,
				body: 'var b=new Buffer<Int>();var n:String=b[0];',
				accepted: false,
				toArray: false
			},
			{
				name: "getter_only_write",
				members: getter,
				body: 'var b=new Buffer<Int>();b[0]=7;',
				accepted: false,
				toArray: false
			},
			{
				name: "setter_only_read",
				members: setter,
				body: 'var b=new Buffer<Int>();var n:Int=b[0];',
				accepted: false,
				toArray: false
			},
			{
				name: "backing_is_not_permission",
				members: "",
				body: 'var b=new Buffer<Int>();var n:Int=b[0];',
				accepted: false,
				toArray: false
			},
			{
				name: "declared_conversion",
				members: "",
				body: 'var b=new Buffer<Int>();b[0]=7;var n:Int=b[0];',
				accepted: true,
				toArray: true
			},
			{
				name: "conversion_bad_index",
				members: "",
				body: 'var b=new Buffer<Int>();var n:Int=b["bad"];',
				accepted: false,
				toArray: true
			},
			{
				name: "conversion_bad_value",
				members: "",
				body: 'var b=new Buffer<Int>();b[0]="bad";',
				accepted: false,
				toArray: true
			},
			{
				name: "catalog_suppresses_conversion",
				members: '@:op([]) private inline function read(i:String):T return this[0];',
				body: 'var b=new Buffer<Int>();var n:Int=b[0];',
				accepted: false,
				toArray: true
			},
			{
				name: "getter_catalog_suppresses_write",
				members: getter,
				body: 'var b=new Buffer<Int>();b[0]=7;',
				accepted: false,
				toArray: true
			},
			{
				name: "static_generic_read",
				members: staticGetter,
				body: 'var b=new Buffer();var n:Int=b[0];var same:Buffer<Int>=b;',
				accepted: true,
				toArray: false
			},
			{
				name: "static_generic_write",
				members: staticSetter,
				body: 'var b=new Buffer();b[0]=7;var same:Buffer<Int>=b;',
				accepted: true,
				toArray: false
			},
			{
				name: "explicit_dynamic",
				members: getter + setter,
				body: 'var b=new Buffer<Dynamic>();b[0]=7;b[1]="text";',
				accepted: true,
				toArray: false
			},
			{
				name: "expected_result_does_not_reselect",
				members: '@:op([]) private inline function first(i:Int):Int return 1;@:op([]) private inline function second(i:Int):String return "two";',
				body: 'var b=new Buffer<Int>();var n:String=b[0];',
				accepted: false,
				toArray: false
			}
		];
		for (entry in [
			{
				name: "untyped_empty_catalog",
				members: "",
				body: 'var b=new Buffer<Int>();untyped {b[0]=7;var n:Int=b[0];}',
				accepted: true,
				toArray: false
			},
			{
				name: "untyped_conversion_operands",
				members: "",
				body: 'var b=new Buffer<Int>();untyped {b["key"]="text";}',
				accepted: true,
				toArray: true
			},
			{
				name: "untyped_declared_helpers",
				members: getter + setter,
				body: 'var b=new Buffer<Int>();untyped {b[0]=7;var n:Int=b[0];}',
				accepted: true,
				toArray: false
			},
			{
				name: "untyped_declared_bad_index",
				members: getter,
				body: 'var b=new Buffer<Int>();untyped b["bad"];',
				accepted: false,
				toArray: false
			},
			{
				name: "untyped_declared_bad_value",
				members: setter,
				body: 'var b=new Buffer<Int>();untyped {b[0]="text";}',
				accepted: false,
				toArray: false
			},
			{
				name: "untyped_getter_only_write",
				members: getter,
				body: 'var b=new Buffer<Int>();untyped {b[0]=7;}',
				accepted: false,
				toArray: false
			},
			{
				name: "untyped_catalog_suppresses_conversion",
				members: getter,
				body: 'var b=new Buffer<Int>();untyped b["bad"];',
				accepted: false,
				toArray: true
			}
		])
			cases.push(entry);
		for (entry in cases) {
			final source = 'abstract Buffer<T>(Array<T>)' + (entry.toArray ? ' to Array<T>' : '') + '{public inline function new(){this=[];}' + helpers
				+ entry.members + '}class Main{static function main():Void{' + entry.body + '}}';
			check(entry.name, source, entry.accepted);
		}
		check("untyped_enum_value",
			'class Main{static function read(value:EnumValue,key:String):Dynamic return untyped value[key];static function main():Void{}}', true);
		check("typed_enum_value", 'class Main{static function read(value:EnumValue,key:String):Dynamic return value[key];static function main():Void{}}',
			false);
		check("nullable_owner", program(getter + setter, 'var b:Null<Buffer<Int>>=new Buffer();b[0]=7;var n:Int=b[0];'), true);
		check("ordinary_receiver_block", 'class Main{static function main():Void{var values=[0];({var alias=values;alias;})[0]=7;}}', true);
		// These controls observe lexical traversal during typing. Unary lvalue
		// control projection has a separate pre-existing unsupported boundary.
		for (update in ['+=7', '++', '??=7'])
			check("ordinary_receiver_update_"
				+ update,
				'class Main{static function main():Void{var values:Array<Null<Int>>=[0];({var alias=values;alias;})[0]'
				+ update
				+ ';}}', true, false);
		check("parenthesized_indexed_place", program(getter + setter, 'var b=new Buffer<Int>();(b[0])=7;'), false);
		check("conversion_only_update",
			StringTools.replace(program("", 'var b=new Buffer<Int>();b[0]=7;b[0]++;b[0]+=1;'), '(Array<T>)', '(Array<T>) to Array<T>'), true);
		checkSelection();
		checkRevisions();
		checkInlineDependency();
		checkRetainedTerms();
		checkUpdates();
		checkRuntime();
		checkUntypedRuntime();
		TyperStage.typeModule(ParserStage.parse('class Legacy{static function main(){var values=[];values[0]=7;}}', "Legacy.hx"));
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS legacy_no_index");
	}

	/** Untyped raw access remains available, while declared indexers still own effects and assignment results. */
	static function checkUntypedRuntime():Void {
		final source = 'abstract Raw(Array<Int>){public inline function new(){this=[7];}}'
			+ 'abstract Indexed(Array<Int>){public inline function new(){this=[7];}'
			+ '@:arrayAccess public inline function read(i:Int):Int{Main.events+="G";return this[i]+10;}'
			+ '@:arrayAccess public inline function write(i:Int,v:Int):Int{Main.events+="S";this[i]=v+20;return v+30;}}'
			+ 'class Main{public static var events:String="";static function main():Void{'
			+ 'var raw=new Raw();var before:Int=untyped raw[0];untyped {raw[0]=9;}var after:Int=untyped raw[0];trace(before+":"+after);'
			+ 'var indexed=new Indexed();var first:Int=untyped indexed[0];var written:Int=untyped {indexed[0]=9;}var last:Int=untyped indexed[0];'
			+ 'trace(events+":"+first+":"+written+":"+last);}}';
		final expected = "7:9\nGSG:17:39:39\n";
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]) != 0)
			throw "untyped indexed upstream observer did not compile";
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [root + "/upstream.js"],
			expected: path + ":1: 7:9\n" + path + ":1: GSG:17:39:39\n"
		});
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root}), "Main", expected);
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS untyped_runtime");
	}

	static function program(members:String, body:String):String
		return 'abstract Buffer<T>(Array<T>){public inline function new(){this=[];}'
			+ helpers
			+ members
			+ '}class Main{static function main():Void{'
			+ body
			+ '}}';

	/** Upstream acceptance is checked before the same authored source reaches local typing and projection. */
	static function check(name:String, source:String, accepted:Bool, project:Bool = true):Null<TypedModule> {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepted)
			throw "upstream indexed expectation differs: " + name + output;
		var typed:Null<TypedModule> = null;
		try {
			typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
			if (project)
				typed.getBackendProjection();
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			typed = null;
		}
		if ((typed != null) != accepted)
			throw "local indexed expectation differs: " + name;
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS " + name);
		return typed;
	}

	/** Mixed static/instance helpers obey source order, even when a later helper is a better numeric match. */
	static function checkSelection():Void {
		final typed = check("first_applicable",
			program('@:op([]) private static inline function first<T>(b:Buffer<T>,i:Float):String return "first";'
				+ '@:op([]) private inline function second(i:Int):String return "second";',
				'var b=new Buffer<Int>();var value:String=b[0];'),
			true);
		var selected = false;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Call
				&& value.getDeclaration() != null
				&& value.getDeclaration().getOwner().getCanonicalName() == "Main.Buffer") {
				if (value.getDeclaration().getSignature().getName() != "first")
					throw "indexed selection ignored source order";
				selected = true;
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
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
					for (stmt in fn.getBody().getStatements())
						statement(stmt);
		if (!selected)
			throw "indexed selected declaration observer missed its call";
	}

	/** Private indexed helpers are callable API: reordering or changing a signature must invalidate cached callers. */
	static function checkRevisions():Void {
		final first = '@:op([]) private inline function first(i:Float):Int return 1;';
		final second = '@:op([]) private inline function second(i:Int):Int return 2;';
		function revision(members:String):String {
			final root = JsRuntimeFixture.reserveOutput();
			final source = program(members, "");
			return CompilerTypedModuleRevision.fromTypedModule(M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root}))
				.publicInterfaceRevision;
		}
		final original = revision(first + second);
		if (original == revision(second + first) || original == revision(StringTools.replace(first, "i:Float", "i:Int") + second))
			throw "private indexed order/signature absent from public revision";
		if (original != revision(StringTools.replace(first, "return 1", "return 3") + second))
			throw "inline indexed helper body belongs in the implementation revision";
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS private_public_revision");
	}

	/** Private inline indexing consumes the implementation even when a body-only edit preserves its public signature. */
	static function checkInlineDependency():Void {
		var getterFact = "";
		function snapshot(extra:String):CompilerDependencySnapshot {
			final resolved = [
				new ResolvedModule("Main", "Main.hx",
					ParserStage.parse('import Buffer;class Main{static function visit(b:Buffer):Int return b[0];static function main():Void{}}', "Main.hx")),
				new ResolvedModule("Buffer", "Buffer.hx",
					ParserStage.parse('abstract Buffer(Int){public function new(){this=7;}@:op([]) private inline function read(i:Int):Int return this+i'
						+ extra
						+ ';}',
						"Buffer.hx")),
				new ResolvedModule("Unused", "Unused.hx", ParserStage.parse('class Unused{}', "Unused.hx"))
			];
			final index = TyperIndex.build(resolved);
			final declaration = index.getAbstractByFullName("Buffer").getIndexedDeclarations()[0];
			final exact = "declaration:" + declaration.getIdentity().getCanonicalKey();
			if (getterFact.length > 0 && getterFact != exact)
				throw "body-only edit changed indexed getter identity";
			getterFact = exact;
			final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, (_) -> false);
			loader.markResolvedAlready(resolved);
			return CompilerDependencyCollector.collect([
				for (module in resolved)
					TyperStage.typeResolvedModule(module, index, loader, true)
			], index);
		}
		final original = snapshot("");
		final changed = snapshot("+1");
		var found = false;
		for (edge in original.getEdges())
			if (edge.consumerModule == "Main"
				&& edge.providerModule == "Buffer"
				&& edge.kind == CompilerDependencyKind.InlineImplementation
				&& edge.factIdentity == getterFact)
				found = true;
		if (!found)
			throw "indexed call lost its private inline implementation edge";
		if (original.findModule("Buffer").publicInterfaceRevision != changed.findModule("Buffer").publicInterfaceRevision
			|| original.findModule("Buffer").implementationRevision == changed.findModule("Buffer").implementationRevision)
			throw "private inline indexing lost the public/implementation revision distinction";
		final difference = CompilerDependencyInvalidator.compare(original, changed);
		if (!difference.isAffected("Main") || difference.isAffected("Unused"))
			throw "private inline indexed implementation edit invalidated the wrong consumers";
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS private_inline_dependency");
	}

	/** Original receiver children and method binders remain distinct, including a late failed candidate transaction. */
	static function checkRetainedTerms():Void {
		final index = TyperIndex.build([
			new ResolvedModule("Buffer", "Buffer.hx",
				ParserStage.parse('abstract Buffer<T>(Array<T>){public function new();public static function read<T>(b:Buffer<T>,i:Int):T;public static function write<T>(b:Buffer<T>,i:Int,v:T):T;public function late(value:T,tail:Array<Int>):T;}',
					"Buffer.hx"))
		]);
		final owner = index.getAbstractByFullName("Buffer");
		for (name in ["read", "write"]) {
			final signature = owner.staticMethodCandidates(name)[0];
			final declaration = owner.declarationForSignature(signature);
			if (owner.getTypeParameterIds()[0].equals(declaration.getTypeParameterIds()[0]))
				throw "static indexed method borrowed its owner's same-spelled binder";
			final environment = new TyFunctionEnv("static-index-" + name, [], [], TyType.unknown(), TyType.unknown());
			final inference = environment.getInference();
			final allocation:HxExpr = ENew("Buffer", []);
			final original = inference.construct(allocation, TyType.nominal(owner.getIdentity(), []), 1);
			final symbol = environment.declareLocal("buffer", original);
			inference.recordLocal(symbol, inference.sourceTerm(allocation, environment));
			final receiver:HxExpr = EIdent("buffer");
			final arguments:Array<HxExpr> = name == "read" ? [receiver, EInt(0)] : [receiver, EInt(0), EInt(7)];
			final actual = name == "read" ? [original, TyType.fromHintText("Int")] : [original, TyType.fromHintText("Int"), TyType.fromHintText("Int")];
			final occurrence:HxExpr = name == "read" ? EArrayAccess(receiver, arguments[1]) : EBinop("=", EArrayAccess(receiver, arguments[1]), arguments[2]);
			final binding = inference.indexedAccess(occurrence, () -> new TyIndexedAccessBinding(occurrence, receiver, arguments, declaration));
			final copied:HxExpr = name == "read" ? EArrayAccess(receiver, arguments[1]) : EBinop("=", EArrayAccess(receiver, arguments[1]), arguments[2]);
			if (inference.indexedAccess(copied) != null || binding.receiver != receiver || binding.getArguments()[0] != receiver)
				throw "indexed binding lost exact source/receiver-first identities";
			inference.inferDirectCall({
				expression: occurrence,
				declaration: declaration,
				callable: TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType(),
				signature: signature,
				order: TyMethodArgumentOrder.select(signature, arguments, (_, _, _) -> Compatible),
				arguments: arguments,
				actual: actual,
				environment: environment,
				index: index,
				accepts: (expected, supplied) -> TyValueCompatibility.accepts(index, expected, supplied, null)
			});
			if (name == "read" && !inference.constrain([occurrence], [TyType.fromHintText("Int")], environment, index))
				throw "static indexed read lost its retained result child";
			inference.seal(environment.getLocals());
			if (inference.expressionType(allocation, original, environment).getTypeArguments()[0].getSemanticKey() != "primitive:Int"
				|| inference.directCallType(occurrence, declaration).getFunctionReturn().getSemanticKey() != "primitive:Int"
				|| inference.directCallType(copied, declaration) != null
				|| inference.indexedAccess(occurrence) != binding)
				throw "static indexed selection solved a copy instead of the original receiver/result";
		}
		final environment = new TyFunctionEnv("late-index-probe", [], [], TyType.unknown(), TyType.unknown());
		final inference = environment.getInference();
		final receiver:HxExpr = ENew("Buffer", []);
		final original = inference.construct(receiver, TyType.nominal(owner.getIdentity(), []), 1);
		final tail:HxExpr = EArrayDecl([]);
		final stringArray = TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("String")]);
		inference.contextualCollection(tail, stringArray);
		final signature = owner.instanceMethodCandidates("late")[0];
		final arguments:Array<HxExpr> = [EInt(7), tail];
		final trial = environment.copyForInference();
		final order = TyMethodArgumentOrder.select(signature, arguments, (_, _, _) -> Compatible);
		if (!trial.getInference()
			.constrainMember(receiver, owner, signature, [TyType.fromHintText("Int"), TyType.unknown()], trial, index, {expressions: arguments, order: order}))
			throw "late indexed probe did not stage its receiver constraint";
		if (trial.getInference().constrain(arguments, [
			TyType.fromHintText("Int"),
			TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Int")])
		], trial, index))
			throw "late indexed probe accepted its incompatible retained child";
		if (!inference.expressionType(receiver, original, environment).hasUnknownComponent()
			|| inference.expressionType(tail, stringArray, environment).getTypeArguments()[0].getSemanticKey() != "primitive:String")
			throw "late rejected indexed probe leaked into the parent";
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS retained_static_identity_and_late_rollback");
	}

	/** Update forms remain a diagnosed follow-up rather than silently becoming a raw carrier update. */
	static function checkUpdates():Void {
		for (update in ['b[0]+=1', 'b[0]++', '--b[0]']) {
			final source = program(getter + setter, 'var b=new Buffer<Int>();' + update + ';');
			final root = JsRuntimeFixture.reserveOutput();
			try {
				M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
				throw "abstract indexed update escaped its unsupported boundary";
			} catch (error:TyperError) {
				if (error.message.indexOf("haxe_ocaml-rgmu4") < 0)
					throw error;
			}
		}
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS deferred_updates");
	}

	/** Execute setter results and receiver/index/value effects, including every abrupt-completion boundary. */
	static function checkRuntime():Void {
		final root = "test/fixtures/abstract_indexed_access";
		final path = root + "/Main.hx";
		final source = sys.io.File.getContent(path);
		final expected = "ok:RIVS:stored\nreceiver:R:caught\nindex:RI:caught\nvalue:RIV:caught\nsetter:RIVS:caught\nread:RIG:11\n";
		final output = JsRuntimeFixture.reserveOutput();
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		final messages = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw messages;
		final lines = source.split("\n");
		var attemptLine = 0;
		var readLine = 0;
		for (i in 0...lines.length) {
			if (lines[i].indexOf("trace(stage") >= 0)
				attemptLine = i + 1;
			if (lines[i].indexOf('trace("read:') >= 0)
				readLine = i + 1;
		}
		if (attemptLine == 0 || readLine == 0)
			throw "upstream indexed trace positions are absent";
		final expectedLines = expected.split("\n");
		expectedLines.pop();
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [output + "/upstream.js"],
			expected: [
				for (i in 0...expectedLines.length)
					path + ":" + (i == 5 ? readLine : attemptLine) + ": " + expectedLines[i]
			].join("\n") + "\n"
		});
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root}), "Main", expected);
		Sys.println("ABSTRACT_INDEXED_ACCESS:PASS runtime");
	}
}
