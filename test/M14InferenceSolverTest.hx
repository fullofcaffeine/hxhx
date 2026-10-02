import TyInferenceTerm;

/** Constraint failures and speculative candidates cannot corrupt the selected type solution. */
class M14InferenceSolverTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejects(action:Void->Void, message:String):Void {
		var rejected = false;
		try {
			action();
		} catch (error:String) {
			rejected = error.indexOf(message) >= 0;
		}
		check(rejected, "missing inference rejection: " + message);
	}

	static function main():Void {
		final binder = TyTypeParameterId.method(new TyNominalTypeId("Example"), false, "echo", 0, 0, "T");
		final open = new TyInferenceSolver("Main.open");
		final firstOpen = open.freshMethodParameter(binder);
		final secondOpen = open.freshMethodParameter(binder);
		rejects(() -> {
			open.requireSolved(firstOpen);
		}, "remains unsolved");
		open.seal();
		final firstPublished = open.requireSolved(firstOpen);
		check(firstPublished.isOpenMethodParameter()
			&& !firstPublished.isUnknown()
			&& !firstPublished.isDynamic()
			&& !firstPublished.isUnresolved()
			&& !firstPublished.isTypeParameter(),
			"open method type lost its distinct semantic meaning");
		check(firstPublished.getSemanticKey() != open.requireSolved(secondOpen).getSemanticKey(), "separate method instances share an open identity");
		check(firstPublished.getCanonicalDisplay() == "Dynamic" && firstPublished.getSemanticKey() != "dynamic",
			"target carrier rendering erased the semantic open identity");
		final concreteOnly = new TyInferenceSolver("Main.concreteOnly");
		final concreteVariable = concreteOnly.fresh();
		check(concreteOnly.constrain(concreteVariable, Known(firstPublished)), "published open type setup failed");
		rejects(() -> concreteOnly.seal(), "required inference cannot publish an open method parameter");
		var aliasKey:Null<String> = null;
		for (reverse in [false, true]) {
			final aliases = new TyInferenceSolver("Main.aliasOpen");
			final a = aliases.freshMethodParameter(binder);
			final b = aliases.freshMethodParameter(binder);
			check(reverse ? aliases.constrain(b, a) : aliases.constrain(a, b), "open alias setup failed");
			aliases.seal();
			final key = aliases.requireSolved(a).getSemanticKey();
			check(key == aliases.requireSolved(b).getSemanticKey(), "open aliases lost their shared identity");
			check(aliasKey == null || aliasKey == key, "unification direction changed the published identity");
			aliasKey = key;
			final mixed = new TyInferenceSolver("Main.mixed");
			final required = mixed.fresh();
			final admitted = mixed.freshMethodParameter(binder);
			check(reverse ? mixed.constrain(admitted, required) : mixed.constrain(required, admitted), "mixed alias setup failed");
			rejects(() -> mixed.seal(), "remains unsolved");
			rejects(() -> {
				mixed.requireSolved(admitted);
			}, "remains unsolved");
			check(mixed.constrain(required, Known(TyType.fromHintText("Int"))), "failed publication mutated required inference");
			mixed.seal();
			check(mixed.requireSolved(admitted).getSemanticKey() == "primitive:Int", "concrete alias evidence was lost");
		}
		final nestedOpen = new TyInferenceSolver("Main.nestedOpen");
		final rollback = new TyInferenceSolver("Main.failedPublication");
		final publishable = rollback.freshMethodParameter(binder);
		final missing = rollback.fresh();
		rejects(() -> rollback.seal(), "remains unsolved");
		rejects(() -> {
			rollback.requireSolved(publishable);
		}, "remains unsolved");
		check(rollback.constrain(publishable, Known(TyType.fromHintText("Int"))), "failed publication froze an independent method parameter");
		check(rollback.constrain(missing, Known(TyType.fromHintText("String"))), "failed publication lost the required parameter");
		rollback.seal();
		check(rollback.requireSolved(publishable).getSemanticKey() == "primitive:Int", "publication rollback lost later concrete evidence");
		final requiredContainer = nestedOpen.fresh();
		final admittedChild = nestedOpen.freshMethodParameter(binder);
		check(nestedOpen.constrain(requiredContainer, Nominal(new TyNominalTypeId("Box"), [admittedChild])), "nested required setup failed");
		rejects(() -> nestedOpen.seal(), "remains unsolved");
		final failedLookup = new TyInferenceSolver("Main.failedLookup");
		final admittedLookup = failedLookup.freshMethodParameter(binder);
		check(failedLookup.constrain(admittedLookup, Known(TyType.unresolved("Missing", [], null))), "failed lookup setup failed");
		rejects(() -> failedLookup.seal(), "incomplete concrete type");
		Sys.println("OPEN_METHOD_INFERENCE:PASS");
		final stringType = TyType.fromHintText("String");
		final intType = TyType.fromHintText("Int");
		final stringTerm = TyInferenceSolver.fromType(stringType);
		final intTerm = TyInferenceSolver.fromType(intType);
		final box = new TyNominalTypeId("model.Box");
		final solver = new TyInferenceSolver("Main.main");
		final first = solver.fresh();
		final second = solver.fresh();
		final candidate = solver.fork();
		check(candidate.constrain(first, stringTerm), "candidate failed its String constraint");
		rejects(() -> {
			solver.requireSolved(first);
		}, "remains unsolved");
		solver.commit(candidate);
		check(solver.requireSolved(first).getSemanticKey() == "primitive:String", "selected candidate lost its solution");
		rejects(() -> {
			solver.requireSolved(second);
		}, "remains unsolved");
		rejects(() -> solver.commit(candidate), "foreign or stale");
		check(!solver.constrain(Nominal(box, [second, intTerm]), Nominal(box, [stringTerm, stringTerm])), "incompatible second component was accepted");
		rejects(() -> {
			solver.requireSolved(second);
		}, "remains unsolved");
		check(solver.constrain(second, intTerm), "failed candidate leaked its first binding");
		final snapshot = solver.requireSolved(Nominal(box, [first]));
		check(!solver.constrain(first, intTerm), "conflicting uses were accepted");
		check(snapshot.getSemanticKey() == "nominal:model.Box<primitive:String>", "a later constraint changed a published snapshot");
		solver.seal();
		rejects(() -> {
			solver.fresh();
		}, "already sealed");
		rejects(() -> {
			solver.constrain(first, stringTerm);
		}, "already sealed");

		final cyclic = new TyInferenceSolver("Main.cycle");
		final a = cyclic.fresh();
		final b = cyclic.fresh();
		check(cyclic.constrain(a, b), "alias constraint failed");
		check(!cyclic.constrain(b, Nominal(box, [a])), "indirect recursive solution was accepted");
		rejects(() -> cyclic.seal(), "remains unsolved");
		check(cyclic.constrain(a, stringTerm), "occurs-check failure polluted its aliases");
		check(cyclic.requireSolved(b).getSemanticKey() == "primitive:String", "alias did not share its solution");

		final parent = new TyInferenceSolver("Main.branch");
		final value = parent.fresh();
		final stale = parent.fork();
		check(stale.constrain(value, intTerm), "stale candidate setup failed");
		check(parent.constrain(value, stringTerm), "current candidate setup failed");
		rejects(() -> parent.commit(stale), "foreign or stale");
		final unrelated = new TyInferenceSolver("Main.branch");
		final foreign = unrelated.fresh();
		rejects(() -> {
			parent.constrain(value, foreign);
		}, "another owner");
		rejects(() -> parent.commit(unrelated), "foreign or stale");

		final structural = new TyInferenceSolver("Main.structural");
		final parameter = structural.fresh();
		final arguments:Array<TyInferenceTerm> = [parameter];
		final term = structural.fresh();
		check(structural.constrain(term, Nominal(box, arguments)), "nominal constraint failed");
		arguments[0] = intTerm;
		check(structural.constrain(parameter, stringTerm), "caller mutation changed stored constraints");
		check(structural.requireSolved(term).getSemanticKey() == "nominal:model.Box<primitive:String>", "stored term retained a caller-owned array");
		check(!structural.constrain(Nominal(new TyNominalTypeId("other.Box"), [stringTerm]), Nominal(box, [stringTerm])),
			"same short name substituted a foreign nominal declaration");
		final result = structural.fresh();
		check(structural.constrain(Function([intTerm], Nullable(result)),
			TyInferenceSolver.fromType(TyType.functionType([intType], TyType.nullable(stringType)))),
			"function result constraint failed");
		check(structural.requireSolved(result).getSemanticKey() == "primitive:String", "nullable function result was not solved");
		structural.seal();
		final incomplete = new TyInferenceSolver("Main.incomplete");
		final nested = incomplete.fresh();
		check(incomplete.constrain(nested, Known(TyType.anonymous(["value"], [TyType.unresolved("Missing", [], null)]))),
			"incomplete structural constraint setup failed");
		rejects(() -> incomplete.seal(), "incomplete concrete type");
		Sys.println("INFERENCE_SOLVER:PASS");
	}
}
