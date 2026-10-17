/** A column reads one value after its enclosing structural test succeeds. */
enum GuardedPatternRead {
	Input;
	ArrayItem(parent:Int, index:Int);
	ObjectField(parent:Int, name:String);
	EnumArgument(parent:Int, constructor:HxSwitchPattern, index:Int);
}

/** Named constructors retain their exact selected declaration, not just a source label. */
enum GuardedPatternTest {
	IsNull;
	IsBool(value:Bool);
	IsInt(value:Int);
	IsString(value:String);
	ArrayLength(length:Int);
	EnumConstructor(source:HxSwitchPattern, selection:TypedNamedPattern);
}

/** The original binding occurrence identifies its typed local at projection time. */
typedef GuardedPatternCapture = {
	final source:HxSwitchPattern;
	final column:Int;
}

/**
	An attempt runs one canonical case body and follows rejected only if its guard fails.
	Read creates immutable observations in this decision path. Later attempts reuse
	those observations even when a guard mutates the original object or array.
 */
enum GuardedPatternDecision {
	Exhausted;
	NullAccess;
	Test(column:Int, test:GuardedPatternTest, matched:GuardedPatternDecision, unmatched:GuardedPatternDecision);
	Read(columns:Array<Int>, next:GuardedPatternDecision);
	Attempt(caseIndex:Int, captures:Array<GuardedPatternCapture>, rejected:GuardedPatternDecision);
}

private typedef GuardedPatternRow = {
	final patterns:Array<HxSwitchPattern>;
	final caseIndex:Int;
	final captures:Array<GuardedPatternCapture>;
}

private typedef GuardedPatternColumn = {
	final index:Int;
	final nonNull:Bool;
}

/**
	Plan guard retries with the structural observations shared by a whole switch.
	A successful array, record, or enum decomposition exposes its immediate values
	before any nested decision or guard. Nested decompositions stay conditional.
	For example, a guard can change [1, 2] to [1, 3], but another alternative
	within that length decision still binds the previously extracted 2.
	The plan references case bodies by index, so it never copies typed closures.
 */
class TypedGuardedPatternPlan {
	final patterns:Array<HxSwitchPattern>;
	final columns:Array<GuardedPatternRead> = [Input];
	final namedPatterns:Array<HxSwitchPattern>;
	final namedSelections:Array<TypedNamedPattern>;
	final root:GuardedPatternDecision;
	final canCompleteNormally:Bool;
	final exhaustive:Bool;
	final caseCompletion:Array<Bool>;

	public function new(patterns:Array<HxSwitchPattern>, named:HxSwitchPattern->TypedNamedPattern, canCompleteNormally:Bool, exhaustive:Bool,
			caseCompletion:Array<Bool>) {
		if (caseCompletion.length != patterns.length)
			throw "guarded plan requires one accepted-body completion fact per case";
		this.patterns = patterns.copy();
		this.canCompleteNormally = canCompleteNormally;
		this.exhaustive = exhaustive;
		this.caseCompletion = caseCompletion.copy();
		namedPatterns = TypedSwitchPatterns.named(this.patterns);
		// Snapshot every selected declaration before literal normalization or
		// unreachable-case pruning can erase it from the execution decisions.
		namedSelections = namedPatterns.map(pattern -> {
			final selected = named(pattern);
			if (selected == null)
				throw "guarded named pattern requires its exact declaration";
			return selected;
		});
		root = compile([
			for (index in 0...patterns.length)
				{patterns: [patterns[index]], caseIndex: index, captures: []}
		], [{index: 0, nonNull: false}]);
	}

	public function getRoot():GuardedPatternDecision
		return root;

	/** False retains shared typing's proof that every possible case exits this region. */
	public function getCanCompleteNormally():Bool
		return canCompleteNormally;

	/** Exhaustion contradicts shared typing only when the original guarded cases cover every input. */
	public function getHasExhaustiveCoverage():Bool
		return exhaustive;

	/** True permits a target exit after the selected body; false forbids an unreachable synthetic jump. */
	public function caseCanCompleteNormally(index:Int):Bool {
		if (index < 0 || index >= caseCompletion.length)
			throw "guarded completion requires an existing case";
		return caseCompletion[index];
	}

	public function getColumns():Array<GuardedPatternRead>
		return columns.copy();

	public function getPatterns():Array<HxSwitchPattern>
		return patterns.copy();

	/** Pair projected occurrences with the declarations already selected by typing. */
	public static function fromSelected(patterns:Array<HxSwitchPattern>, selections:Array<Null<TypedNamedPattern>>, canCompleteNormally:Bool, exhaustive:Bool,
			caseCompletion:Array<Bool>):TypedGuardedPatternPlan {
		final occurrences = TypedSwitchPatterns.named(patterns);
		if (occurrences.length != selections.length)
			throw "guarded plan lost named pattern occurrences";
		return new TypedGuardedPatternPlan(patterns, pattern -> {
			final index = occurrences.indexOf(pattern);
			if (index < 0 || selections[index] == null)
				throw "guarded plan has no exact selected named pattern";
			return selections[index];
		}, canCompleteNormally, exhaustive, caseCompletion);
	}

	/** Include executable decisions and exact pattern membership in projection freshness checks. */
	public function getSemanticKey():String {
		final occurrences = new Array<HxSwitchPattern>();
		function visit(pattern:HxSwitchPattern):Void {
			occurrences.push(pattern);
			switch pattern {
				case PArray(children) | POr(children) | PObject(_, children) | PEnumExtract(_, children):
					for (child in children)
						visit(child);
				case PCapture(_, child):
					visit(child);
				case _:
			}
		}
		for (pattern in patterns)
			visit(pattern);
		function occurrence(pattern:HxSwitchPattern):String {
			final index = occurrences.indexOf(pattern);
			if (index < 0)
				throw "guarded decision borrowed a foreign pattern occurrence";
			return Std.string(index);
		}
		final parts = [
			"guarded-pattern-plan-v5",
			canCompleteNormally ? "normal-completion" : "abrupt-completion",
			exhaustive ? "exhaustive-coverage" : "partial-coverage",
			TypedBodyFingerprint.exactExpression(ESwitch(ENull, patterns, []))
		];
		for (completes in caseCompletion)
			parts.push(completes ? "case-completes" : "case-exits");
		for (index in 0...namedPatterns.length) {
			parts.push("selected");
			parts.push(occurrence(namedPatterns[index]));
			parts.push(namedSelections[index].getSemanticKey());
		}
		for (read in columns)
			switch read {
				case Input:
					parts.push("input");
				case ArrayItem(parent, index):
					for (part in ["array", Std.string(parent), Std.string(index)])
						parts.push(part);
				case ObjectField(parent, name):
					for (part in ["field", Std.string(parent), name])
						parts.push(part);
				case EnumArgument(parent, source, index):
					for (part in ["argument", Std.string(parent), occurrence(source), Std.string(index)])
						parts.push(part);
			}
		function decision(node:GuardedPatternDecision):Void {
			switch node {
				case Exhausted:
					parts.push("exhausted");
				case NullAccess:
					parts.push("null-access");
				case Read(values, next):
					parts.push("read");
					parts.push(Std.string(values.length));
					for (value in values)
						parts.push(Std.string(value));
					decision(next);
				case Test(column, test, yes, no):
					parts.push("test");
					parts.push(Std.string(column));
					switch test {
						case IsNull: parts.push("null");
						case IsBool(value):
							parts.push("bool");
							parts.push(Std.string(value));
						case IsInt(value):
							parts.push("int");
							parts.push(Std.string(value));
						case IsString(value):
							parts.push("string");
							parts.push(value);
						case ArrayLength(value):
							parts.push("length");
							parts.push(Std.string(value));
						case EnumConstructor(source, selected):
							parts.push("constructor");
							parts.push(occurrence(source));
							parts.push(selected.getSemanticKey());
					}
					decision(yes);
					decision(no);
				case Attempt(index, captures, rejected):
					if (index < 0 || index >= patterns.length)
						throw "guarded decision has no owning case";
					parts.push("attempt");
					parts.push(Std.string(index));
					parts.push(Std.string(captures.length));
					for (capture in captures) {
						parts.push(occurrence(capture.source));
						parts.push(Std.string(capture.column));
					}
					decision(rejected);
			}
		}
		decision(root);
		return CompilerCacheIdentity.encode(parts);
	}

	function addColumn(read:GuardedPatternRead):GuardedPatternColumn {
		final index = columns.length;
		columns.push(read);
		return {index: index, nonNull: false};
	}

	static function replace(row:GuardedPatternRow, index:Int, patterns:Array<HxSwitchPattern>):GuardedPatternRow
		return {
			patterns: row.patterns.slice(0, index).concat(patterns).concat(row.patterns.slice(index + 1)),
			caseIndex: row.caseIndex,
			captures: row.captures
		};

	static function replaceColumns(values:Array<GuardedPatternColumn>, index:Int, children:Array<GuardedPatternColumn>):Array<GuardedPatternColumn>
		return values.slice(0, index).concat(children).concat(values.slice(index + 1));

	/** Save references to observed columns; binding storage is created only when the case is attempted. */
	static function capture(row:GuardedPatternRow, values:Array<GuardedPatternColumn>):GuardedPatternRow {
		final captures = row.captures.copy();
		function strip(pattern:HxSwitchPattern, column:Int):HxSwitchPattern {
			return switch pattern {
				case PCapture(name, inner):
					if (name.length > 0 && name != "_")
						captures.push({source: pattern, column: column});
					strip(inner, column);
				case PBind(name):
					if (name.length > 0 && name != "_")
						captures.push({source: pattern, column: column});
					PWildcard;
				case _: pattern;
			};
		}
		return {patterns: [for (index in 0...values.length) strip(row.patterns[index], values[index].index)], caseIndex: row.caseIndex, captures: captures};
	}

	static function alternatives(row:GuardedPatternRow, index:Int, pattern:HxSwitchPattern, output:Array<GuardedPatternRow>):Void {
		switch pattern {
			case POr(children):
				if (children.length == 0)
					throw "guarded pattern alternative cannot be empty";
				for (child in children)
					alternatives(row, index, child, output);
			case _:
				output.push(replace(row, index, [pattern]));
		}
	}

	function test(pattern:HxSwitchPattern):GuardedPatternTest {
		return switch pattern {
			case PNull: IsNull;
			case PBool(value): IsBool(value);
			case PInt(value): IsInt(value);
			case PString(value): IsString(value);
			case PArray(items): ArrayLength(items.length);
			case PEnumValue(_) | PEnumExtract(_, _):
				final index = namedPatterns.indexOf(pattern);
				if (index < 0)
					throw "guarded decision borrowed a foreign named pattern";
				final selected = namedSelections[index];
				switch selected.getKind() {
					case Constructor(_, _, _, arity):
						final count = switch pattern {
							case PEnumExtract(_, arguments): arguments.length;
							case _: 0;
						};
						if (count != arity)
							throw "guarded enum pattern differs from its selected payload count";
						EnumConstructor(pattern, selected);
					case Constant(field):
						if (pattern.match(PEnumExtract(_, _)))
							throw "guarded constant pattern cannot extract a payload";
						switch field.getConstant().project() {
							case ENull: IsNull;
							case EBool(value): IsBool(value);
							case EInt(value): IsInt(value);
							case EString(value): IsString(value);
							case _: throw "guarded named constant requires its selected literal value";
						}
				}
			case _: throw "guarded pattern requires a structural decision";
		};
	}

	static function sameTest(left:GuardedPatternTest, right:GuardedPatternTest):Bool {
		return switch [left, right] {
			case [IsNull, IsNull]: true;
			case [IsBool(a), IsBool(b)]: a == b;
			case [IsInt(a), IsInt(b)]: a == b;
			case [IsString(a), IsString(b)]: a == b;
			case [ArrayLength(a), ArrayLength(b)]: a == b;
			case [EnumConstructor(_, a), EnumConstructor(_, b)]: a.getSemanticKey() == b.getSemanticKey();
			case _: false;
		};
	}

	static function usesValue(pattern:HxSwitchPattern):Bool {
		return switch pattern {
			case PWildcard: false;
			case PBind(name): name.length > 0 && name != "_";
			case PCapture(name, inner): (name.length > 0 && name != "_") || usesValue(inner);
			case POr(children): children.filter(usesValue).length > 0;
			case _: true;
		};
	}

	/** Immediate projections happen together; a deeper null access stays behind its own decision. */
	function observe(children:Array<GuardedPatternColumn>, rows:Array<GuardedPatternRow>, index:Int,
			values:Array<GuardedPatternColumn>):GuardedPatternDecision {
		final reads = [
			for (offset in 0...children.length) {
				var used = false;
				for (row in rows) {
					final pattern = row.patterns[index + offset];
					if (usesValue(pattern))
						used = true;
				}
				if (used) children[offset].index;
			}
		];
		final next = compile(rows, replaceColumns(values, index, children));
		return reads.length == 0 ? next : Read(reads, next);
	}

	function compile(input:Array<GuardedPatternRow>, values:Array<GuardedPatternColumn>):GuardedPatternDecision {
		if (input.length == 0)
			return Exhausted;
		final rows = [for (row in input) capture(row, values)];
		var index = 0;
		while (index < values.length && rows[0].patterns[index].match(PWildcard))
			index++;
		if (index == values.length)
			return Attempt(rows[0].caseIndex, rows[0].captures, compile(rows.slice(1), values));
		if (rows.filter(row -> row.patterns[index].match(POr(_))).length > 0) {
			final expanded = new Array<GuardedPatternRow>();
			for (row in rows)
				alternatives(row, index, row.patterns[index], expanded);
			return compile(expanded, values);
		}
		final column = values[index];
		if (rows.filter(row -> row.patterns[index].match(PNull)).length > 0) {
			final nullRows = [
				for (row in rows)
					if (row.patterns[index].match(PWildcard) || row.patterns[index].match(PNull)) replace(row, index, [])
			];
			final otherRows = rows.filter(row -> !row.patterns[index].match(PNull));
			return Test(column.index, IsNull, compile(nullRows, replaceColumns(values, index, [])),
				compile(otherRows, replaceColumns(values, index, [{index: column.index, nonNull: true}])));
		}
		final pattern = rows[0].patterns[index];
		final structural = switch pattern {
			case PArray(_) | PObject(_, _): true;
			case PEnumValue(_) | PEnumExtract(_, _): test(pattern).match(EnumConstructor(_, _));
			case _: false;
		};
		if (structural && !column.nonNull)
			return Test(column.index, IsNull, NullAccess, compile(rows, replaceColumns(values, index, [{index: column.index, nonNull: true}])));
		if (pattern.match(PObject(_, _))) {
			final fields = new Array<String>();
			for (row in rows)
				switch row.patterns[index] {
					case PObject(names, patterns):
						if (names.length != patterns.length || names.length == 0)
							throw "guarded record pattern requires aligned fields";
						for (name in names)
							if (fields.indexOf(name) < 0)
								fields.push(name);
					case PWildcard:
					case _:
						throw "guarded record decision contains incompatible patterns";
				}
			fields.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			final specialized = [
				for (row in rows) {
					final nested:Array<HxSwitchPattern> = [for (_ in fields) PWildcard];
					switch row.patterns[index] {
						case PObject(names, patterns):
							for (i in 0...names.length)
								nested[fields.indexOf(names[i])] = patterns[i];
						case _:
					}
					replace(row, index, nested);
				}
			];
			return observe([for (field in fields) addColumn(ObjectField(column.index, field))], specialized, index, values);
		}
		final selected = test(pattern);
		final children:Array<GuardedPatternColumn> = switch selected {
			case ArrayLength(length): [for (i in 0...length) addColumn(ArrayItem(column.index, i))];
			case EnumConstructor(source, selection): switch selection.getKind() {
					case Constructor(_, _, _, arity): [for (i in 0...arity) addColumn(EnumArgument(column.index, source, i))];
					case _: throw "guarded enum projection requires its selected constructor";
				}
			case _: [];
		};
		final matched = new Array<GuardedPatternRow>();
		final unmatched = new Array<GuardedPatternRow>();
		for (row in rows) {
			final candidate = row.patterns[index];
			if (candidate.match(PWildcard)) {
				matched.push(replace(row, index, [for (_ in children) PWildcard]));
				unmatched.push(row);
			} else if (sameTest(selected, test(candidate))) {
				final nested = switch candidate {
					case PArray(items) | PEnumExtract(_, items): items;
					case _: [];
				};
				matched.push(replace(row, index, nested));
			} else {
				unmatched.push(row);
			}
		}
		return Test(column.index, selected, observe(children, matched, index, values), compile(unmatched, values));
	}
}
