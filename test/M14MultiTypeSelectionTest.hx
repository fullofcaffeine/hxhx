import sys.io.File;

/** Selected conversions retain exact ownership, binder substitution, declaration order, and storage types. */
class M14MultiTypeSelectionTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final source = File.getContent("test/fixtures/multitype_specialization/Main.hx");
		final alternate = ' @:to static inline function alternate<T:String>(unused:Storage<T>):TextStorage return new TextStorage();\n';
		final cases = [
			{
				name: "text",
				source: source,
				key: "String",
				method: "text",
				storage: "Main.TextStorage"
			},
			{
				name: "number",
				source: source,
				key: "Int",
				method: "number",
				storage: "Main.NumberStorage"
			},
			{
				name: "unsupported",
				source: source,
				key: "Float",
				method: "",
				storage: ""
			},
			{
				name: "unknown",
				source: source,
				key: "",
				method: "",
				storage: ""
			},
			{
				name: "bare",
				source: StringTools.replace(source, "@:multiType(@:followWithAbstracts T)", "@:multiType"),
				key: "String",
				method: "text",
				storage: "Main.TextStorage"
			},
			{
				name: "ignored_name",
				source: StringTools.replace(source, "@:multiType(@:followWithAbstracts T)", "@:multiType(Missing)"),
				key: "String",
				method: "text",
				storage: "Main.TextStorage"
			},
			{
				name: "first",
				source: StringTools.replace(source, "@:to static inline function text", alternate + "@:to static inline function text"),
				key: "String",
				method: "alternate",
				storage: "Main.TextStorage"
			},
			{
				name: "later",
				source: StringTools.replace(source, "@:to static inline function number", alternate + "@:to static inline function number"),
				key: "String",
				method: "text",
				storage: "Main.TextStorage"
			}
		];
		for (item in cases) {
			final index = indexSource(item.source);
			final owner = index.getAbstractByFullName("Main.Choice");
			require(owner != null && owner.getMultiTypePolicy() != null, "missing declared specialization policy");
			final supplied = item.key == "" ? TyType.unknown() : TyType.fromHintText(item.key);
			final type = TyType.nominal(owner.getIdentity(), [supplied]);
			final before = owner.getDeclarations().map(value -> value.getIdentity().getCanonicalKey()).join("|");
			switch TyMultiTypeSelection.select(index, type) {
				case Ordinary:
					throw "declared multi-type became ordinary";
				case Rejected(_):
					require(item.method == "", "valid provider rejected: " + item.name);
				case Selected(plan):
					require(item.method != "", "unsupported key selected a provider");
					require(plan.getDeclaration().getSignature().getName() == item.method, "wrong conversion: " + item.name);
					require(plan.getStorageType().getNominalIdentity().getCanonicalName() == item.storage, "wrong storage type");
					require(plan.getCallableType().getFunctionArguments()[0].getTypeArguments()[0].getSemanticKey() == supplied.getSemanticKey(),
						"method binder was not specialized");
					require(owner.getDeclarations().indexOf(plan.getDeclaration()) >= 0, "conversion identity was copied");
					plan.assertCurrent(index, type);
					final construction = new TypedMultiTypeConstruction(plan, index, [], []);
					final applied = construction.apply([], type, null);
					require(applied.getTag() == Cast && applied.getExpressions()[0].getDeclaration() == plan.getDeclaration(),
						"construction lost its exact selected factory");
					reject(() -> construction.apply([], TyType.nominal(owner.getIdentity(), [TyType.fromHintText("Bool")]), null),
						"multi-type construction belongs to another applied result");
					reject(() -> construction.apply([TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), null)], type, null),
						"call argument binding has a stale signature or operand count");
					reject(() -> plan.assertCurrent(indexSource(item.source), type));
					reject(() -> plan.assertCurrent(index, TyType.nominal(owner.getIdentity(), [TyType.fromHintText("Bool")])));
			}
			require(before == owner.getDeclarations().map(value -> value.getIdentity().getCanonicalKey()).join("|"),
				"selection mutated declaration signatures");
			final policy = owner.getMultiTypePolicy();
			final count = policy.getParameters().length;
			policy.getParameters().pop();
			require(policy.getParameters().length == count, "policy exposed a mutable parameter array");
			Sys.println("MULTITYPE_SELECTION:" + item.name + ":PASS");
		}
		for (follow in [true, false]) {
			final prefix = "abstract TextKey(String) {}\n";
			final index = indexSource(prefix + (follow ? source : StringTools.replace(source, "@:followWithAbstracts T", "T")));
			final owner = index.getAbstractByFullName("Main.Choice");
			final key = TyType.nominal(index.getAbstractByFullName("Main.TextKey").getIdentity(), []);
			final type = TyType.nominal(owner.getIdentity(), [key]);
			switch TyMultiTypeSelection.select(index, type) {
				case Selected(plan):
					require(follow && plan.getDeclaration().getSignature().getName() == "text", "opaque abstract selected String storage");
				case Rejected(_):
					require(!follow, "explicit abstract following was rejected");
				case Ordinary:
					throw "multi-type declaration lost";
			}
			require(type.getTypeArguments()[0].getSemanticKey() == key.getSemanticKey(), "following changed the source type argument");
		}
		final ordinary = indexSource(StringTools.replace(source, "@:multiType(@:followWithAbstracts T)", "@:multiTypeDecoy(T)"));
		require(TyMultiTypeSelection.select(ordinary,
			TyType.nominal(ordinary.getAbstractByFullName("Main.Choice").getIdentity(), [TyType.fromHintText("String")]))
			.match(Ordinary),
			"unrelated metadata activated specialization");
		Sys.println("MULTITYPE_SELECTION:PASS");
	}

	static function indexSource(source:String):TyperIndex {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperIndex.build([resolved]);
	}

	static function reject(action:Void->Void, expected:String = "multi-type selection belongs to another provider or type application"):Void {
		var failed = false;
		try
			action()
		catch (error:haxe.Exception) {
			require(error.message == expected, "unexpected ownership failure: " + error.message);
			failed = true;
		}
		require(failed, "foreign selection was accepted");
	}
}
