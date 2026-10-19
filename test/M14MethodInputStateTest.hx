/** Caller inference trials must preserve declarations and isolate rejected overload candidates. */
class M14MethodInputStateTest {
	static function declaration(hint:String):TyDeclarationInfo {
		final parsed = ParserStage.parse("class Main { static function accept(value" + hint + "):Void {} }", "Main.hx");
		final module = new ResolvedModule("Main", "Main.hx", parsed);
		final owner = TyperIndex.build([module]).getByFullName("Main");
		return owner.declarationForSignature(owner.staticMethod("accept"));
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function rejects(action:() -> Void, expected:String):Void {
		var message = "";
		try {
			action();
		} catch (error:haxe.Exception) {
			message = error.message;
		}
		require(message.indexOf(expected) >= 0, "missing rejection: " + expected + ": " + message);
	}

	/** New caller evidence rebuilds body facts without changing earlier immutable snapshots. */
	static function bodyPublication():Void {
		final receiver = new ResolvedModule("Receiver", "Receiver.hx",
			ParserStage.parse("class Receiver { public function new() {} public function add(listener):Void {} }", "Receiver.hx"));
		final main = new ResolvedModule("Main", "Main.hx",
			ParserStage.parse('class Main { static function main():Void { new Receiver().add(function(value:Int):Int return value + 1); Sys.println("accepted"); } }',
				"Main.hx"));
		final index = TyperIndex.build([receiver, main]);
		final owner = index.getByFullName("Receiver");
		final method = owner.declarationForSignature(owner.instanceMethod("add"));
		final before = TyperStage.typeResolvedModule(receiver, index);
		final cached = index.getMethodBodyResults().signature(method);
		require(cached.getArgs()[0].isUnknown(), "body supplied unexpected caller evidence");
		final callback = TyType.fromHintText("Int->Int");
		final typedMain = TyperStage.typeResolvedModule(main, index);
		require(index.getMethodInputs().getRevision() > 0, "actual caller did not retain declaration input evidence");
		final finished = TyMethodInputPublication.finish({modules: [before, typedMain], index: index});
		final after = finished[0];
		require(after != before, "production finalizer retained the stale receiver module");
		final repeated = TyMethodInputPublication.finish({modules: finished, index: index});
		require(repeated[0] == after && repeated[1] == finished[1], "stable publication repeated typing");
		for (module in [before, after])
			for (cls in module.getTypedClasses())
				for (fn in cls.getFunctions())
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "add") {
						final actual = fn.getEnvironment().getParams()[0].getType();
						require(module == before ? actual.isUnknown() : actual.getSemanticKey() == callback.getSemanticKey(),
							"method input publication changed the wrong snapshot");
					}
		require(cached.getArgs()[0].isUnknown()
			&& method.getSignature().getArgs()[0].isUnknown(), "cached signature or declaration was mutated");
		JsRuntimeFixture.assertProgramRuntime(MacroStage.expandProgram(finished, []), "Main", "accepted\n");
		Sys.println("METHOD_INPUT_BODY_PUBLICATION:PASS");
	}

	static function main():Void {
		final method = declaration("");
		final original = method.getSignature();
		final state = new TyMethodInputState();
		final callback = TyType.fromHintText("Int->Int");
		final discarded = state.trial(method, original, [TyType.fromHintText("String")]);
		final selected = state.trial(method, original, [callback]);
		require(state.getRevision() == 0
			&& state.signature(method, original).getArgs()[0].isUnknown(), "trial leaked into shared evidence");
		selected.getSignature().getArgs()[0] = TyType.fromHintText("String");
		require(state.commit(selected), "selected evidence was not retained");
		final retained = state.signature(method, original);
		require(retained.getArgs()[0].getSemanticKey() == callback.getSemanticKey(), "candidate view mutated its retained evidence");
		require(original.getArgs()[0].isUnknown(), "declaration header was mutated");
		retained.getArgs()[0] = TyType.fromHintText("String");
		require(state.signature(method, original).getArgs()[0].isFunction(), "returned signature mutated the stored solution");
		rejects(() -> {
			state.commit(discarded);
		}, "stale");
		rejects(() -> {
			new TyMethodInputState().commit(selected);
		}, "foreign");
		require(!state.commit(state.trial(method, original, [callback])) && state.getRevision() == 1, "repeated caller changed revision");
		final conflict = state.trial(method, original, [TyType.fromHintText("String")]);
		require(conflict.getSignature().getArgs()[0].isFunction(), "later caller rebound an established input");
		for (hint in [":String", ":Dynamic"]) {
			final written = declaration(hint);
			final writtenState = new TyMethodInputState();
			final trial = writtenState.trial(written, written.getSignature(), [callback]);
			require(!writtenState.commit(trial), "written annotation acquired caller evidence");
		}
		for (actual in [
			TyType.fromHintText("Dynamic"),
			TyType.fromHintText("Null"),
			TyType.unknown(),
			TyType.typeParameter(new TyTypeParameterId("caller", 0, "T"))
		]) {
			final unconstrained = new TyMethodInputState();
			require(!unconstrained.commit(unconstrained.trial(method, original, [actual])), "non-evidence solved an omitted input");
		}
		final mutable = declaration("");
		final changing = new TyMethodInputState();
		final prior = changing.trial(mutable, mutable.getSignature(), [callback]);
		HxFunctionDecl.getArgs(mutable.getSourceDeclaration()).pop();
		rejects(() -> {
			changing.commit(prior);
		}, "changed source");
		final replacement = declaration("");
		rejects(() -> {
			state.signature(replacement, replacement.getSignature());
		}, "changed declaration");
		final partialState = new TyMethodInputState();
		final partial = callback.withFunctionTypes([TyType.unknown()], TyType.fromHintText("Int"));
		require(partialState.commit(partialState.trial(method, original, [partial])), "callback shape was discarded with its unused input");
		final partialSnapshot = partialState.signature(method, original);
		require(partialState.commit(partialState.trial(method, original, [callback])), "later caller did not solve an unused callback input");
		require(partialSnapshot.getArgs()[0].getFunctionArguments()[0].isUnknown(), "partial callback snapshot was mutated");
		require(partialState.signature(method, original).getArgs()[0].getSemanticKey() == callback.getSemanticKey(), "callback input remained stale");
		require(TyAssignmentCompatibility.classify(partial, partial, Unchecked) == Unknown, "ordinary incomplete assignment was weakened");
		final unproved = TyCallbackArgumentContext.align(TyCallableSignature.fromFunctionValue(TyType.functionType([partial], TyType.fromHintText("Void"))),
			[EIdent("unproved")], [partial], null);
		require(switch unproved {
			case Rejected(_): true;
			case _: false;
		}, "an arbitrary incomplete stored callable was admitted");
		bodyPublication();
		Sys.println("METHOD_INPUT_STATE:PASS");
	}
}
