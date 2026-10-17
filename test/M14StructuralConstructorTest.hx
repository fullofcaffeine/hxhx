import sys.io.File;

/** Compare explicit and inferred structural assignments with upstream, then execute inherited and context-only constructions. */
class M14StructuralConstructorTest {
	static function type(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function main():Void {
		final cases = [
			{
				name: "method",
				requirement: "function get():T;",
				member: "public function get():T return value;",
				initialize: "",
				accepted: true
			},
			{
				name: "missing_method",
				requirement: "function get():T;",
				member: "",
				initialize: "",
				accepted: false
			},
			{
				name: "wrong_result",
				requirement: "function get():T;",
				member: "public function get():Int return 1;",
				initialize: "",
				accepted: false
			},
			{
				name: "private_method",
				requirement: "function get():T;",
				member: "private function get():T return value;",
				initialize: "",
				accepted: false
			},
			{
				name: "extra_optional",
				requirement: "function get():T;",
				member: "public function get(?unused:Int):T return value;",
				initialize: "",
				accepted: false
			},
			{
				name: "field",
				requirement: "var item:T;",
				member: "public var item:T;",
				initialize: "item=value;",
				accepted: true
			},
			{
				name: "private_field",
				requirement: "var item:T;",
				member: "private var item:T;",
				initialize: "item=value;",
				accepted: false
			},
			{
				name: "readonly_field",
				requirement: "var item:T;",
				member: "public final item:T;",
				initialize: "item=value;",
				accepted: false
			},
			{
				name: "optional_absent",
				requirement: "var ?item:T;",
				member: "",
				initialize: "",
				accepted: false
			},
			{
				name: "function_field",
				requirement: "var get:()->T;",
				member: "public function get():T return value;",
				initialize: "",
				accepted: false
			}
		];
		for (entry in cases)
			for (explicit in [false, true]) {
				final name = entry.name + (explicit ? "_explicit" : "_inferred");
				final source = "typedef Snapshot<T>={"
					+ entry.requirement
					+ "}\nclass Cell<T>{var value:T; public function new(value:T){this.value=value;"
					+ entry.initialize
					+ "}"
					+ entry.member
					+ "}\nclass Main{static function main():Void{var result:Snapshot<String>=new Cell"
					+ (explicit ? "<String>" : "")
					+ '("value");}}';
				upstream(name, source, entry.accepted, "");
				var accepted = true;
				try {
					type(source);
				} catch (error:TyperError) {
					accepted = false;
				}
				if (accepted != entry.accepted)
					throw "structural constructor acceptance differs: " + name;
			}
		final source = File.getContent("test/fixtures/structural_constructor/Main.hx");
		upstream("inherited", source, true, "ok\ntrue\n");
		final typed = type(source);
		var allocations = 0;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				final actual = node.getType();
				if (actual.getNominalIdentity() == null
					|| actual.getTypeArguments().length != 1
					|| actual.getTypeArguments()[0].getSemanticKey() != "primitive:String")
					throw "structural context replaced or failed to solve the concrete allocation: " + actual.getSemanticKey();
				allocations++;
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (allocations != 2)
			throw "structural constructor fixture lost an allocation";
		JsRuntimeFixture.assertRuntime(typed, "Main", "ok\ntrue\n");
		rollback(source);
		Sys.println("STRUCTURAL_CONSTRUCTOR:PASS cases=20 inherited=2 rollback=1");
	}

	/** A failed later member cannot publish an earlier member's tentative generic solution. */
	static function rollback(source:String):Void {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final solver = new TyInferenceSolver("structural-rollback");
		final parameter = solver.fresh();
		final expected = TyType.declaredAnonymous([
			method("read", TyType.anonymous(["item"], [TyType.fromHintText("String")])),
			method("zzzMissing", TyType.fromHintText("Bool"))
		]);
		final candidate = solver.fork();
		if (TyStructuralConstraint.constrain(index, candidate, Nominal(new TyNominalTypeId("Main.Child"), [parameter]), expected))
			throw "missing structural member was accepted";
		if (candidate.preview(parameter).getSemanticKey() != "primitive:String")
			throw "rollback test did not reach the first member's tentative solution";
		if (!solver.preview(parameter).isUnknown())
			throw "failed structural candidate leaked its solution";
		if (!solver.constrain(parameter, TyInferenceSolver.fromType(TyType.fromHintText("Int"))))
			throw "failed structural candidate froze its variable";
	}

	static function method(name:String, result:TyType):TyAnonymousField {
		return {
			name: name,
			type: TyType.functionType([], result),
			kind: Method([]),
			isOptional: false,
			visibility: Public,
			metadata: [],
			position: HxPos.unknown()
		};
	}

	/** Pin the independent compiler and distinguish expected rejection from timeout or process failure. */
	static function upstream(name:String, source:String, accepted:Bool, expected:String):Void {
		final root = ".tmp/structural_constructor_contract/" + name;
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (accepted ? code != 0 || output != expected : code != 1 || errors.length == 0)
			throw "upstream structural contract differs for " + name + ": " + output + errors;
	}
}
