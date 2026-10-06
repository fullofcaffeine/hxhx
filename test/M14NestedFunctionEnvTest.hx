/** Nested functions retain lexical bindings without sharing declaration or return catalogs. */
class M14NestedFunctionEnvTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function identity(owner:String, ordinal:Int):TyNestedFunctionId {
		return new TyNestedFunctionId({
			ownerIdentity: owner,
			sourceOrdinal: ordinal,
			form: Ordinary,
			origin: Authored,
			kind: FunctionExpression
		});
	}

	static function requireSymbol(env:TyFunctionEnv, name:String):TySymbol {
		final symbol = env.resolveSymbol(name);
		if (symbol == null)
			throw "missing lexical binding: " + name;
		return symbol;
	}

	static function main():Void {
		final intType = TyType.fromHintText("Int");
		final stringType = TyType.fromHintText("String");
		final outerT = new TyTypeParameterId("outer", 0, "T");
		final outer = new TyFunctionEnv("outer", [], [], intType, intType, "outer", null, false, 0, true, [outerT]);
		final shared = outer.declareLocal("shared", TyType.unknown());
		final hidden = outer.declareLocal("value", intType);
		outer.enterLexicalScope();
		final visible = outer.declareLocal("value", stringType);
		final self = outer.declareLocal("recur", TyType.unknown(), NamedFunction);
		final id = identity("outer", 0);
		final parameterInputs = [{name: "arg", type: intType}, {name: "shared", type: stringType}];
		final shadow = outer.createNestedFunction({
			identity: identity("outer", 1),
			name: "shadow",
			parameters: parameterInputs,
			typeParameterNames: [],
			returnType: stringType,
			returnExprType: stringType
		});
		parameterInputs.pop();
		check(requireSymbol(shadow, "shared").getIdentity().getOwnerIdentity() == shadow.getOwnerIdentity(),
			"parameter did not shadow the outer binding or retained the caller array");
		final child = outer.createNestedFunction({
			identity: id,
			name: "child",
			parameters: [{name: "arg", type: intType}],
			typeParameterNames: ["T"],
			returnType: stringType,
			returnExprType: stringType
		});
		outer.declareLocal("later", intType);
		outer.exitLexicalScope();
		check(requireSymbol(child, "value") == visible, "capture changed after leaving the definition scope");
		check(requireSymbol(outer, "value") == hidden, "nested scope leaked into the enclosing scope");
		check(child.resolveSymbol("later") == null, "later declaration became visible retroactively");
		check(requireSymbol(child, "recur") == self, "recursive binding lost its declaration identity");
		check(child.isStaticContext(), "nested function lost its class context");
		check(child.getReturnType().getSemanticKey() == stringType.getSemanticKey(), "nested return boundary changed");
		check(outer.getReturnType().getSemanticKey() == intType.getSemanticKey(), "nested return contaminated enclosing function");
		final generics = child.getTypeParameters();
		check(generics.length == 2 && generics[0].equals(outerT), "enclosing generic identity disappeared");
		check(generics[1].equals(TyTypeParameterId.nestedFunction(id, 0, "T")), "nested generic borrowed an enclosing identity");
		generics.pop();
		check(child.getTypeParameters().length == 2, "caller mutated generic visibility");
		final arg = requireSymbol(child, "arg");
		check(arg.getIdentity().getOwnerIdentity() == id.getCanonicalKey(), "parameter belongs to another function");
		check(child.getLocals().length == 0, "enclosing declarations entered the child catalog");
		shared.setType(intType);
		check(requireSymbol(child, "shared").getType().getSemanticKey() == intType.getSemanticKey(), "capture lost the shared inference slot");
		final local = child.declareLocal("value", intType);
		check(requireSymbol(child, "value") == local, "child local did not shadow its capture");
		check(local.getIdentity().getOwnerIdentity() == id.getCanonicalKey(), "child local borrowed enclosing ownership");
		check(outer.getLocals().length == 5, "child declaration entered the enclosing catalog");
		final grandchild = child.createNestedFunction({
			identity: identity(id.getCanonicalKey(), 0),
			name: "grandchild",
			parameters: [],
			typeParameterNames: [],
			returnType: intType,
			returnExprType: intType
		});
		check(requireSymbol(grandchild, "shared") == shared
			&& requireSymbol(grandchild, "value") == local, "transitive enclosing bindings changed");
		final replay = child.withReturnTypes(intType, intType).createBodyReplay();
		check(requireSymbol(replay, "value") == visible, "replay exposed a local before its declaration");
		check(requireSymbol(replay, "arg").getIdentity().equals(arg.getIdentity()), "replay changed parameter identity");
		check(replay.declareLocal("value", intType).getIdentity().equals(local.getIdentity()), "replay changed local identity");
		replay.assertReplayComplete();
		final speculative = replay.copyForInference();
		requireSymbol(speculative, "shared").setType(stringType);
		check(shared.getType().getSemanticKey() == intType.getSemanticKey(), "speculation mutated an enclosing type slot");
		check(requireSymbol(speculative, "shared").getIdentity().equals(shared.getIdentity()), "speculation changed capture identity");
		check(requireSymbol(speculative, "value").getIdentity().equals(local.getIdentity()), "speculation lost local shadowing");
		var rejected = false;
		try
			outer.createNestedFunction({
				identity: identity("foreign", 0),
				name: "foreign",
				parameters: [],
				typeParameterNames: [],
				returnType: intType,
				returnExprType: intType
			})
		catch (_:String)
			rejected = true;
		check(rejected, "foreign nested owner was accepted");
		Sys.println("NESTED_FUNCTION_ENV:PASS");
	}
}
