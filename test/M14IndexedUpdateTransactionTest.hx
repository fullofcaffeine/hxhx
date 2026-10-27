import TyIndexedUpdateSelection.TyIndexedUpdateQuery;
import TyIndexedUpdateSelection.TyIndexedUpdateKind;

/** Indexed helper selection must publish all inference and declaration inputs together, or publish neither. */
@:access(TyperStage)
class M14IndexedUpdateTransactionTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function rejects(action:() -> Void, expected:String):Void {
		var message = "";
		try
			action()
		catch (error:haxe.Exception)
			message = error.message;
		require(message.indexOf(expected) >= 0, "missing rejection " + expected + ": " + message);
	}

	static function fixture():{
		index:TyperIndex,
		getter:TyDeclarationInfo,
		setter:TyDeclarationInfo,
		input:TyDeclarationInfo
	} {
		final module = new ResolvedModule("Main", "Main.hx",
			ParserStage.parse('class Main { public function new() {} public function read(index:Int):Int return 1; public function write(index:Int,value:Int):String return "written"; static function accept(value):Void {} }',
				"Main.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Main");
		return {
			index: index,
			getter: owner.declarationForSignature(owner.instanceMethod("read")),
			setter: owner.declarationForSignature(owner.instanceMethod("write")),
			input: owner.declarationForSignature(owner.staticMethod("accept"))
		};
	}

	static function query(owner:String, ?source:HxExpr, ?kind:TyIndexedUpdateKind):TyIndexedUpdateQuery {
		final receiver:HxExpr = ECall(EIdent("slots"), []);
		final index:HxExpr = EInt(0);
		final get:HxExpr = EArrayAccess(receiver, index);
		final computed:HxExpr = EBinop("+", get, EInt(1));
		final set:HxExpr = EBinop("=", EArrayAccess(receiver, index), computed);
		return new TyIndexedUpdateQuery({
			owner: owner,
			source: source == null ? HxParser.parseExprText("slots[0]++") : source,
			kind: kind == null ? Unary(Increment, Postfix) : kind,
			getterSource: get,
			computedSource: computed,
			setterSource: set
		});
	}

	static function complete(query:TyIndexedUpdateQuery, getter:TyDeclarationInfo, setter:TyDeclarationInfo):TyIndexedUpdateSelection {
		final operands = switch query.getterSource {
			case EArrayAccess(receiver, index): {receiver: receiver, index: index};
			case _: throw "unexpected getter fixture query";
		};
		return new TyIndexedUpdateSelection({
			query: query,
			getter: new TyIndexedAccessBinding(query.getterSource, operands.receiver, [operands.index], getter),
			setter: new TyIndexedAccessBinding(query.setterSource, operands.receiver, [operands.index, query.computedSource], setter)
		});
	}

	static function environment():TyFunctionEnv
		return new TyFunctionEnv("update", [], [], TyType.fromHintText("Void"), TyType.unknown(), "update", null, false, 0, false,
			new TyControlScope("update", "source-v1"));

	/** Operation identity includes fixity, and a completed selection must belong to this exact candidate query. */
	static function sourceKindAndCompletion():Void {
		query("update", HxParser.parseExprText("++slots[0]"), Unary(Increment, Prefix));
		query("update", HxParser.parseExprText("slots[0]--"), Unary(Decrement, Postfix));
		query("update", HxParser.parseExprText("slots[0] += 1"), Compound("+="));
		for (kind in [
			Unary(Increment, Prefix),
			Unary(Decrement, Postfix),
			Unary(Negate, Prefix),
			Compound("+="),
			Compound("??=")
		])
			rejects(() -> query("update", HxParser.parseExprText("slots[0]++"), kind), "kind disagrees");
		rejects(() -> query("update", HxParser.parseExprText("slots[0] += 1"), Compound("-=")), "kind disagrees");
		rejects(() -> query("update", HxParser.parseExprText("slots[0] ??= 1"), Compound("??=")), "kind disagrees");
		final facts = fixture();
		final env = environment();
		final parent = env.getInference();
		final owned = query("update");
		final trial = parent.beginIndexedUpdate(owned);
		final candidate = env.copyForIndexedSelection(trial);
		trial.candidate.contextualCollection(owned.getterSource, TyType.fromHintText("Int"));
		final inputs = new TyMethodInputState();
		final batch = inputs.prepareBatch([]);
		// Equal syntax does not let a selection completed for another trial borrow this fork.
		final foreign = complete(query("update"), facts.getter, facts.setter);
		rejects(() -> parent.commitIndexedUpdate(trial, foreign, inputs, batch), "another trial query");
		require(parent.sourceTerm(owned.getterSource, env) == null, "foreign completion published getter facts");
		final completed = complete(owned, facts.getter, facts.setter);
		parent.commitIndexedUpdate(trial, completed, inputs, batch);
		require(parent.sourceTerm(owned.getterSource, env) != null, "complete candidate did not publish getter facts");
	}

	/** Supported candidate constraints solve their own nested terms without editing shared retained child arrays. */
	static function nestedTermIsolation():Void {
		final facts = fixture();
		final env = environment();
		final parent = env.getInference();
		final receiver:HxExpr = EIdent("genericReceiver");
		final owner = new TyNominalTypeId("Envelope");
		parent.construct(receiver, TyType.nominal(owner, []), 1);
		final before = parent.expressionType(receiver, TyType.unknown(), env).getSemanticKey();
		final trial = parent.beginIndexedUpdate(query("update"));
		final candidate = env.copyForIndexedSelection(trial);
		final integer = TyType.nominal(owner, [TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Int")])]);
		final string = TyType.nominal(owner, [TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("String")])]);
		require(trial.candidate.constrain([receiver], [integer], candidate, facts.index), "candidate failed to solve nested result");
		require(!trial.candidate.constrain([receiver], [string], candidate, facts.index), "late nested mismatch was admitted");
		require(parent.expressionType(receiver, TyType.unknown(), env).getSemanticKey() == before, "candidate changed parent nested terms");
		require(trial.candidate.expressionType(receiver, TyType.unknown(), candidate).getSemanticKey() == integer.getSemanticKey(),
			"failed nested constraint changed candidate's earlier solution");
		require(parent.constrain([receiver], [string], env, facts.index), "discarded candidate constrained the parent child term");
	}

	/** Multiple roles may select the same declaration; combine only compatible observations from this base. */
	static function inputBatches():Void {
		final method = fixture().input;
		final body = method.getSignature();
		final int = TyType.fromHintText("Int");
		final string = TyType.fromHintText("String");
		final unknown = TyType.unknown();
		final partialInput = TyType.functionType([int], unknown);
		final partialResult = TyType.functionType([unknown], string);
		final complete = TyType.functionType([int], string);
		for (reverse in [false, true]) {
			final state = new TyMethodInputState();
			final first = state.trial(method, body, [partialInput]);
			final second = state.trial(method, body, [partialResult]);
			final batch = state.prepareBatch(reverse ? [second, first] : [first, second]);
			require(state.getRevision() == 0 && state.signature(method, body).getArgs()[0].isUnknown(), "prepared batch leaked evidence");
			require(state.commitBatch(batch) && state.getRevision() == 1, "duplicate batch did not publish one revision");
			require(state.signature(method, body).getArgs()[0].getSemanticKey() == complete.getSemanticKey(), "partial callbacks were not merged");
			require(!state.commit(state.trial(method, body, [string])), "ordinary later caller rebound established evidence");
			final conflict = new TyMethodInputState();
			final left = conflict.trial(method, body, [int]);
			final right = conflict.trial(method, body, [string]);
			rejects(() -> conflict.prepareBatch(reverse ? [right, left] : [left, right]), "conflicting observations");
			require(conflict.getRevision() == 0
				&& conflict.signature(method, body).getArgs()[0].isUnknown(), "conflicting batch partly committed");
		}
		final state = new TyMethodInputState();
		final trial = state.trial(method, body, [int]);
		rejects(() -> new TyMethodInputState().prepareBatch([trial]), "foreign");
		final batch = state.prepareBatch([trial]);
		state.commit(state.trial(method, body, [int]));
		rejects(() -> state.commitBatch(batch), "stale");
		require(state.getRevision() == 1, "stale batch changed revision");
	}

	/** A known occurrence can change the parent facts without changing its solver revision. */
	static function staleFacts():Void {
		final facts = fixture();
		final env = environment();
		final inference = env.getInference();
		final trial = inference.beginIndexedUpdate(query(env.getOwnerIdentity()));
		final inputs = new TyMethodInputState();
		final batch = inputs.prepareBatch([
			inputs.trial(facts.input, facts.input.getSignature(), [TyType.fromHintText("Int")])
		]);
		final known:HxExpr = EIdent("laterKnown");
		inference.contextualCollection(known, TyType.fromHintText("Int"));
		rejects(() -> inference.commitIndexedUpdate(trial, complete(trial.query, facts.getter, facts.setter), inputs, batch), "facts are foreign or stale");
		require(inputs.getRevision() == 0
			&& inference.expressionType(known, TyType.unknown(), env).getSemanticKey() == TyType.fromHintText("Int").getSemanticKey(),
			"stale rejection lost parent facts or published inputs");
	}

	/** Getter work remains private when a later setter input cannot satisfy the same retained result. */
	static function failedSetter():Void {
		final facts = fixture();
		final env = environment();
		final inference = env.getInference();
		final selected = query(env.getOwnerIdentity());
		final trial = inference.beginIndexedUpdate(selected);
		final candidate = env.copyForIndexedSelection(trial);
		trial.candidate.untypedResult(selected.computedSource);
		require(trial.candidate.constrain([selected.computedSource], [TyType.fromHintText("Int")], candidate, facts.index), "getter result did not constrain");
		require(!trial.candidate.constrain([selected.computedSource], [TyType.fromHintText("String")], candidate, facts.index),
			"incompatible setter was admitted");
		require(inference.sourceTerm(selected.computedSource, env) == null, "failed setter leaked computed result");
		final inputs = new TyMethodInputState();
		require(inputs.getRevision() == 0, "discarded candidate published method inputs");
		final accepted = inference.beginIndexedUpdate(selected);
		final acceptedEnv = env.copyForIndexedSelection(accepted);
		accepted.candidate.contextualCollection(selected.getterSource, TyType.fromHintText("Int"));
		accepted.candidate.contextualCollection(selected.computedSource, TyType.fromHintText("Float"));
		accepted.candidate.contextualCollection(selected.setterSource, TyType.fromHintText("String"));
		final batch = inputs.prepareBatch([
			inputs.trial(facts.input, facts.input.getSignature(), [TyType.fromHintText("Float")])
		]);
		final completed = complete(selected, facts.getter, facts.setter);
		inference.commitIndexedUpdate(accepted, completed, inputs, batch);
		require(inference.expressionType(selected.getterSource, TyType.unknown(), env).getSemanticKey() == TyType.fromHintText("Int").getSemanticKey(),
			"getter result changed");
		require(inference.expressionType(selected.computedSource, TyType.unknown(), env).getSemanticKey() == TyType.fromHintText("Float").getSemanticKey(),
			"computed result aliased getter");
		require(inference.expressionType(selected.setterSource, TyType.unknown(), env).getSemanticKey() == TyType.fromHintText("String").getSemanticKey()
			&& inputs.getRevision() == 1,
			"setter result or inputs were not published");
		rejects(() -> inference.commitIndexedUpdate(accepted, completed, inputs, batch), "stale");
	}

	static function identityAndLexicalState():Void {
		final facts = fixture();
		final env = environment();
		final inference = env.getInference();
		rejects(() -> inference.beginIndexedUpdate(query("foreign")), "another owner");
		final selected = query(env.getOwnerIdentity());
		final trial = inference.beginIndexedUpdate(selected);
		final candidate = env.copyForIndexedSelection(trial);
		candidate.declareLocal("lostDeclaration", TyType.fromHintText("Int"));
		final inputs = new TyMethodInputState();
		rejects(() -> inference.commitIndexedUpdate(trial, complete(selected, facts.getter, facts.setter), inputs, inputs.prepareBatch([])),
			"lexical or control");
		require(env.getLocals().length == 0 && inputs.getRevision() == 0, "candidate declaration escaped into owning source catalog");
		final controlTrial = inference.beginIndexedUpdate(selected);
		final controlCandidate = env.copyForIndexedSelection(controlTrial);
		controlCandidate.requireControlScope().enter(Loop, "invented-loop");
		rejects(() -> inference.commitIndexedUpdate(controlTrial, complete(selected, facts.getter, facts.setter), inputs, inputs.prepareBatch([])),
			"lexical or control");
		final changed = query(env.getOwnerIdentity());
		final changedTrial = inference.beginIndexedUpdate(changed);
		final foreignSource:HxExpr = ECall(EIdent("query"), []);
		final wrong = new TyIndexedAccessBinding(foreignSource, EIdent("slots"), [EInt(0)], facts.getter);
		rejects(() -> new TyIndexedUpdateSelection({
			query: changed,
			getter: wrong,
			setter: complete(changed, facts.getter, facts.setter).setter
		}), "another query");
		final completedChanged = complete(changed, facts.getter, facts.setter);
		final arguments = switch changed.getterSource {
			case EArrayAccess(ECall(_, arguments), _): arguments;
			case _: throw "unexpected fixture query";
		};
		arguments.push(EInt(7));
		rejects(() -> inference.commitIndexedUpdate(changedTrial, completedChanged, inputs, inputs.prepareBatch([])), "query changed");
		require(inputs.getRevision() == 0, "changed query published inputs");
	}

	/** A late failure in either participant cannot publish an earlier successful inference step. */
	static function coordinatedRollback():Void {
		final facts = fixture();
		for (staleInputs in [false, true]) {
			final env = environment();
			final parent = env.getInference();
			final value:HxExpr = EIdent("lateResult");
			parent.untypedResult(value);
			final trial = parent.beginIndexedUpdate(query("update"));
			final candidate = env.copyForIndexedSelection(trial);
			require(trial.candidate.constrain([value], [TyType.fromHintText("Int")], candidate, facts.index), "candidate did not solve result");
			final inputs = new TyMethodInputState();
			final batch = inputs.prepareBatch([
				inputs.trial(facts.input, facts.input.getSignature(), [TyType.fromHintText("Float")])
			]);
			if (staleInputs) {
				inputs.commit(inputs.trial(facts.input, facts.input.getSignature(), [TyType.fromHintText("String")]));
			} else {
				require(parent.constrain([value], [TyType.fromHintText("String")], env, facts.index), "parent did not accept independent later solution");
			}
			rejects(() -> parent.commitIndexedUpdate(trial, complete(trial.query, facts.getter, facts.setter), inputs, batch), "stale");
			require(parent.expressionType(value, TyType.unknown(), env)
				.getSemanticKey() == (staleInputs ? TyType.unknown() : TyType.fromHintText("String")).getSemanticKey(),
				"late rejection published candidate solver");
			require(inputs.getRevision() == (staleInputs ? 1 : 0), "late rejection changed method input revision");
			require(inputs.signature(facts.input, facts.input.getSignature())
				.getArgs()[0].getSemanticKey() == (staleInputs ? TyType.fromHintText("String") : TyType.unknown()).getSemanticKey(),
				"late rejection changed method input content");
		}
	}

	/** Authored operands retain their block declarations and closures in the original replay catalog. */
	static function authoredOperandOwnership():Void {
		final facts = fixture();
		final env = environment();
		final context = new TyperContext(facts.index, "Main.hx", "Main", "", [], "Main");
		final operands = [
			for (role in ["receiver", "index", "rhs"])
				HxParser.parseExprText('{ var ' + role + 'Local:Int = 1; var ' + role + 'Closure = function():Int return ' + role + 'Local; ' + role
					+ 'Closure(); }')
		];
		for (operand in operands)
			require(TyperStage.inferExprType(operand, env, context, HxPos.unknown()).getSemanticKey() == TyType.fromHintText("Int").getSemanticKey(),
				"authored operand lost its result");
		final locals = env.getLocals();
		require(locals.length == 6, "authored operand declarations were not visited once");
		final parent = env.getInference();
		final trial = parent.beginIndexedUpdate(query("update"));
		final candidate = env.copyForIndexedSelection(trial);
		final inputs = new TyMethodInputState();
		parent.commitIndexedUpdate(trial, complete(trial.query, facts.getter, facts.setter), inputs, inputs.prepareBatch([]));
		for (index in 0...locals.length)
			require(env.getLocals()[index] == locals[index], "selection replaced the authored declaration catalog");
		// Sealed lookup must retain the exact authored closures, rather than recomputing them in a copied scope.
		env.sealInference();
		for (operand in operands) {
			final closure = switch operand {
				case ESourceGroup([_, EVars([EVariableDeclaration(_, _, initializer, _, _, _)]), _], _): initializer;
				case _: throw "authored operand fixture lost its closure";
			};
			final retained = parent.sourceFunctionType(closure);
			require(retained != null && retained.getSemanticKey() == TyType.functionType([], TyType.fromHintText("Int")).getSemanticKey(),
				"selection lost the authored closure's retained signature");
		}
	}

	static function main():Void {
		sourceKindAndCompletion();
		nestedTermIsolation();
		inputBatches();
		staleFacts();
		failedSetter();
		identityAndLexicalState();
		coordinatedRollback();
		authoredOperandOwnership();
		Sys.println("INDEXED_UPDATE_TRANSACTION:PASS");
	}
}
