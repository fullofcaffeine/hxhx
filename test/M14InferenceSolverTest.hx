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

	/** Retained argument evidence cannot be borrowed by another declaration or equal-looking source node. */
	static function receiverCallOwnership():Void {
		final source = "class Box<T> { public function take(value:T):Void {} public function other(value:T):Void {} public function read():T return null; } class Main {}";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Main.Box");
		final declaration = owner.declarationForSignature(owner.instanceMethodCandidates("take")[0]);
		final other = owner.declarationForSignature(owner.instanceMethodCandidates("other")[0]);
		final arguments:Array<HxExpr> = [EIdent("value")];
		final call:HxExpr = ECall(EField(EIdent("box"), "take"), arguments);
		final identical:HxExpr = ECall(EField(EIdent("box"), "take"), [EIdent("value")]);
		final integer = TyType.fromHintText("Int");
		final dynamicType = TyType.fromHintText("Dynamic");
		final parameters:Array<Null<TyType>> = [dynamicType];
		final context = new TyReceiverCallContext(call, declaration, parameters);
		parameters[0] = integer;
		check(context.apply(call, declaration, [integer])[0].isDynamic(), "retained call borrowed its caller's mutable parameter list");
		rejects(() -> context.apply(identical, declaration, [integer]), "no longer belongs");
		rejects(() -> context.apply(call, other, [integer]), "no longer belongs");
		final inference = new TyFunctionInference("receiver-context");
		inference.recordReceiverCall(call, declaration, [dynamicType]);
		check(inference.receiverCallParameters(identical, declaration, [integer])[0].getSemanticKey() == integer.getSemanticKey(),
			"a distinct occurrence borrowed receiver permission");
		check(inference.fork().receiverCallParameters(call, declaration, [integer])[0].isDynamic(), "fork lost immutable invocation evidence");
		final resultEnvironment = new TyFunctionEnv("receiver-result", [], [], TyType.unknown(), TyType.unknown());
		final resultInference = resultEnvironment.getInference();
		final receiver:HxExpr = EIdent("receiver");
		resultInference.construct(receiver, TyType.nominal(owner.getIdentity(), []), 1);
		final read = owner.declarationForSignature(owner.instanceMethodCandidates("read")[0]);
		final resultArguments:Array<HxExpr> = [];
		final resultCall:HxExpr = ECall(EField(receiver, "read"), resultArguments);
		resultInference.recordReceiverResult(resultCall, receiver, read, resultEnvironment, index);
		check(resultInference.constrain([resultCall], [integer], resultEnvironment, index), "member result lost receiver variables");
		check(resultInference.expressionType(receiver, TyType.unknown(), resultEnvironment).getTypeArguments()[0].getSemanticKey() == integer.getSemanticKey(),
			"result context did not constrain its receiver");
		rejects(() -> resultInference.recordReceiverResult(resultCall, receiver, other, resultEnvironment, index), "changed its selected declaration");
		resultArguments.push(EInt(7));
		rejects(() -> resultInference.expressionType(resultCall, integer, resultEnvironment), "source changed");
		arguments[0] = EInt(7);
		rejects(() -> context.apply(call, declaration, [integer]), "no longer belongs");
	}

	/** Nullable argument inference keeps wrappers and rolls back every component on failure. */
	static function nullableInputContracts():Void {
		final solver = new TyInferenceSolver("nullable-input");
		final integer = Known(TyType.fromHintText("Int"));
		final string = Known(TyType.fromHintText("String"));
		check(!solver.constrain(Nullable(integer), integer), "exact unification erased nullability");
		final value = solver.fresh();
		final owner = new TyNominalTypeId("Pair");
		final wanted = Nominal(owner, [Nullable(value), integer]);
		check(!solver.constrainNullableInput(wanted, Nominal(owner, [string, string])), "nullable matching accepted a conflicting component");
		check(solver.preview(value).isUnknown(), "failed nullable matching leaked its first binding");
		check(solver.constrainNullableInput(wanted, Nominal(owner, [integer, integer])), "nullable matching rejected a matching input");
		check(solver.requireSolved(Nullable(value)).getSemanticKey() == TyType.nullable(TyType.fromHintText("Int")).getSemanticKey(),
			"nullable input lost its wrapper");
		check(!solver.constrainNullableInput(wanted, Nominal(owner, [string, integer])), "later input erased an existing constraint");
		check(!solver.constrainNullableInput(integer, Nullable(integer)), "nullable input matching became symmetric");
	}

	/** Nested record variables participate in ownership, rollback, occurs checks, and exact field contracts. */
	static function structuralContracts():Void {
		final solver = new TyInferenceSolver("Main.structural");
		final value = solver.fresh();
		final template = TyType.anonymous(["item"], [TyType.fromHintText("String")]);
		final record = Structure([value], template);
		check(solver.constrain(record, TyInferenceSolver.fromType(template)), "record context did not solve its field");
		check(solver.requireSolved(value).getSemanticKey() == "primitive:String", "record field solution differs");
		check(solver.requireSolved(record).getSemanticKey() == template.getSemanticKey(), "record rebuild lost its field contract");
		final recursive = solver.fresh();
		check(!solver.constrain(recursive, Structure([recursive], template)), "recursive record was accepted");
		final foreign = new TyInferenceSolver("Other.structural");
		rejects(() -> solver.preview(Structure([foreign.fresh()], template)), "another owner");
		final optional = TyType.declaredAnonymous([
			{
				name: "item",
				type: TyType.fromHintText("String"),
				kind: Variable(false, "", ""),
				isOptional: true,
				visibility: Public,
				metadata: [],
				position: HxPos.unknown()
			}
		]);
		check(!solver.constrain(TyInferenceSolver.fromType(template), TyInferenceSolver.fromType(optional)), "exact record unification erased optionality");
		final pair = TyType.anonymous(["first", "second"], [TyType.fromHintText("String"), TyType.fromHintText("Int")]);
		final pending = solver.fresh();
		check(!solver.constrain(Structure([pending, Known(TyType.fromHintText("String"))], pair), TyInferenceSolver.fromType(pair)),
			"conflicting record fields were accepted");
		check(solver.preview(pending).isUnknown(), "failed record constraint leaked its first field solution");
		check(solver.constrain(pending, Known(TyType.fromHintText("Int"))), "failed record constraint froze its variable");
		final publication = new TyInferenceSolver("Main.structuralPublication");
		final required = publication.fresh();
		final binder = TyTypeParameterId.method(new TyNominalTypeId("Example"), false, "record", 0, 0, "T");
		final open = publication.freshMethodParameter(binder);
		check(publication.constrain(required, Structure([open], template)), "nested required record setup failed");
		rejects(() -> publication.seal(), "remains unsolved");
		check(publication.constrain(open, Known(TyType.fromHintText("String"))), "failed record publication mutated the solver");
		publication.seal();
		check(publication.requireSolved(required).getSemanticKey() == template.getSemanticKey(), "record publication lost its concrete field");
		final callable = TyType.functionType([], TyType.fromHintText("String"));
		final method = TyType.declaredAnonymous([
			{
				name: "get",
				type: callable,
				kind: Method([]),
				isOptional: false,
				visibility: Public,
				metadata: [],
				position: HxPos.unknown()
			}
		]);
		check(solver.constrain(TyInferenceSolver.fromType(method), TyInferenceSolver.fromType(method)), "structural method identity was rejected");
		check(!solver.constrain(TyInferenceSolver.fromType(method), TyInferenceSolver.fromType(TyType.anonymous(["get"], [callable]))),
			"structural method became a writable function field");
		Sys.println("STRUCTURAL_INFERENCE:PASS");
	}

	/** Nominal field evidence is transactional, owner-checked, and shares the receiver's generic variables. */
	static function nominalMemberContracts():Void {
		final solver = new TyInferenceSolver("Main.nominalMembers");
		final receiver = solver.freshUntypedResult();
		final count = solver.field(receiver, "count");
		final label = solver.field(receiver, "label");
		final intType = TyType.fromHintText("Int");
		final stringType = TyType.fromHintText("String");
		check(solver.constrain(label, Known(stringType)), "label setup failed");
		final nominal = Nominal(new TyNominalTypeId("Box"), []);
		check(!solver.constrain(receiver, nominal), "nominal fields were invented without declaration evidence");
		check(!solver.constrain(receiver, nominal, (_, _) -> Known(intType)), "conflicting nominal label was accepted");
		check(solver.preview(count).isUnknown(), "failed nominal member check leaked the earlier count binding");
		check(!solver.constrain(receiver, nominal, (_, _) -> null), "missing nominal members were accepted");
		final foreign = new TyInferenceSolver("Other.nominalMembers");
		final foreignTerm = foreign.fresh();
		rejects(() -> solver.constrain(receiver, nominal, (_, _) -> foreignTerm), "another owner");
		check(solver.constrain(receiver, nominal, (_, name) -> Known(name == "count" ? intType : stringType)), "valid nominal members were rejected");
		solver.seal();
		check(solver.published(receiver).getNominalIdentity().getCanonicalName() == "Box", "nominal binding became a structural record");
		check(solver.published(count).getSemanticKey() == intType.getSemanticKey(), "nominal member solution was lost");
		final generic = new TyInferenceSolver("Main.genericMember");
		final value = generic.freshUntypedResult();
		final item = generic.field(value, "item");
		final parameter = generic.fresh();
		check(generic.constrain(item, Known(intType)), "generic member setup failed");
		check(generic.constrain(value, Nominal(new TyNominalTypeId("GenericBox"), [parameter]), (owner, name) -> switch owner {
			case Nominal(_, [argument]) if (name == "item"): argument;
			case _: null;
		}), "member constraint did not reach the owner's generic variable");
		generic.seal();
		check(generic.published(parameter).getSemanticKey() == intType.getSemanticKey(), "generic argument was copied instead of shared");
		Sys.println("NOMINAL_MEMBER_INFERENCE:PASS");
	}

	/** A later operand can reject a candidate after an earlier operand has bound its result variable. */
	static function directCallConstraints():Void {
		dynamicDirectCalls();
		final solver = new TyInferenceSolver("Main.directCall");
		final parameter = solver.fresh();
		final unknown = TyType.unknown();
		final callable = Function([parameter, parameter], parameter, TyType.functionType([unknown, unknown], unknown));
		final signature = new TyFunSig("choose", true, ["first", "second"], [unknown, unknown], [false, false], [false, false], unknown, HxPos.unknown());
		final intType = TyType.fromHintText("Int");
		final stringType = TyType.fromHintText("String");
		final index = TyperIndex.build([]);
		final rejected = solver.fork();
		check(!TyDirectGenericCallConstraints.constrain({
			solver: rejected,
			callable: callable,
			signature: signature,
			order: TyMethodArgumentOrder.select(signature, [EInt(1), EString("bad")], (_, _, _) -> Compatible),
			arguments: [EInt(1), EString("bad")],
			terms: [Known(intType), Known(stringType)],
			index: index,
			accepts: (expected, actual) -> expected.getSemanticKey() == actual.getSemanticKey()
		}), "conflicting direct operands were accepted after solving an earlier parameter");
		check(solver.preview(parameter).isUnknown(), "rejected direct-call candidate changed its parent");
		final accepted = solver.fork();
		check(TyDirectGenericCallConstraints.constrain({
			solver: accepted,
			callable: callable,
			signature: signature,
			order: TyMethodArgumentOrder.select(signature, [EInt(1), EInt(2)], (_, _, _) -> Compatible),
			arguments: [EInt(1), EInt(2)],
			terms: [Known(intType), Known(intType)],
			index: index,
			accepts: (expected, actual) -> expected.getSemanticKey() == actual.getSemanticKey()
		}), "matching direct operands were rejected");
		solver.commit(accepted);
		solver.seal();
		check(solver.requireSolved(callable)
			.getFunctionReturn()
			.getSemanticKey() == intType.getSemanticKey(), "direct-call result lost its argument equation");
		Sys.println("DIRECT_CALL_CONSTRAINTS:PASS");
		final spread = new TyInferenceSolver("Main.spreadCall");
		final element = spread.fresh();
		final array = new TyNominalTypeId("Array");
		final restSignature = new TyFunSig("spread", true, ["items"], [TyType.nominal(array, [unknown])], [false], [true], unknown, HxPos.unknown());
		final restCallable = Function([element], element, TyType.functionSignature([
			{
				name: "items",
				type: unknown,
				isOptional: false,
				isRest: true,
				metadata: []
			}
		], unknown));
		check(TyDirectGenericCallConstraints.constrain({
			solver: spread,
			callable: restCallable,
			signature: restSignature,
			order: TyMethodArgumentOrder.select(restSignature, [ECall(EIdent("__hxhx_spread"), [EIdent("values")])], (_, _, _) -> Compatible),
			arguments: [ECall(EIdent("__hxhx_spread"), [EIdent("values")])],
			terms: [Nominal(array, [Known(intType)])],
			index: index,
			accepts: (expected, actual) -> expected.getSemanticKey() == actual.getSemanticKey()
		}), "spread container did not contribute its element constraint");
		spread.seal();
		check(spread.requireSolved(element).getSemanticKey() == intType.getSemanticKey(), "spread element identity was lost");
		Sys.println("DIRECT_CALL_SPREAD_CONSTRAINT:PASS");
	}

	/** Dynamic consumers supply a publication fallback, never an early alias-unification result. */
	static function dynamicDirectCalls():Void {
		final integer = TyType.fromHintText("Int");
		final dynamicType = TyType.fromHintText("Dynamic");
		final unknown = TyType.unknown();
		for (concreteLater in [false, true]) {
			final solver = new TyInferenceSolver("Main.dynamicDirect");
			final parameter = solver.fresh();
			final signature = new TyFunSig("fixed", true, ["value"], [unknown], [false], [false], integer, HxPos.unknown());
			final callable = Function([parameter], Known(integer), TyType.functionType([unknown], integer));
			check(TyDirectGenericCallConstraints.constrain({
				solver: solver,
				callable: callable,
				signature: signature,
				order: TyMethodArgumentOrder.select(signature, [EIdent("value")], (_, _, _) -> Compatible),
				arguments: [EIdent("value")],
				terms: [Known(dynamicType)],
				index: TyperIndex.build([]),
				accepts: (expected, actual) -> expected.getSemanticKey() == actual.getSemanticKey()
			}), "explicit Dynamic call was rejected");
			check(solver.preview(parameter).isUnknown(), "Dynamic input solved a generic parameter too early");
			if (concreteLater)
				check(solver.constrain(parameter, Known(integer)), "later concrete type lost to Dynamic evidence");
			solver.seal();
			check(solver.requireSolved(parameter).getSemanticKey() == (concreteLater ? integer : dynamicType).getSemanticKey(),
				"generic input fallback lost later constraints or explicit Dynamic evidence");
		}
		Sys.println("DIRECT_CALL_DYNAMIC_EVIDENCE:PASS");
	}

	/** Dynamic consumers supply a publication fallback, never an early alias-unification result. */
	static function dynamicUseContracts():Void {
		final destinations = new TyInferenceSolver("Main.dynamicDestinations");
		final input = destinations.freshOmittedParameter();
		final field = destinations.field(input, "value");
		final operation = destinations.freshUntypedResult();
		check(!destinations.isUnresolvedInput(field), "unsealed inference supplied final input evidence");
		destinations.observeDynamicUse(input, true);
		destinations.observeDynamicUse(field, true);
		destinations.observeDynamicUse(operation, true);
		check(destinations.previewDynamicUses(field).isUnknown(), "Dynamic destination invented an input field annotation");
		check(destinations.previewDynamicUses(operation).isDynamic(), "untyped operation lost its Dynamic consumer carrier");
		destinations.seal();
		check(destinations.isUnresolvedInput(field), "sealed input projection lost its origin");
		check(!destinations.isUnresolvedInput(operation), "untyped operation forged omitted input evidence");
		check(!destinations.isUnresolvedInput(Known(TyType.unknown())), "missing type fact forged omitted input evidence");
		check(destinations.published(field).isUnknown(), "Dynamic destination changed the input field at seal");
		check(destinations.published(operation).isDynamic(), "untyped operation lost its Dynamic carrier at seal");

		final solver = new TyInferenceSolver("Main.dynamicUse");
		final pending = solver.freshUntypedResult();
		solver.observeDynamicUse(pending);
		check(solver.preview(pending).isUnknown(), "Dynamic use solved inference before later uses");
		check(solver.constrain(pending, Known(TyType.fromHintText("Int"))), "later concrete context was lost");
		check(!solver.constrain(pending, Known(TyType.fromHintText("String"))), "Dynamic consumer erased an alias conflict");
		solver.seal();
		check(solver.published(pending).getSemanticKey() == "primitive:Int", "Dynamic fallback replaced a concrete solution");
		rejects(() -> solver.observeDynamicUse(pending), "already sealed");

		final aliases = new TyInferenceSolver("Main.dynamicAliases");
		final first = aliases.freshUntypedResult();
		final second = aliases.freshUntypedResult();
		aliases.observeDynamicUse(first);
		check(aliases.constrain(first, second), "alias setup failed");
		aliases.seal();
		check(aliases.published(first).isDynamic() && aliases.published(second).isDynamic(), "fallback lost its final alias root");

		final rollback = new TyInferenceSolver("Main.dynamicRollback");
		final untouched = rollback.freshUntypedResult();
		final discarded = rollback.fork();
		discarded.observeDynamicUse(untouched);
		rollback.seal();
		check(rollback.published(untouched).isUnknown(), "discarded candidate leaked Dynamic publication");

		final record = new TyInferenceSolver("Main.dynamicFields");
		final object = record.freshUntypedResult();
		record.observeDynamicUse(object);
		final count = record.field(object, "count");
		final label = record.field(object, "label");
		check(record.constrain(count, Known(TyType.fromHintText("Int"))), "field setup failed");
		record.seal();
		check(record.published(object).isAnonymous(), "Dynamic fallback erased required fields");
		check(record.published(count).getSemanticKey() == "primitive:Int"
			&& record.published(label).isDynamic(), "field fallback replaced concrete evidence");

		final foreign = new TyInferenceSolver("Other.dynamicUse");
		final local = new TyInferenceSolver("Main.dynamicOwnership");
		rejects(() -> local.observeDynamicUse(foreign.freshUntypedResult()), "another owner");
		final required = local.fresh();
		local.observeDynamicUse(Known(TyType.unknown()));
		rejects(() -> local.seal(), "remains unsolved");
		Sys.println("DYNAMIC_CONTEXT_INFERENCE:PASS");
	}

	/** Empty literals defer their fallback; later concrete evidence and independent arrays remain distinct. */
	static function emptyArrayContracts():Void {
		final solver = new TyInferenceSolver("Main.emptyArrays");
		final pending = solver.freshEmptyArrayElement();
		final unused = solver.freshEmptyArrayElement();
		check(solver.preview(pending).isUnknown(), "empty array chose Dynamic before later uses");
		final rejected = solver.fork();
		check(rejected.constrain(pending, Known(TyType.fromHintText("String"))), "candidate could not constrain empty array");
		check(solver.constrain(pending, Known(TyType.fromHintText("Int"))), "discarded candidate changed empty array");
		solver.seal();
		check(solver.published(pending).getSemanticKey() == "primitive:Int", "empty fallback replaced later Int evidence");
		check(solver.published(unused).isDynamic(), "independent unused array lost its default element type");
		Sys.println("EMPTY_ARRAY_SOLVER:PASS");
	}

	static function main():Void {
		nullableInputContracts();
		receiverCallOwnership();
		emptyArrayContracts();
		dynamicUseContracts();
		directCallConstraints();
		nominalMemberContracts();
		structuralContracts();
		callableContracts();
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
		check(structural.constrain(Function([intTerm], Nullable(result), TyType.functionType([intType], TyType.unknown())),
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

	/** Inference can solve child types without changing which arguments a caller may omit or spread. */
	static function callableContracts():Void {
		final solver = new TyInferenceSolver("Main.callableContracts");
		for (hint in ["(?item:Int)->Int", "(...items:Int)->Int"]) {
			final source = TyType.fromHintText(hint);
			final restored = solver.requireSolved(TyInferenceSolver.fromType(source));
			check(restored.getSemanticKey() == source.getSemanticKey(), "inference erased callable contract: " + hint);
			check(restored.getFunctionParameters()[0].name == source.getFunctionParameters()[0].name, "inference erased a callable parameter name");
			check(!solver.constrain(TyInferenceSolver.fromType(source), TyInferenceSolver.fromType(TyType.fromHintText("Int->Int"))),
				"exact unification accepted different callable omission or rest rules");
		}
	}
}
