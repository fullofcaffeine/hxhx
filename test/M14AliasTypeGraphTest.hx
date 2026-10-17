/**
	Exercise the recursive representation independently of source resolution.
	The expected payload progression is Int, Array<Int>, Array<Array<Int>>.
	A finite definition must preserve that progression without expanding its
	whole future graph or hiding changed definitions behind a name-only key.
 */
class M14AliasTypeGraphTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function rejects(action:Void->Void, expected:String):Void {
		var message = "";
		try {
			action();
		} catch (error:String) {
			message = error;
		}
		require(message.indexOf(expected) >= 0, "expected " + expected + ", got " + message);
	}

	static function definition(name:String, ?parameter:String):TyAliasDefinition {
		final source = "typedef Node" + (parameter == null ? "" : "<" + parameter + ">") + " = {};";
		final parsed = ParserStage.parse(source, "Types.hx").getDecl();
		return new TyAliasDefinition(new TyTypeDeclaration({
			canonicalName: name,
			visibility: Public,
			kind: Alias(HxModuleDecl.getTypedefs(parsed)[0]),
			context: {
				packagePath: "",
				modulePath: "Types",
				directives: [],
				filePath: "Types.hx",
				position: HxPos.unknown(),
				parameters: []
			}
		}));
	}

	static function array(element:TyType):TyType
		return TyType.nominal(new TyNominalTypeId("Array"), [element]);

	static function growing(?name:String = "Types.Tree", ?payload:String):TyAliasDefinition {
		final tree = definition(name, "T");
		final parameter = TyType.typeParameter(tree.getDeclaration().getParameterIds()[0]);
		tree.bind(TyType.anonymous(["value", "next"], [
			payload == null ? parameter : TyType.fromHintText(payload),
			TyType.aliasApplication(tree, [array(parameter)])
		]));
		TyAliasDefinition.seal([tree]);
		return tree;
	}

	static function field(type:TyType, name:String):TyType {
		final selected = TyStructuralFieldRead.resolve(type, name);
		if (selected == null)
			throw "missing recursive field " + name;
		return selected;
	}

	static function main():Void {
		construction();
		progression();
		keysAndScopes();
		componentScans();
		productiveExpansion();
		sharedGraphKeys();
		nullableReceiver();
		literalContext();
		nestedAliasViews();
		Sys.println("ALIAS_TYPE_GRAPH:PASS");
	}

	/** Unfolding one array element cannot change the mutable field's exact semantic type. */
	static function nestedAliasViews():Void {
		final alias = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		final expected = TyType.anonymous(["items"], [array(alias)]);
		final expanded = TyType.anonymous(["items"], [array(TyAliasExpansion.reveal(alias))]);
		require(TyStructuralArgument.compatibility(null, expected, expanded) == Compatible, "recursive array element expansion changed compatibility");
		final wrong = TyType.anonymous(["items"], [array(TyType.aliasApplication(growing(), [TyType.fromHintText("String")]))]);
		require(TyStructuralArgument.compatibility(null, expected, wrong) == Incompatible, "recursive array comparison hid different payloads");
		final other = TyType.anonymous(["items"], [TyType.nominal(new TyNominalTypeId("other.Array"), [alias])]);
		require(TyStructuralArgument.compatibility(null, expected, other) == Incompatible, "recursive array comparison hid a different nominal owner");
	}

	/** A literal at a recursive edge must receive the same required fields as the root. */
	static function literalContext():Void {
		final expected = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		final fields = TypedAnonymousLiteral.fieldTypes(["value", "next"], expected);
		require(fields[0].getSemanticKey() == "primitive:Int", "recursive literal lost its value context");
		require(fields[1].getAliasDefinition() != null, "recursive literal lost its next application");
		var rejected = false;
		try {
			TypedAnonymousLiteral.infer({
				names: [],
				values: [],
				expected: expected,
				typeExpression: (_, _) -> throw "empty literal cannot type a child",
				accepts: (_, _) -> true,
				filePath: "Literal.hx",
				position: HxPos.unknown()
			});
		} catch (error:TyperError) {
			rejected = error.message.indexOf("missing object literal field") >= 0;
		}
		require(rejected, "recursive literal omitted a required field");
	}

	/** Nullable recursion must not make the field-read adapter restart forever. */
	static function nullableReceiver():Void {
		final record = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		require(TyStructuralFieldRead.resolve(TyType.nullable(record), "value").getSemanticKey() == "primitive:Int", "nullable alias lost its field type");
		final cycle = definition("Types.NullableCycle");
		final use = TyType.aliasApplication(cycle, []);
		cycle.bind(TyType.nullable(use));
		TyAliasDefinition.seal([cycle]);
		var rejected = false;
		try {
			TyStructuralFieldRead.resolve(use, "value");
		} catch (error:TyperError) {
			rejected = error.message.indexOf("Recursive typedef is not allowed") >= 0;
		}
		require(rejected, "nullable cycle escaped the receiver termination guard");
	}

	/** A shared definition graph must not serialize an exponentially expanded tree. */
	static function sharedGraphKeys():Void {
		var child = definition("Types.Leaf");
		child.bind(TyType.fromHintText("Int"));
		for (index in 0...24) {
			final parent = definition("Types.Level" + index);
			final use = TyType.aliasApplication(child, []);
			parent.bind(TyType.anonymous(["left", "right"], [use, use]));
			child = parent;
		}
		TyAliasDefinition.seal([child]);
		final key = TyType.aliasApplication(child, []).getSemanticKey();
		require(key.length < 10000, "key expanded the shared definition graph as a tree");
		require(key.indexOf("primitive:Int") >= 0 && key.indexOf("Types.Level23") >= 0, "key truncated the definition graph");
	}

	/** Alias nesting alone is neither a cycle nor proof that recursion is productive. */
	static function productiveExpansion():Void {
		final identity = definition("Types.Id", "T");
		identity.bind(TyType.typeParameter(identity.getDeclaration().getParameterIds()[0]));
		TyAliasDefinition.seal([identity]);
		final nested = TyType.aliasApplication(identity, [TyType.aliasApplication(identity, [TyType.fromHintText("Int")])]);
		require(TyAliasExpansion.reveal(nested).getSemanticKey() == "primitive:Int", "nested identity applications were treated as a cycle");
		final discarded = definition("Types.Drop", "T");
		discarded.bind(TyType.fromHintText("Int"));
		final unused = definition("Types.Unused");
		final unusedUse = TyType.aliasApplication(unused, []);
		unused.bind(TyType.aliasApplication(discarded, [unusedUse]));
		TyAliasDefinition.seal([unused]);
		require(TyAliasExpansion.reveal(unusedUse).getSemanticKey() == "primitive:Int", "unused recursive argument was evaluated");
		final direct = definition("Types.Direct");
		direct.bind(TyType.aliasApplication(direct, []));
		final indirect = definition("Types.Indirect");
		indirect.bind(TyType.aliasApplication(identity, [TyType.aliasApplication(indirect, [])]));
		final growingCycle = definition("Types.Growing", "T");
		growingCycle.bind(TyType.aliasApplication(growingCycle, [array(TyType.typeParameter(growingCycle.getDeclaration().getParameterIds()[0]))]));
		final left = definition("Types.LeftCycle");
		final right = definition("Types.RightCycle");
		left.bind(TyType.aliasApplication(right, []));
		right.bind(TyType.aliasApplication(left, []));
		TyAliasDefinition.seal([direct, indirect, growingCycle, left]);
		for (input in [
			TyType.aliasApplication(direct, []),
			TyType.aliasApplication(indirect, []),
			TyType.aliasApplication(growingCycle, [TyType.fromHintText("Int")]),
			TyType.aliasApplication(left, [])
		]) {
			var rejected = false;
			try {
				TyAliasExpansion.reveal(input);
			} catch (error:TyperError) {
				rejected = error.message.indexOf("Recursive typedef is not allowed") >= 0 && error.filePath == "Types.hx";
			}
			require(rejected, "an alias-only cycle escaped explicit expansion");
		}
	}

	static function construction():Void {
		final left = definition("Types.Left");
		final right = definition("Types.Right");
		final use = TyType.aliasApplication(left, []);
		left.bind(TyType.anonymous(["next"], [TyType.aliasApplication(right, [])]));
		rejects(() -> use.getSemanticKey(), "not sealed");
		rejects(() -> TyAliasDefinition.seal([left]), "has no body");
		rejects(() -> left.getBody(), "not sealed");
		right.bind(TyType.anonymous(["next"], [use]));
		TyAliasDefinition.seal([left]);
		require(use.getSemanticKey().indexOf("alias-ref:") >= 0, "mutual recursion has no finite back-reference");
		require(!use.isAnonymous() && use.getNominalIdentity() == null && !use.isUnresolved(), "alias reference borrowed another type constructor");
		rejects(() -> left.bind(TyType.fromHintText("String")), "exactly one body");
		rejects(() -> TyType.aliasApplication(left, [TyType.fromHintText("Int")]), "exact argument count");
		final foreign = definition("Types.Foreign");
		rejects(() -> foreign.bind(TyType.typeParameter(new TyTypeParameterId("unrelated", 0, "T"))), "foreign type parameter");
	}

	static function progression():Void {
		final tree = growing();
		final arguments = [TyType.fromHintText("Int")];
		final root = TyType.aliasApplication(tree, arguments);
		arguments[0] = TyType.fromHintText("String");
		root.getTypeArguments().resize(0);
		var current = root;
		var expected = "primitive:Int";
		final key = root.getSemanticKey();
		for (_ in 0...8) {
			require(field(current, "value").getSemanticKey() == expected, "recursive application lost its argument progression");
			current = field(current, "next");
			expected = "nominal:Array<" + expected + ">";
		}
		require(root.getSemanticKey() == key, "expansion mutated a shared definition");
		final outer = new TyTypeParameterId("caller", 0, "Item");
		final open = TyType.aliasApplication(tree, [TyType.typeParameter(outer)]);
		require(TyTypeSubstitution.freeParameterIdentities(open)[0].equals(outer), "alias scan leaked declaration-owned parameters");
		final replaced = TyTypeSubstitution.apply(open, TyTypeSubstitution.bind([outer], [TyType.fromHintText("String")], "caller"));
		require(replaced.getAliasDefinition() == tree, "substitution copied the definition graph");
		require(field(replaced, "value").getSemanticKey() == "primitive:String", "substitution lost the application argument");
		require(field(field(replaced, "next"), "value").getSemanticKey() == "nominal:Array<primitive:String>", "nested substitution stopped at recursion");
	}

	static function keysAndScopes():Void {
		final first = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		final copy = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		require(first.getSemanticKey() == copy.getSemanticKey(), "allocation order changed semantic identity");
		require(first.getSemanticKey() != TyType.aliasApplication(growing(), [TyType.fromHintText("String")]).getSemanticKey(),
			"arguments disappeared from the key");
		require(first.getSemanticKey() != TyType.aliasApplication(growing("Types.Tree", "String"), [TyType.fromHintText("Int")]).getSemanticKey(),
			"a changed alias body reused its old semantic key");
		require(first.getSemanticKey() != TyType.aliasApplication(growing("Other.Tree"), [TyType.fromHintText("Int")]).getSemanticKey(),
			"module identity disappeared");
		function method(binderName:String):TyType {
			final binder = new TyTypeParameterId("method:" + binderName, 0, binderName);
			final signature = TyType.functionType([], TyType.aliasApplication(growing(), [TyType.typeParameter(binder)]));
			return TyType.declaredAnonymous([
				{
					name: "make",
					type: signature,
					kind: Method([binder]),
					isOptional: false,
					visibility: Public,
					metadata: [],
					position: HxPos.unknown()
				}
			]);
		}
		require(method("T").getSemanticKey() == method("U").getSemanticKey(), "alias arguments lost structural method alpha-equivalence");
	}

	static function componentScans():Void {
		final good = TyType.aliasApplication(growing(), [TyType.fromHintText("Int")]);
		require(!good.hasUnknownComponent() && !good.hasOpenMethodParameter(), "complete recursion became an incomplete type");
		final broken = definition("Types.Broken");
		final use = TyType.aliasApplication(broken, []);
		broken.bind(TyType.anonymous(["next", "value"], [use, TyType.unknown()]));
		TyAliasDefinition.seal([broken]);
		require(use.hasUnknownComponent(), "recursive scan hid an unknown payload");
		require(TyType.aliasApplication(growing(), [TyType.unknown()]).hasUnknownComponent(), "recursive scan hid an unknown application argument");
	}
}
