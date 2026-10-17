import TypedGuardedPatternPlan;

/** Small runtime values let the test observe reads and mutations without a target emitter. */
private enum ObservedValue {
	NullValue;
	IntValue(value:Int);
	BoolValue(value:Bool);
	StringValue(value:String);
	ArrayValue(values:Array<ObservedValue>);
	ObjectValue(fields:haxe.ds.StringMap<ObservedValue>);
	EnumValue(owner:String, index:Int, arguments:Array<ObservedValue>);
}

/** Expected values come from separate upstream Haxe programs, not from the planner. */
class M14GuardedPatternPlanTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function integer(value:ObservedValue):Int
		return switch value {
			case IntValue(value): value;
			case _: throw "observer requires an Int";
		};

	static function execute(patterns:Array<HxSwitchPattern>, input:ObservedValue, attempt:(Int, haxe.ds.StringMap<ObservedValue>) -> Bool,
			?named:HxSwitchPattern->TypedNamedPattern):Int {
		final plan = new TypedGuardedPatternPlan(patterns, named == null ? _ -> throw "this fixture has no named patterns" : named, true, false,
			[for (_ in patterns) true]);
		final reads = plan.getColumns();
		final values = new haxe.ds.IntMap<ObservedValue>();
		values.set(0, input);
		function value(column:Int):ObservedValue {
			if (!values.exists(column))
				throw "decision read a column before observation";
			return values.get(column);
		}
		function observe(column:Int):Void {
			if (values.exists(column))
				throw "decision observed the same column twice";
			values.set(column, switch reads[column] {
				case Input: throw "the input is already observed";
				case ArrayItem(parent, index): switch value(parent) {
						case ArrayValue(items): items[index];
						case _: throw "array projection has no array";
					}
				case ObjectField(parent, name): switch value(parent) {
						case ObjectValue(fields): fields.get(name);
						case _: throw "record projection has no record";
					}
				case EnumArgument(parent, _, index): switch value(parent) {
						case EnumValue(_, _, arguments): arguments[index];
						case _: throw "enum projection has no enum";
					}
			});
		}
		function matches(column:Int, test:GuardedPatternTest):Bool {
			return switch [test, value(column)] {
				case [IsNull, NullValue]: true;
				case [IsBool(a), BoolValue(b)]: a == b;
				case [IsInt(a), IntValue(b)]: a == b;
				case [IsString(a), StringValue(b)]: a == b;
				case [ArrayLength(length), ArrayValue(items)]: length == items.length;
				case [EnumConstructor(_, selected), EnumValue(owner, index, _)]: switch selected.getKind() {
						case Constructor(identity, _, expected, _): owner == identity.getCanonicalName() && index == expected;
						case _: false;
					}
				case _: false;
			};
		}
		function run(decision:GuardedPatternDecision):Int {
			return switch decision {
				case Exhausted: -1;
				case NullAccess: throw "null access";
				case Test(column, test, yes, no): run(matches(column, test) ? yes : no);
				case Read(columns, next):
					for (column in columns)
						observe(column);
					run(next);
				case Attempt(index, captures, rejected):
					final bindings = new haxe.ds.StringMap<ObservedValue>();
					for (capture in captures) {
						final name = switch capture.source {
							case PBind(name) | PCapture(name, _): name;
							case _: throw "capture lost its original binding occurrence";
						};
						bindings.set(name, value(capture.column));
					}
					attempt(index, bindings) ? index : run(rejected);
			};
		}
		return run(plan.getRoot());
	}

	static function mutationAlternatives():Void {
		final items = [IntValue(1), IntValue(2)];
		var seen = 0;
		final selected = execute([
			POr([PArray([PBind("value"), PInt(2)]), PArray([PInt(1), PBind("value")])]),
			PWildcard
		], ArrayValue(items), (index, captures) -> {
			if (index == 1)
				return true;
			final value = integer(captures.get("value"));
			seen = seen * 10 + value;
			items[1] = IntValue(3);
			return value == 3;
		});
		require(selected == 1 && seen == 12, "OR retries must reuse extracted values after guard mutation");
		require(integer(items[1]) == 3, "guard mutation must remain visible in the original input");
	}

	static function mutationCases(first:HxSwitchPattern, second:HxSwitchPattern):Void {
		final items = [IntValue(1), IntValue(2)];
		var observed = -1;
		final selected = execute([first, second, PWildcard], ArrayValue(items), (index, captures) -> {
			if (index == 0) {
				items[1] = IntValue(3);
				return false;
			}
			observed = integer(captures.get("value"));
			return true;
		});
		require(selected == 1 && observed == 2, "separate cases must share immediate projections, including values unused by the first case");
	}

	static function lazyNested():Void {
		final input = ArrayValue([NullValue]);
		final patterns:Array<HxSwitchPattern> = [PWildcard, PArray([PArray([PBind("value")])]), PWildcard];
		require(execute(patterns, input, (index, _) -> index == 0) == 0, "a selected wildcard must not read later nested values");
		var rejected = false;
		try {
			execute(patterns, input, (_, _) -> false);
		} catch (error:String) {
			rejected = error == "null access";
		}
		require(rejected, "a later structural match must still report its null access");
	}

	static function recordMutation():Void {
		final fields = new haxe.ds.StringMap<ObservedValue>();
		fields.set("a", IntValue(1));
		fields.set("b", IntValue(2));
		var observed = -1;
		execute([PObject(["a"], [PBind("value")]), PObject(["b"], [PBind("value")])], ObjectValue(fields), (index, captures) -> {
			if (index == 0) {
				fields.set("b", IntValue(3));
				return false;
			}
			observed = integer(captures.get("value"));
			return true;
		});
		require(observed == 2, "record cases must retain immediate fields extracted before a guard");
	}

	static function namedSelections():Void {
		final first = HxSwitchPattern.PEnumExtract("Original.Value", [PBind("value")]);
		final alias = HxSwitchPattern.PEnumExtract("Alias.Value", [PBind("value")]);
		final other = HxSwitchPattern.PEnumExtract("Other.Value", [PBind("value")]);
		final selected = new TypedNamedPattern(Constructor(new TyNominalTypeId("model.Choice"), "Value", 0, 1));
		final different = new TypedNamedPattern(Constructor(new TyNominalTypeId("other.Choice"), "Value", 0, 1));
		var attempts = 0;
		final winner = execute([other, first, alias], EnumValue("model.Choice", 0, [IntValue(4)]), (index, captures) -> {
			attempts++;
			require(integer(captures.get("value")) == 4, "named case lost its payload");
			return index == 2;
		}, pattern -> pattern == other ? different : selected);
		require(winner == 2 && attempts == 2, "aliases must share selected identity while another same-named constructor stays distinct");
		var rejected = false;
		try {
			new TypedGuardedPatternPlan([PEnumExtract("Original.Value", [])], _ -> selected, true, false, [true]);
		} catch (error:String) {
			rejected = error.indexOf("selected payload count") >= 0;
		}
		require(rejected, "a named pattern cannot borrow a constructor with another payload shape");
	}

	/** Projection identities must notice a changed retry and reject a borrowed binding occurrence. */
	static function decisionFreshness():Void {
		final binding = HxSwitchPattern.PBind("value");
		final plan = new TypedGuardedPatternPlan([binding], _ -> throw "this fixture has no named patterns", true, false, [true]);
		final before = plan.getSemanticKey();
		switch plan.getRoot() {
			case Attempt(_, captures, _):
				captures.pop();
				require(plan.getSemanticKey() != before, "removing a case binding must invalidate its projected plan");
				captures.push({source: HxSwitchPattern.PBind("other"), column: 0});
				var rejected = false;
				try {
					plan.getSemanticKey();
				} catch (error:String) {
					rejected = error.indexOf("foreign pattern occurrence") >= 0;
				}
				require(rejected, "a decision cannot borrow a binding from another switch");
			case _:
				throw "a binding-only case requires one attempt";
		}
		final pattern = HxSwitchPattern.PEnumValue("Choice.Value");
		final first = new TypedNamedPattern(Constructor(new TyNominalTypeId("first.Choice"), "Value", 0, 0));
		final second = new TypedNamedPattern(Constructor(new TyNominalTypeId("second.Choice"), "Value", 0, 0));
		final firstPlan = TypedGuardedPatternPlan.fromSelected([pattern], [first], true, false, [true]);
		final secondPlan = TypedGuardedPatternPlan.fromSelected([pattern], [second], true, false, [true]);
		require(firstPlan.getSemanticKey() != secondPlan.getSemanticKey(), "same-spelled constructors from different enums must have distinct plan identities");
		final abrupt = TypedGuardedPatternPlan.fromSelected([pattern], [first], false, false, [false]);
		require(!abrupt.getCanCompleteNormally() && firstPlan.getCanCompleteNormally(), "guarded projection lost its selected completion fact");
		require(firstPlan.getSemanticKey() != abrupt.getSemanticKey(), "changing completion must invalidate the projected control plan");
		final exhaustive = TypedGuardedPatternPlan.fromSelected([pattern], [first], true, true, [true]);
		require(exhaustive.getHasExhaustiveCoverage()
			&& !firstPlan.getHasExhaustiveCoverage(), "guarded projection lost its coverage proof");
		require(exhaustive.getSemanticKey() != firstPlan.getSemanticKey(), "changing coverage must invalidate the projected control plan");
		final completions = [false];
		final abruptCase = TypedGuardedPatternPlan.fromSelected([pattern], [first], true, false, completions);
		completions[0] = true;
		require(!abruptCase.caseCanCompleteNormally(0), "a caller changed an accepted body's completion fact after projection");
		require(abruptCase.getSemanticKey() != firstPlan.getSemanticKey(), "accepted-body completion must participate in plan identity");
	}

	/** Attempt scopes isolate bindings and share unique names without intercepting thrown values. */
	static function lexicalCleanup():Void {
		final scope = new backend.js.JsFunctionScope(new haxe.ds.StringMap<String>());
		final outer = scope.declareLocal("outer");
		var failedName = "";
		var caught = false;
		try {
			final attempt = scope.lexicalChild();
			require(attempt.resolveLocal("outer") == outer, "attempt lost enclosing names");
			failedName = attempt.declareLocal("temporary");
			throw "scope sentinel";
		} catch (error:String) {
			caught = error == "scope sentinel";
		}
		require(caught
			&& scope.resolveLocal("temporary") == null
			&& scope.resolveLocal("outer") == outer, "string failure leaked names or changed its value");
		final original = new haxe.Exception("same exception");
		caught = false;
		try {
			final attempt = scope.lexicalChild();
			require(attempt.declareLocal("temporary") != failedName, "failed attempt released a reserved name");
			throw original;
		} catch (error:haxe.Exception) {
			caught = error == original;
		}
		require(caught && scope.resolveLocal("temporary") == null && scope.resolveLocal("outer") == outer,
			"exception failure leaked names or changed identity");
		final attempt = scope.lexicalChild();
		final local = attempt.declareLocal("temporary");
		final nested = attempt.lexicalChild();
		require(nested.resolveLocal("temporary") == local, "nested attempt lost enclosing bindings");
		final inner = nested.declareLocal("inner");
		require(attempt.resolveLocal("inner") == null
			&& scope.declareLocal("inner") != inner, "nested attempt leaked bindings or reused a name");
		require(scope.resolveLocal("temporary") == null && scope.resolveLocal("outer") == outer, "normal completion leaked local names");
	}

	static function main():Void {
		lexicalCleanup();
		mutationAlternatives();
		mutationCases(PArray([PBind("value"), PInt(2)]), PArray([PInt(1), PBind("value")]));
		mutationCases(PArray([PBind("value"), PWildcard]), PArray([PWildcard, PBind("value")]));
		lazyNested();
		recordMutation();
		namedSelections();
		decisionFreshness();
		constantSelectionFreshness();
		Sys.println("GUARDED_PATTERN_PLAN:PASS");
	}

	/** Equal literal values still depend on different declarations; caller arrays do not own a compiled plan. */
	static function constantSelectionFreshness():Void {
		final modules = [
			for (name in ["First", "Second"])
				new ResolvedModule(name, name + ".hx", ParserStage.parse("enum abstract " + name + "(Int) { var Value = 1; }", name + ".hx"))
		];
		final index = TyperIndex.build(modules);
		final first = new TypedNamedPattern(Constant(index.getByFullName("First").fieldInfo("Value")));
		final second = new TypedNamedPattern(Constant(index.getByFullName("Second").fieldInfo("Value")));
		final source = HxSwitchPattern.PEnumValue("Selected.Value");
		final selections:Array<Null<TypedNamedPattern>> = [first];
		final plan = TypedGuardedPatternPlan.fromSelected([source], selections, true, false, [true]);
		final before = plan.getSemanticKey();
		selections[0] = second;
		require(plan.getSemanticKey() == before, "a caller changed the declarations of an already compiled plan");
		final changed = TypedGuardedPatternPlan.fromSelected([source], selections, true, false, [true]);
		require(changed.getSemanticKey() != before, "equal-valued constants from different declarations reused one plan identity");
	}
}
