/** Helper selection uses retained source facts while public indexed-update admission remains disabled. */
@:access(TyperStage)
@:access(TyFunctionInference)
@:access(TyIndexedComputedResult)
@:access(TyIndexedUpdateOutcome)
class M14IndexedUpdateSelectionTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function fixture(source:String, ?body:HxExpr):{
		environment:TyFunctionEnv,
		index:TyperIndex,
		context:TyperContext
	} {
		final parsed = ParserStage.parse(source, "Main.hx");
		final index = TyperIndex.build([new ResolvedModule("Main", "Main.hx", parsed)]);
		final owner = index.getAbstractByFullName("Main.Slots");
		require(owner != null, "authored indexed provider is absent");
		final revision = body == null ? haxe.crypto.Sha256.encode(source) : TypedBodyFingerprint.exactExpression(body);
		final environment = new TyFunctionEnv("Main.main", [], [], TyType.fromHintText("Void"), TyType.unknown(), "Main.main", null, false, 0, true,
			new TyControlScope("Main.main", revision));
		final allocation:HxExpr = ENew("Slots", []);
		final inferred = environment.getInference().construct(allocation, TyType.nominal(owner.getIdentity(), []), owner.getTypeParameterIds().length);
		final local = environment.declareLocal("slots", inferred);
		final term = environment.getInference().sourceTerm(allocation, environment);
		if (term != null)
			environment.getInference().recordLocal(local, term);
		final context = new TyperContext(index, "Main.hx", "Main", "", [], "Main");
		return {environment: environment, index: index, context: context};
	}

	static function selected(source:String, expression:String):{
		selection:TyIndexedUpdateOutcome,
		environment:TyFunctionEnv,
		index:TyperIndex,
		original:HxExpr
	} {
		final setup = fixture(source);
		final original = HxParser.parseExprText(expression);
		return {
			selection: TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown()),
			environment: setup.environment,
			index: setup.index,
			original: original
		};
	}

	static function rejects(action:() -> Void, message:String):Void {
		var rejected = false;
		try {
			action();
		} catch (_:String) {
			rejected = true;
		} catch (_:TyperError) {
			rejected = true;
		}
		require(rejected, message);
	}

	static function lateGetterAndRollback():Void {
		final prefix = 'abstract Slots<T>(Array<T>){public function new();@:arrayAccess public function read(index:Int):T;';
		final accepted = fixture(prefix + '@:arrayAccess public function write(index:Int,value:T):String;}class Main{static function main():Void{}}');
		final source = HxParser.parseExprText("slots[0] += 2");
		final outcome = TyperStage.selectIndexedUpdate(source, accepted.environment, accepted.context, HxPos.unknown());
		final inference = accepted.environment.getInference();
		final slots:HxExpr = EIdent("slots");
		require(inference.expressionType(slots, TyType.unknown(), accepted.environment).getTypeArguments()[0].getSemanticKey() == "primitive:Int",
			"addition did not solve the original generic getter/receiver child");
		require(outcome.computed.getType(accepted.environment).getSemanticKey() == "primitive:Int", "late getter lost its operation result");
		final before = inference.unchangedFacts();
		final incompatible = TyType.nominal(accepted.index.getAbstractByFullName("Main.Slots").getIdentity(), [TyType.fromHintText("String")]);
		require(!inference.constrain([slots], [incompatible], accepted.environment, accepted.index), "late incompatible receiver was accepted");
		require(before(), "late incompatible constraint changed retained facts");
		require(outcome.getStaticType(accepted.environment).getSemanticKey() == "primitive:String", "late mismatch replaced the setter result");
		final denied = fixture(prefix + '@:arrayAccess public function write(index:Int,value:Bool):String;}class Main{static function main():Void{}}');
		final parent = denied.environment.getInference();
		final unchanged = parent.unchangedFacts();
		final revision = denied.index.getMethodInputs().getRevision();
		final original = HxParser.parseExprText("slots[0] += 2");
		rejects(() -> TyperStage.selectIndexedUpdate(original, denied.environment, denied.context, HxPos.unknown()), "failed setter was accepted");
		require(unchanged()
			&& denied.index.getMethodInputs().getRevision() == revision, "failed setter published candidate facts or inputs");
		require(parent.expressionType(slots, TyType.unknown(), denied.environment).hasUnknownComponent(), "failed setter leaked the getter's Int solution");
		require(parent.sourceTerm(original, denied.environment) == null
			&& parent.indexedUpdateOutcome(original, denied.environment) == null,
			"failed setter published an original result or checked outcome");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS late_getter_and_rollback");
	}

	static function conversionAndIdentity():Void {
		final source = 'abstract Stored(Int){@:from public static function fromInt(value:Int):Stored return cast value;}'
			+ 'abstract Slots(Array<Int>){public function new();@:arrayAccess public function read(index:Int):Int;'
			+ '@:arrayAccess public function write(index:Int,value:Stored):String;}class Main{static function main():Void{}}';
		final result = selected(source, "slots[0] += 2");
		final outcome = result.selection;
		require(outcome.computed.getType(result.environment).getSemanticKey() == "primitive:Int", "conversion replaced raw operator output");
		require(outcome.setterInput.getType(result.environment).getNominalIdentity().getCanonicalName() == "Main.Stored",
			"conversion erased the exact new nominal owner");
		final other = selected(source, "slots[0] += 2");
		final conversion = TyAbstractBinaryConversion.select(result.index, outcome.setterInput.getType(result.environment),
			outcome.placeResult.getType(result.environment));
		rejects(() -> TyIndexedComputedResult.converted(outcome.placeResult, other.selection.selection.query.setterInputSource, conversion),
			"equal-looking foreign conversion output was accepted");
		rejects(() -> TyIndexedComputedResult.converted(outcome.placeResult, outcome.selection.query.computedSource, conversion),
			"swapped conversion output query was accepted");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS conversion_identity");
	}

	static function operatorPositions():Void {
		final source = 'abstract Value(Int){@:op(a += b) public static function plus(a:Value,b:Value):Value return a;}'
			+ 'abstract Slots(Array<Value>){public function new();@:arrayAccess public function read(index:Int):Value;'
			+ '@:arrayAccess public function write(index:Int,value:Value):String;}class Main{static function main():Void{}}';
		final setup = fixture(source);
		final value = TyType.nominal(setup.index.getAbstractByFullName("Main.Value").getIdentity(), []);
		setup.environment.declareLocal("rhs", value);
		final original = HxParser.parseExprText("slots[0] += rhs");
		final outcome = TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown());
		final bound = outcome.selection.binary;
		require(bound != null
			&& bound.getOperatorInfo().getDeclaration().getSignature().getName() == "plus", "operator declaration was not retained");
		final rhs = switch original {
			case EBinop(_, _, right): right;
			case _: throw "missing original RHS";
		};
		final sources = [outcome.selection.query.getterSource, rhs];
		final plans = [bound.getSourceLeftConversion(), bound.getSourceRightConversion()];
		require(plans[0] != plans[1], "control requires distinct equal-looking conversion plans");
		@:privateAccess TyIndexedUpdateOperation.validateInputs({
			query: outcome.selection.query,
			binding: bound,
			sources: sources,
			types: [value, value],
			plans: plans
		});
		rejects(() -> @:privateAccess TyIndexedUpdateOperation.validateInputs({
			query: outcome.selection.query,
			binding: bound,
			sources: sources,
			types: [value, value],
			plans: [plans[1], plans[0]]
		}), "swapped equal-looking plans were accepted");
		rejects(() -> @:privateAccess TyIndexedUpdateOperation.validateInputs({
			query: outcome.selection.query,
			binding: bound,
			sources: [rhs, sources[0]],
			types: [value, value],
			plans: plans
		}), "swapped equal-looking operand occurrences were accepted");
		final reverseSource = 'abstract Value(Float) to Float{@:commutative @:op(a + b) public static function plus(a:Value,b:Float):Float return b;}'
			+ 'abstract Slots(Array<Float>){public function new();@:arrayAccess public function read(index:Int):Float;'
			+ '@:arrayAccess public function write(index:Int,value:Float):String;}class Main{static function main():Void{}}';
		final reverse = fixture(reverseSource);
		reverse.environment.declareLocal("rhs", TyType.nominal(reverse.index.getAbstractByFullName("Main.Value").getIdentity(), []));
		final reversed = TyperStage.selectIndexedUpdate(HxParser.parseExprText("slots[0] += rhs"), reverse.environment, reverse.context, HxPos.unknown());
		require(reversed.selection.binary.getReverseArguments(), "commutative operator lost its exact reversed orientation");
		final instanceSource = 'abstract Value(Int){@:op(a + b) public function plus(b:Int):Value return this;}'
			+ 'abstract Slots(Array<Value>){public function new();@:arrayAccess public function read(index:Int):Value;'
			+ '@:arrayAccess public function write(index:Int,value:Value):String;}class Main{static function main():Void{}}';
		final instance = selected(instanceSource, "slots[0] += 2");
		require(!instance.selection.selection.binary.getOperatorInfo().getDeclaration().getIsStatic(), "instance operator lost its receiver conversion");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS operator_positions");
	}

	static function finalBindingIdentity():Void {
		final source = 'abstract Slots(Array<Int>){public function new();@:arrayAccess public function read(index:Int):Int;'
			+ '@:arrayAccess public function write(index:Int,value:Int):String;}class Main{static function main():Void{}}';
		final result = selected(source, "slots[0] += 2");
		final outcome = result.selection;
		final other = selected(source, "slots[0] += 2");
		function rebuild(selection:TyIndexedUpdateSelection, setterInput:TyIndexedComputedResult,
				admission:TyIndexedUpdateOutcome.TyIndexedSetterAdmission):Void {
			new TyIndexedUpdateOutcome({
				selection: selection,
				computed: outcome.computed,
				placeResult: outcome.placeResult,
				setterInput: setterInput,
				admission: admission,
				environment: result.environment,
				index: result.index,
				finalTypes: outcome.finalTypes
			});
		}
		final unchanged = result.environment.getInference().unchangedFacts();
		rejects(() -> rebuild(outcome.selection, other.selection.setterInput, outcome.admission), "foreign equal-type setter output was accepted");
		final arguments = outcome.selection.setter.getArguments();
		final swapped = new TyIndexedAccessBinding(outcome.selection.query.setterSource, outcome.selection.setter.receiver, [arguments[1], arguments[0]],
			outcome.selection.setter.declaration);
		final wrong = new TyIndexedUpdateSelection({query: outcome.selection.query, getter: outcome.selection.getter, setter: swapped});
		rejects(() -> rebuild(wrong, outcome.setterInput, outcome.admission), "swapped equal-type final arguments were accepted");
		final signature = outcome.admission.signature;
		final types = signature.getArgs().copy();
		types[types.length - 1] = TyType.fromHintText("Bool");
		final incompatible = new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames(), types, signature.getArgOptional(),
			signature.getArgRest(), signature.getReturnType(), signature.getPos());
		rejects(() -> rebuild(outcome.selection, outcome.setterInput, {
			declaration: outcome.admission.declaration,
			signature: incompatible,
			order: outcome.admission.order,
			sources: outcome.admission.sources,
			types: outcome.admission.types,
			inputTrial: outcome.admission.inputTrial
		}), "late selected-parameter mismatch was accepted");
		require(unchanged(), "rejected final argument evidence changed parent inference");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS final_binding_identity");
	}

	static function lexicalOperands():Void {
		final source = 'abstract Slots(Array<Int>){public function new();@:arrayAccess public function read(index:Int):Int;'
			+ '@:arrayAccess public function write(index:Int,value:Int):String;}class Main{static function main():Void{}}';
		final original = HxParser.parseExprText('({var receiverLocal=slots;var receiverClosure=function():Slots return receiverLocal;receiverClosure();})'
			+ '[{var indexLocal:Int=0;var indexClosure=function():Int return indexLocal;indexClosure();}]'
			+ ' += {var rhsLocal:Int=2;var rhsClosure=function():Int return rhsLocal;rhsClosure();}');
		final setup = fixture(source, original);
		final outcome = TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown());
		final locals = setup.environment.getLocals();
		require(locals.length == 7, "authored receiver/index/RHS declarations were traversed more than once");
		require(setup.environment.getInference().sourceFunctions.length == 3, "authored nested closure facts were lost or repeated");
		setup.environment.sealInference();
		final unchanged = setup.environment.getInference().unchangedFacts();
		require(TyperStage.selectIndexedUpdate(original, setup.environment, setup.context, HxPos.unknown()) == outcome,
			"sealed lookup allocated a new selection");
		require(unchanged() && setup.environment.getLocals().length == locals.length, "sealed lookup revisited authored operands");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS lexical_operands");
	}

	static function numericAndAdmissionBoundaries():Void {
		function provider(getter:String, value:String):String {
			return 'abstract Slots(Array<'
				+ getter
				+ '>){public function new();@:arrayAccess public function read(index:Int):'
				+ getter
				+ ';@:arrayAccess public function write(index:Int,value:'
				+ value
				+ '):String;}class Main{static function main():Void{}}';
		}
		final intSource = provider("Int", "Float");
		rejects(() -> selected(intSource, "slots[0] /= 2"), "Float division output bypassed the Int place contract");
		final division = selected(provider("Float", "Float"), "slots[0] /= 2");
		require(division.selection.computed.getType(division.environment).getSemanticKey() == "primitive:Float", "division lost its checked Float result");
		final nullable = selected(provider("Null<Int>", "Null<Int>"), "slots[0]++");
		require(nullable.selection.computed.getType(nullable.environment).isNullable(), "numeric step erased nullable getter identity");
		final abstractSource = 'abstract Value(Int){@:op(a++) public function increment():Value return this;}' + provider("Value", "Value");
		final abstractStep = selected(abstractSource, "slots[0]++");
		require(abstractStep.selection.selection.binary == null, "indexed numeric step selected a declared increment overload");
		require(abstractStep.selection.computed.getType(abstractStep.environment).getNominalIdentity().getCanonicalName() == "Main.Value",
			"numeric abstract step erased the applied getter declaration");
		final incomplete = fixture('abstract Slots<T>(Array<T>){public function new();@:arrayAccess public function read(index:Int):T;'
			+ '@:arrayAccess public function write(index:Int,value:T):String;}class Main{static function main():Void{}}');
		final unchanged = incomplete.environment.getInference().unchangedFacts();
		rejects(() -> TyperStage.selectIndexedUpdate(HxParser.parseExprText("slots[0]++"), incomplete.environment, incomplete.context, HxPos.unknown()),
			"incomplete numeric result was materialized as a fallback");
		require(unchanged(), "incomplete result published candidate facts");
		final guarded = fixture(intSource);
		rejects(() -> TyperStage.inferExprType(HxParser.parseExprText("slots[0]++"), guarded.environment, guarded.context, HxPos.unknown()),
			"helper evidence enabled public indexed-update admission");
		Sys.println("INDEXED_UPDATE_SELECTION:PASS numeric_and_admission_boundaries");
	}

	static function main():Void {
		final source = 'abstract Slots(Array<Int>){public function new();'
			+ '@:arrayAccess public function read(index:Int):Int;'
			+ '@:arrayAccess public function write(index:Int,value:Float):String;}'
			+ 'class Main{static function main():Void{}}';
		for (expression in ["slots[0]++", "++slots[0]", "slots[0] += 2"]) {
			final result = selected(source, expression);
			final selection = result.selection;
			final query = selection.selection.query;
			require(query.source == result.original, "selection lost the original update occurrence");
			require(selection.getStaticType(result.environment).getSemanticKey() == "primitive:String", "static result must follow the setter");
			require(selection.selection.getter.declaration.getSignature().getName() == "read", "wrong getter declaration");
			require(selection.selection.setter.declaration.getSignature().getName() == "write", "wrong setter declaration");
			require(query.setterInputSource != query.computedSource, "setter input borrowed the raw computed query");
			require(query.setterInputSource != query.setterSource, "setter input borrowed the setter result query");
			require(selection.computed.getType(result.environment).getSemanticKey() == "primitive:Int", "computed query lost its raw Int result");
			require(selection.setterInput.getType(result.environment).getSemanticKey() == "primitive:Float", "setter input is not its converted Float value");
			require(selection.payload == (expression == "slots[0]++" ? OldGetter : SetterValue), "static type changed runtime payload ownership");
		}
		lateGetterAndRollback();
		conversionAndIdentity();
		operatorPositions();
		finalBindingIdentity();
		lexicalOperands();
		numericAndAdmissionBoundaries();
		Sys.println("INDEXED_UPDATE_SELECTION:PASS");
	}
}
