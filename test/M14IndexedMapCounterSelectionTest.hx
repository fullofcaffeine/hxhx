import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	Regression for the three original `Map<String, MapCounter>` updates in
	`test/js_map_provider/Main.hx`, typed against the real Map providers.

	Why: `Map.get` returns `Null<MapCounter>` while `Map.set` accepts and returns
	`MapCounter`. Upstream Haxe types indexed `++`/`--` over the Int storage of the
	nullable abstract (no declared unary helper), and `+=` calls the authored
	`MapCounter.compound` with the raw nullable getter as its first argument.
	Earlier helper selection rejected all three before any projection.

	What: each update's getter, computed result, actual setter input, expected
	setter parameter and static result are asserted separately, from expected
	strings written in this test rather than derived from each other.
 */
@:access(TyperStage)
@:access(TyFunctionInference)
@:access(TyIndexedComputedResult)
@:access(TyIndexedUpdateOutcome)
@:access(TyIndexedNullableAbstractOperand)
@:access(TyAbstractBinaryArgument)
class M14IndexedMapCounterSelectionTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** One loaded copy of the unchanged fixture, its typed providers and its source occurrences. */
	static function loadOriginal():{
		index:TyperIndex,
		context:TyperContext,
		hints:haxe.ds.StringMap<String>,
		updates:Array<HxExpr>,
		plain:HxExpr
	} {
		final path = "test/js_map_provider/Main.hx";
		final source = sys.io.File.getContent(path);
		final args = Stage1Args.parse(["-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: ["test/js_map_provider"],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final provider = new CompilerSourceProvider();
		final modules = ResolverStage.parseProjectRoots(paths, ["Main"], defines, provider);
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, defines, index, null, true, provider);
		loader.markResolvedAlready(modules);
		final pending = modules.copy();
		final required = [
			"Class",
			"StdTypes",
			"Map",
			"haxe.ds.Map",
			"haxe.Constraints",
			"haxe.ds.EnumValueMap",
			"haxe.ds.ObjectMap",
			"haxe.ds.IntMap",
			"haxe.ds.StringMap"
		];
		final typed = new Array<String>();
		var cursor = 0;
		while (cursor < pending.length) {
			final module = pending[cursor++];
			if (required.contains(module.modulePath)) {
				TyperStage.typeResolvedModule(module, index, loader, true);
				typed.push(module.modulePath);
			}
			for (discovered in loader.drainNewModules())
				pending.push(discovered);
		}
		for (name in required)
			require(typed.contains(name), "real provider body was not typed: " + name);
		final original = modules.filter(module -> module.modulePath == "Main")[0];
		require(original.parsed.getSource() == source, "original Main source identity changed");
		final declaration = original.parsed.getDecl();
		final owner = HxModuleDecl.getClasses(declaration).filter(owner -> HxClassDecl.getName(owner) == "Main")[0];
		final fn = HxClassDecl.getFunctions(owner).filter(fn -> HxFunctionDecl.getName(fn) == "main")[0];
		final context = new TyperContext(index, original.filePath, "Main", HxModuleDecl.getPackagePath(declaration), HxModuleDecl.getDirectives(declaration),
			"Main", loader);
		final hints = new haxe.ds.StringMap<String>();
		final updates = new Array<HxExpr>();
		var plain:Null<HxExpr> = null;
		function expression(value:HxExpr):Void {
			switch value {
				case EUnop(_, _, EArrayAccess(EIdent("counters"), _)):
					updates.push(value);
				case EUnop(_, _, EIdent("plain")):
					plain = value;
				case EBinop("+=", EArrayAccess(EIdent("counters"), _), _):
					updates.push(value);
				case EBinop(_, left, right):
					expression(left);
					expression(right);
				case EParenthesized(inner, _):
					expression(inner);
				case _: // Other authored operations are not part of this regression.
			}
		}
		for (statement in HxFunctionDecl.getBody(fn))
			switch statement {
				case SVar(name, hint, initial, _, _):
					if (name == "counters" || name == "plain")
						hints.set(name, hint);
					if (initial != null)
						expression(initial);
				case SIf(condition, _, _, _):
					expression(condition);
				case _:
			}
		require(updates.length == 3, "expected the original postfix, prefix and compound MapCounter updates, found " + updates.length);
		require(plain != null, "original ordinary MapCounter postfix control is absent");
		return {
			index: index,
			context: context,
			hints: hints,
			updates: updates,
			plain: plain
		};
	}

	/** A fresh `Main.main` scope declares the original locals from their authored hints. */
	static function scope(original:{context:TyperContext, hints:haxe.ds.StringMap<String>}):TyFunctionEnv {
		final environment = new TyFunctionEnv("Main.main", [], [], TyType.fromHintText("Void"), TyType.unknown(), "Main.main", null, false, 0, true,
			new TyControlScope("Main.main", "map-counter-regression"));
		for (name => hint in original.hints)
			environment.declareLocal(name, TyperStage.typeFromHintInContext(hint, original.context, environment));
		return environment;
	}

	static function originalApplications():Void {
		final original = loadOriginal();
		final counter = original.index.getAbstractByFullName("Main.MapCounter");
		require(counter != null, "real MapCounter declaration is absent");
		final compound = counter.getBinaryOperators("+=");
		require(compound.length == 1, "MapCounter must declare exactly one compound operator");
		final nullableCounter = "nullable:nominal:Main.MapCounter";
		final plainCounter = "nominal:Main.MapCounter";
		final expected = [
			{label: "postfix", computed: nullableCounter, setterActual: nullableCounter},
			{label: "prefix", computed: nullableCounter, setterActual: nullableCounter},
			{label: "compound", computed: plainCounter, setterActual: plainCounter}
		];
		final parameter = TyType.nominal(counter.getIdentity(), [], "MapCounter");
		for (position in 0...original.updates.length) {
			final environment = scope(original);
			final outcome = TyperStage.selectIndexedUpdate(original.updates[position], environment, original.context, HxPos.unknown());
			final label = expected[position].label;
			final query = outcome.selection.query;
			final getter = environment.getInference().expressionType(query.getterSource, TyType.unknown(), environment);
			require(getter.getSemanticKey() == nullableCounter, label + " getter is " + getter.getSemanticKey());
			require(outcome.computed.getType(environment).getSemanticKey() == expected[position].computed, label + " computed result changed");
			require(outcome.placeResult.getType(environment).getSemanticKey() == expected[position].computed, label + " place changed its actual result");
			require(outcome.setterInput.getType(environment).getSemanticKey() == expected[position].setterActual, label + " setter input changed");
			require(outcome.setterInput.validatesParameter(parameter), label + " lost its selected MapCounter setter parameter");
			require(!outcome.setterInput.validatesParameter(TyType.nullable(parameter)), label + " setter parameter became nullable");
			require(outcome.getStaticType(environment).getSemanticKey() == plainCounter, label + " static result changed");
			require(outcome.selection.getter.declaration.getSignature().getName() == "get", label + " selected another getter");
			require(outcome.selection.setter.declaration.getSignature().getName() == "arrayWrite", label + " selected another setter");
			require(outcome.payload == (position == 0 ? OldGetter : SetterValue), label + " changed its runtime payload owner");
			require(environment.getInference().indexedUpdateOutcome(original.updates[position], environment) == outcome,
				label + " outcome was not published with its transaction");
			if (position < 2) {
				unaryEvidence(label, outcome, environment, counter);
			} else {
				compoundEvidence(outcome, environment, compound[0].getDeclaration());
			}
		}
		Sys.println("INDEXED_MAP_COUNTER:PASS original_applications");
	}

	/** Unary updates compute over Int storage; no declared MapCounter helper is called or recorded. */
	static function unaryEvidence(label:String, outcome:TyIndexedUpdateOutcome, environment:TyFunctionEnv, counter:TyAbstractInfo):Void {
		require(outcome.selection.binary == null, label + " selected a declared MapCounter operator");
		for (call in environment.getInference().directCalls)
			require(call.expression != outcome.selection.query.computedSource, label + " recorded a helper call for its numeric step");
		final operand = switch outcome.computed.evidence {
			case CheckedBuiltin(operands, step) if (step != null && step.nullableOperand != null):
				require(operands.length == 1
					&& operands[0].source == outcome.selection.query.getterSource, label + " step lost its getter operand");
				require(step.owner == counter
					&& step.storage.getSemanticKey() == "primitive:Int", label + " step lost MapCounter Int storage");
				step.nullableOperand;
			case _: throw label + " computed result is not the checked Int-storage step";
		};
		require(operand.query == outcome.selection.query
			&& operand.originalType.getSemanticKey() == "nullable:nominal:Main.MapCounter"
			&& operand.applied.getSemanticKey() == "nominal:Main.MapCounter",
			label
			+ " operand lost its exact getter view");
		final derived = switch outcome.placeResult.evidence {
			case CheckedPlace(input, expected, PlaceUnaryNullableAbstract(result)):
				require(input == outcome.computed
					&& result.computed == outcome.computed
					&& result.operand == operand
					&& expected.getSemanticKey() == "nullable:nominal:Main.MapCounter",
					label
					+ " place lost its exact computed predecessor");
				result;
			case _: throw label + " place does not carry the derived unary permission";
		};
		switch outcome.setterInput.evidence {
			case CheckedArgument(input, expected, ArgumentUnaryNullableAbstract(result, _)):
				require(input == outcome.placeResult && result == derived && expected.getSemanticKey() == "nominal:Main.MapCounter",
					label + " setter permission does not follow its own place");
			case _:
				throw label + " setter input lost its unary admission";
		}
	}

	/** `+=` calls exactly `MapCounter.compound` with the raw nullable getter as source-left argument. */
	static function compoundEvidence(outcome:TyIndexedUpdateOutcome, environment:TyFunctionEnv, declaration:TyDeclarationInfo):Void {
		final bound = outcome.selection.binary;
		require(bound != null
			&& bound.getOperatorInfo().getDeclaration() == declaration
			&& declaration.getSignature().getName() == "compound"
			&& declaration.getIsStatic()
			&& !bound.getReverseArguments()
			&& !bound.getRequiresWriteback()
			&& bound.getResultConversion() == null,
			"compound update did not select Main.MapCounter.compound directly");
		final left = bound.getSourceLeftArgument();
		switch left.evidence {
			case IndexedNullableAdmission(operand, expected):
				require(operand.query == outcome.selection.query && expected.getSemanticKey() == "nominal:Main.MapCounter",
					"compound admission belongs to another query or parameter");
			case _:
				throw "compound first argument is not the raw nullable admission";
		}
		require(left.getActualType().getSemanticKey() == "nullable:nominal:Main.MapCounter", "compound first argument lost its raw nullable type");
		rejects(() -> left.requireConversion(), "ordinary lowering could execute the nullable admission", "no executable conversion");
		final right = bound.getSourceRightArgument();
		require(right.requireConversion().getActualType().getSemanticKey() == "primitive:Int"
			&& right.getExpectedType().getSemanticKey() == "primitive:Int",
			"compound right argument lost its Int conversion");
		final callable = environment.getInference().directCallType(outcome.selection.query.computedSource, declaration);
		require(callable != null
			&& callable.getFunctionReturn().getSemanticKey() == "nominal:Main.MapCounter", "compound call result changed");
		switch outcome.placeResult.evidence {
			case CheckedPlace(input, expected, PlaceSelectedAbstractResult):
				require(input == outcome.computed && expected.getSemanticKey() == "nullable:nominal:Main.MapCounter",
					"compound place lost its exact selected-call predecessor");
			case _:
				throw "compound place is not the selected abstract result admission";
		}
		switch outcome.setterInput.evidence {
			case CheckedArgument(input, expected, ArgumentAssignment):
				require(input == outcome.placeResult
					&& expected.getSemanticKey() == "nominal:Main.MapCounter", "compound setter lost its place");
			case _:
				throw "compound setter input borrowed another admission";
		}
	}

	/** Require rejection; when `reason` is given, the diagnostic must name that exact failed check. */
	static function rejects(action:() -> Void, message:String, ?reason:String):Void {
		var diagnostic:Null<String> = null;
		try {
			action();
		} catch (error:String) {
			diagnostic = error;
		} catch (error:TyperError) {
			diagnostic = error.toString();
		}
		require(diagnostic != null, message);
		if (Sys.getEnv("HXHX_TRACE_REJECTIONS") == "1")
			Sys.println("REJECTED " + message + " :: " + diagnostic);
		require(reason == null || diagnostic.indexOf(reason) >= 0, message + " for another reason: " + diagnostic);
	}

	/** Copy one update query's sources into new, unregistered result occurrences. */
	static function unregisteredQuery(query:TyIndexedUpdateSelection.TyIndexedUpdateQuery):TyIndexedUpdateSelection.TyIndexedUpdateQuery {
		function fresh():HxExpr
			return switch query.source {
				case EUnop(op, fixity, inner): EUnop(op, fixity, inner);
				case EBinop(op, left, right): EBinop(op, left, right);
				case _: throw "query source changed";
			};
		return new TyIndexedUpdateSelection.TyIndexedUpdateQuery({
			owner: query.owner,
			source: query.source,
			kind: query.kind,
			getterSource: query.getterSource,
			computedSource: fresh(),
			placeResultSource: fresh(),
			setterInputSource: fresh(),
			setterSource: fresh()
		});
	}

	/** Rebuild a completed outcome with one substituted part; validation must reject it. */
	static function rebuild(outcome:TyIndexedUpdateOutcome, environment:TyFunctionEnv, index:TyperIndex, ?placeResult:TyIndexedComputedResult,
			?setterInput:TyIndexedComputedResult, ?signature:TyFunSig):Void {
		new TyIndexedUpdateOutcome({
			selection: outcome.selection,
			computed: outcome.computed,
			placeResult: placeResult == null ? outcome.placeResult : placeResult,
			setterInput: setterInput == null ? outcome.setterInput : setterInput,
			admission: {
				declaration: outcome.admission.declaration,
				signature: signature == null ? outcome.admission.signature : signature,
				order: outcome.admission.order,
				sources: outcome.admission.sources,
				types: outcome.admission.types,
				inputTrial: outcome.admission.inputTrial
			},
			environment: environment,
			index: index,
			finalTypes: outcome.finalTypes
		});
	}

	/**
		Unary setter permission is derived only from its own registered numeric step and
		place. Equal nullable types, other occurrences and selected calls cannot reuse it.
	 */
	static function unaryDerivationBoundaries():Void {
		final original = loadOriginal();
		final counter = original.index.getAbstractByFullName("Main.MapCounter");
		final counterType = TyType.nominal(counter.getIdentity(), [], "MapCounter");
		final nullableCounter = TyType.nullable(counterType);
		final postfixScope = scope(original);
		final postfix = TyperStage.selectIndexedUpdate(original.updates[0], postfixScope, original.context, HxPos.unknown());
		final prefixScope = scope(original);
		final prefix = TyperStage.selectIndexedUpdate(original.updates[1], prefixScope, original.context, HxPos.unknown());
		final compoundScope = scope(original);
		final compound = TyperStage.selectIndexedUpdate(original.updates[2], compoundScope, original.context, HxPos.unknown());
		final query = postfix.selection.query;
		final unchanged = postfixScope.getInference().unchangedFacts();

		// A builtin of the same Null<MapCounter> type without numeric-step evidence.
		final substitute = TyIndexedComputedResult.builtin(query, nullableCounter, [{source: query.getterSource, type: nullableCounter}]);
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractPlace(substitute, nullableCounter, postfixScope),
			"substituted equal-type builtin derived unary permission", "exact numeric-step result");
		// A selected compound call cannot be treated as the unary numeric step.
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractPlace(compound.computed, nullableCounter, compoundScope),
			"selected call was accepted as a unary numeric builtin", "exact numeric-step result");
		// Another update's computation is foreign to this scope.
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractPlace(prefix.computed, nullableCounter, postfixScope),
			"foreign computed result derived unary permission", "changed its source, term or applied owner");
		// The identical nullable place without the derived permission cannot authorize the setter.
		final plainPlace = TyIndexedComputedResult.admittedPlace(postfix.computed, nullableCounter);
		require(!plainPlace.admitsUnaryAbstractArgument(counterType), "getter-shaped place exposed setter permission");
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractArgument(plainPlace, counterType, postfixScope),
			"equal-type place without derived permission admitted the setter", "exact computed unary predecessor");
		// A place from another update cannot be the predecessor here.
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractArgument(prefix.placeResult, counterType, postfixScope),
			"foreign place predecessor admitted the setter", "changed its source, term or applied owner");
		// The derived setter permission is only for the exact applied MapCounter parameter.
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractArgument(postfix.placeResult, nullableCounter, postfixScope),
			"unary admission accepted a nullable parameter as its applied owner", "exact computed unary predecessor");
		// A valid re-derivation from the same computation is still not the outcome's own place.
		final rederived = TyIndexedComputedResult.admittedUnaryAbstractPlace(postfix.computed, nullableCounter, postfixScope);
		final rederivedSetter = TyIndexedComputedResult.admittedUnaryAbstractArgument(rederived, counterType, postfixScope);
		rejects(() -> rebuild(postfix, postfixScope, original.index, null, rederivedSetter), "setter from another place object was accepted",
			"another derivation chain");
		rejects(() -> rebuild(postfix, postfixScope, original.index, null, prefix.setterInput), "foreign setter input was accepted",
			"foreign result or declaration evidence");
		// Derivation before registration: same getter view, unregistered computed occurrence.
		final unregistered = unregisteredQuery(query);
		final operand = TyIndexedNullableAbstractOperand.select(unregistered, nullableCounter, postfixScope, original.index);
		require(operand != null, "control lost the checked getter view");
		final early = TyIndexedComputedResult.builtin(unregistered, nullableCounter, [{source: query.getterSource, type: nullableCounter}], {
			owner: counter,
			applied: operand.applied,
			storage: operand.storage,
			index: original.index,
			nullableOperand: operand
		});
		rejects(() -> TyIndexedComputedResult.admittedUnaryAbstractPlace(early, nullableCounter, postfixScope),
			"unregistered computed result derived unary permission", "registered computation");
		// A late, incompatible setter parameter cannot reuse the retained admission.
		final signature = postfix.admission.signature;
		final types = signature.getArgs().copy();
		types[types.length - 1] = TyType.fromHintText("Bool");
		rejects(() -> rebuild(postfix, postfixScope, original.index, null, null,
			new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames(), types, signature.getArgOptional(), signature.getArgRest(),
				signature.getReturnType(), signature.getPos())),
			"late incompatible setter parameter was accepted", "differs from its selected setter parameter");
		require(unchanged(), "rejected unary derivations changed published inference");
		postfix.getStaticType(postfixScope);

		// A changed computed term invalidates the place and setter chain.
		final inference = prefixScope.getInference();
		final computedSource = prefix.selection.query.computedSource;
		var replaced = 0;
		for (offset in 0...inference.occurrences.length) {
			final entry = inference.occurrences[offset];
			if (entry.expression == computedSource) {
				inference.occurrences[offset] = {
					expression: entry.expression,
					term: TyInferenceSolver.fromType(nullableCounter),
					sourceFingerprint: entry.sourceFingerprint
				};
				replaced++;
			}
		}
		require(replaced == 1, "control requires the one registered computed occurrence");
		rejects(() -> prefix.placeResult.validate(prefixScope), "changed computed term kept its place permission", "computed occurrence or term");
		rejects(() -> prefix.getStaticType(prefixScope), "changed computed term kept the completed outcome", "computed occurrence or term");
		Sys.println("INDEXED_MAP_COUNTER:PASS unary_derivation_boundaries");
	}

	/**
		Authored provider whose getter returns `Null<Counter>` and whose setter accepts
		`value`. `Counter` and `Other` both store Int, so a selection that matched by
		storage instead of by the exact applied abstract would be visible here.
	 */
	static function provider(counterBody:String, otherBody:String, ?value:String):String {
		return 'abstract Counter(Int) from Int to Int{'
			+ counterBody
			+ '}abstract Other(Int){'
			+ otherBody
			+ '}'
			+ 'abstract Slots(Array<Counter>){public function new();@:arrayAccess public function read(index:Int):Null<Counter>;'
			+ '@:arrayAccess public function write(index:Int,value:'
			+ (value == null ? "Counter" : value)
			+ '):Counter;}'
			+ 'class Main{static function main():Void{}}';
	}

	static function fixture(source:String, ?locals:Map<String, String>):{
		environment:TyFunctionEnv,
		index:TyperIndex,
		context:TyperContext
	} {
		final parsed = ParserStage.parse(source, "Main.hx");
		final index = TyperIndex.build([new ResolvedModule("Main", "Main.hx", parsed)]);
		final owner = index.getAbstractByFullName("Main.Slots");
		require(owner != null, "authored indexed provider is absent");
		final environment = new TyFunctionEnv("Main.main", [], [], TyType.fromHintText("Void"), TyType.unknown(), "Main.main", null, false, 0, true,
			new TyControlScope("Main.main", haxe.crypto.Sha256.encode(source)));
		final allocation:HxExpr = ENew("Slots", []);
		final inferred = environment.getInference().construct(allocation, TyType.nominal(owner.getIdentity(), []), owner.getTypeParameterIds().length);
		final local = environment.declareLocal("slots", inferred);
		final term = environment.getInference().sourceTerm(allocation, environment);
		if (term != null)
			environment.getInference().recordLocal(local, term);
		final context = new TyperContext(index, "Main.hx", "Main", "", [], "Main");
		if (locals != null)
			for (name => hint in locals)
				environment.declareLocal(name, TyperStage.typeFromHintInContext(hint, context, environment));
		return {environment: environment, index: index, context: context};
	}

	static function select(source:String, expression:String, ?locals:Map<String, String>):{
		outcome:TyIndexedUpdateOutcome,
		environment:TyFunctionEnv,
		index:TyperIndex,
		original:HxExpr
	} {
		final setup = fixture(source, locals);
		final original = HxParser.parseExprText(expression);
		return {
			outcome: TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown()),
			environment: setup.environment,
			index: setup.index,
			original: original
		};
	}

	/** Selection fails and leaves the parent inference and method-input state untouched. */
	static function rejectsUnpublished(source:String, expression:String, message:String, reason:String, ?locals:Map<String, String>):Void {
		final setup = fixture(source, locals);
		final parent = setup.environment.getInference();
		final unchanged = parent.unchangedFacts();
		final revision = setup.index.getMethodInputs().getRevision();
		final original = HxParser.parseExprText(expression);
		rejects(() -> TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown()), message, reason);
		require(unchanged() && setup.index.getMethodInputs().getRevision() == revision, message + " published candidate facts or inputs");
		require(parent.sourceTerm(original, setup.environment) == null && parent.indexedUpdateOutcome(original, setup.environment) == null,
			message + " published an original result or outcome");
	}

	/** Which source operand carries the raw getter admission, checked from the exact tuple. */
	static function requireAdmissionAt(result:{outcome:TyIndexedUpdateOutcome}, label:String, name:String, isStatic:Bool, reversed:Bool):Void {
		final outcome = result.outcome;
		final bound = outcome.selection.binary;
		require(bound != null
			&& bound.getOperatorInfo().getDeclaration().getSignature().getName() == name, label + " selected another declaration");
		require(bound.getOperatorInfo().getDeclaration().getIsStatic() == isStatic, label + " changed static/instance kind");
		require(bound.getReverseArguments() == reversed, label + " changed declaration orientation");
		final left = bound.getSourceLeftArgument();
		final right = bound.getSourceRightArgument();
		require(switch left.evidence {
			case IndexedNullableAdmission(operand, expected): operand.query == outcome.selection.query && expected.getSemanticKey() == "nominal:Main.Counter";
			case _: false;
		}, label + " source-left getter lost its admission");
		require(left.admitsSource(outcome.selection.query.getterSource), label + " admission left its getter occurrence");
		final rhs = switch outcome.selection.query.source {
			case EBinop(_, _, value): value;
			case _: throw "compound source changed";
		};
		require(!left.admitsSource(rhs), label + " admission moved to the right operand");
		require(right.requireConversion() != null, label + " right operand lost its executable conversion");
		final sources = reversed ? [rhs, outcome.selection.query.getterSource] : [outcome.selection.query.getterSource, rhs];
		final plans = reversed ? [right, left] : [left, right];
		final types = plans.map(plan -> plan.getActualType());
		@:privateAccess TyIndexedUpdateOperation.validateInputs({
			query: outcome.selection.query,
			binding: bound,
			sources: sources,
			types: types,
			plans: plans
		});
		rejects(() -> @:privateAccess TyIndexedUpdateOperation.validateInputs({
			query: outcome.selection.query,
			binding: bound,
			sources: [sources[1], sources[0]],
			types: [types[1], types[0]],
			plans: [plans[1], plans[0]]
		}), label + " swapped source tuples were accepted", "another source position");
		rejects(() -> left.validateSource(rhs, result.outcome.environment), label + " admission validated at the right operand", "another source position");
		require(outcome.computed.getType(outcome.environment).getSemanticKey() == "nominal:Main.Counter", label + " call result changed");
		require(outcome.placeResult.getType(outcome.environment).getSemanticKey() == "nominal:Main.Counter", label + " place actual changed");
		require(outcome.setterInput.getType(outcome.environment).getSemanticKey() == "nominal:Main.Counter", label + " setter actual changed");
		require(outcome.getStaticType(outcome.environment).getSemanticKey() == "nominal:Main.Counter", label + " static result changed");
	}

	static function operatorOrientation():Void {
		final other = ["rhs" => "Other"];
		requireAdmissionAt(select(provider('@:op(a += b) public static function add(a:Counter,b:Int):Counter return a;', ''), "slots[0] += 2"),
			"static direct", "add", true, false);
		requireAdmissionAt(select(provider('', '@:commutative @:op(a += b) public static function mix(a:Other,b:Counter):Counter return b;'),
			"slots[0] += rhs", other),
			"static reversed", "mix", true, true);
		requireAdmissionAt(select(provider('@:op(a += b) public function inc(b:Int):Counter return this;', ''), "slots[0] += 2"), "instance direct", "inc",
			false, false);
		requireAdmissionAt(select(provider('', '@:commutative @:op(a += b) public function take(b:Counter):Counter return b;'), "slots[0] += rhs", other),
			"instance reversed", "take", false, true);
		// An existing executable conversion is tried first and still wins over the admission.
		final converted = select(provider('@:op(a += b) public static function keep(a:Dynamic,b:Counter):Counter return b;', ''), "slots[0] += rhs",
			["rhs" => "Counter"]);
		final plan = converted.outcome.selection.binary.getSourceLeftArgument().requireConversion();
		require(plan.getActualType().getSemanticKey() == "nullable:nominal:Main.Counter" && plan.getExpectedType().isDynamic(),
			"existing Dynamic parameter conversion lost its executable plan");
		require(converted.outcome.selection.binary.getOperatorInfo().getDeclaration().getSignature().getName() == "keep",
			"executable conversion control selected another declaration");
		Sys.println("INDEXED_MAP_COUNTER:PASS operator_orientation");
	}

	static function operatorNegatives():Void {
		rejectsUnpublished(provider('', '@:op(a += b) public static function wrong(a:Other,b:Other):Counter return 0;'), "slots[0] += rhs",
			"same-storage different abstract parameter was admitted", "No applicable abstract binary operator", ["rhs" => "Other"]);
		rejectsUnpublished(provider('@:op(a += b) public static function both(a:Counter,b:Counter):Counter return a;', ''), "slots[0] += rhs",
			"nullable right operand borrowed getter admission", "No applicable abstract binary operator", ["rhs" => "Null<Counter>"]);
		final box = 'abstract Box<T>(Int){@:op(a += b) public static function bump(a:Box<Int>,b:Int):Box<Int> return a;}'
			+ 'abstract Slots(Array<Box<String>>){public function new();@:arrayAccess public function read(index:Int):Null<Box<String>>;'
			+ '@:arrayAccess public function write(index:Int,value:Box<String>):Box<String>;}class Main{static function main():Void{}}';
		rejectsUnpublished(box, "slots[0] += 2", "wrong generic application was admitted", "No applicable abstract binary operator");
		final generic = 'abstract Gen<T>(Int){@:op(a += b) public static function grow(a:Gen<T>,b:Int):Gen<T> return a;}'
			+ 'abstract Slots(Array<Gen<Int>>){public function new();@:arrayAccess public function read(index:Int):Null<Gen<Int>>;'
			+ '@:arrayAccess public function write(index:Int,value:Gen<Int>):Gen<Int>;}class Main{static function main():Void{}}';
		rejectsUnpublished(generic, "slots[0] += 2", "generic operator acquired owner specialization", "Generic abstract binary operator is not supported yet");
		final ordinary = fixture(generic);
		final applied = TyType.nominal(ordinary.index.getAbstractByFullName("Main.Gen").getIdentity(), [TyType.fromHintText("Int")]);
		rejects(() -> TyAbstractBinaryBinding.select(ordinary.index, applied, TyType.fromHintText("Int"), "+=", "Main.hx", HxPos.unknown()),
			"ordinary generic operator rejection changed", "Generic abstract binary operator is not supported yet");
		require(TyAbstractBinaryBinding.select(ordinary.index, TyType.nullable(applied), TyType.fromHintText("Int"), "+=", "Main.hx", HxPos.unknown()) == null,
			"ordinary binary lookup started unwrapping nullable abstracts");
		// Late failures after a successful getter/operator choice publish nothing.
		final compound = '@:op(a += b) public static function add(a:Counter,b:Int):Counter return a;';
		rejectsUnpublished(provider(compound, '', "Other"), "slots[0] += 2", "incompatible compound setter was accepted", "indexed setter");
		rejectsUnpublished(provider('', '', "Other"), "slots[0]++", "incompatible unary setter was accepted", "indexed setter");
		rejectsUnpublished(provider('', '', "Bool"), "++slots[0]", "unrelated unary setter was accepted", "indexed setter");
		// One update's admission cannot validate at another update's getter.
		final first = select(provider(compound, ''), "slots[0] += 2");
		final second = select(provider(compound, ''), "slots[0] += 2");
		final admission = first.outcome.selection.binary.getSourceLeftArgument();
		require(!admission.admitsSource(second.outcome.selection.query.getterSource), "admission accepted a foreign getter occurrence");
		rejects(() -> admission.validateSource(second.outcome.selection.query.getterSource, second.environment), "foreign query admission validated",
			"changed its source, term or applied owner");
		Sys.println("INDEXED_MAP_COUNTER:PASS operator_negatives");
	}

	/** The ordinary `plain++` control still selects the authored `post` helper. */
	static function ordinaryPostfix():Void {
		final original = loadOriginal();
		final counter = original.index.getAbstractByFullName("Main.MapCounter");
		final counterType = TyType.nominal(counter.getIdentity(), [], "MapCounter");
		final selected = TyAbstractUnaryBinding.select(original.index, counterType, Increment, Postfix, original.context.getFilePath(), HxPos.unknown());
		require(selected != null && selected.getDeclaration().getSignature().getName() == "post", "ordinary MapCounter postfix lost post");
		final environment = scope(original);
		final type = TyperStage.inferExprType(original.plain, environment, original.context, HxPos.unknown());
		require(type.getSemanticKey() == "nominal:Main.MapCounter", "ordinary MapCounter postfix changed its type");
		require(TyAbstractUnaryBinding.select(original.index, TyType.nullable(counterType), Increment, Postfix, original.context.getFilePath(),
			HxPos.unknown()) == null,
			"ordinary unary lookup started unwrapping nullable abstracts");
		Sys.println("INDEXED_MAP_COUNTER:PASS ordinary_postfix");
	}

	static function main():Void {
		originalApplications();
		unaryDerivationBoundaries();
		ordinaryPostfix();
		operatorOrientation();
		operatorNegatives();
		Sys.println("INDEXED_MAP_COUNTER:PASS");
	}
}
