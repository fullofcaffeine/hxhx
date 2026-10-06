package backend.ocaml;

/** One source-ordered case after the decisions already made on its path. */
private typedef PatternRow = {
	final patterns:Array<HxSwitchPattern>;
	final branch:String;
	final bindings:String;
}

/** An access remains deferred until a refutable pattern needs its value. */
private typedef PatternColumn = {
	final value:String;
	final bound:Bool;
	final nonNull:Bool;
}

/** Rendering dependencies belong to the exact function or initializer being emitted. */
private typedef PatternContext = {
	final dialect:HihBackendDialect;
	final quote:String->String;
	final freshName:Void->String;
	final names:Stage3OcamlLocalNames;
	final fallback:String;
}

/** Inputs belong to one projected switch and its enclosing local catalog. */
typedef PatternSelection = {
	final patterns:Array<HxSwitchPattern>;
	final branches:Array<String>;
	final value:String;
	final fallback:String;
	final dialect:HihBackendDialect;
	final quote:String->String;
	final names:Stage3OcamlLocalNames;
}

/**
	Select a source-ordered branch by specializing a matrix of remaining patterns.

	For example, [[1]] and [null] share the outer length decision. Only then can
	the second row protect the nested access from null. A [null, _] row cannot
	protect it: that row was removed by the incompatible outer length decision.
	Each row keeps its own bindings when alternatives split. Bindings execute only
	in the selected branch. The caller evaluates the root scrutinee once.
	Guard and extractor execution is not represented by this structural subset.
 */
function select(input:PatternSelection):String {
	if (input.patterns.length != input.branches.length || input.names == null)
		throw "OCaml switch requires aligned cases and an exact naming owner";
	var nextTemporary = 0;
	final rows = [
		for (i in 0...input.patterns.length)
			{patterns: [input.patterns[i]], branch: input.branches[i], bindings: ""}
	];
	return compileRows(rows, [{value: input.value, bound: true, nonNull: false}], {
		dialect: input.dialect,
		quote: input.quote,
		freshName: () -> input.names.internalName("__hx_pattern_value_" + nextTemporary++),
		names: input.names,
		fallback: input.fallback
	});
}

/** Captures do not add a test; their exact binding remains in the selected branch. */
private function head(pattern:HxSwitchPattern):HxSwitchPattern {
	return switch pattern {
		case PCapture(_, inner): head(inner);
		case PExtractor(_, _) | PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PIntEqualsGuard(_, _, _) | PIntCompareGuard(_, _, _, _) |
			PParsedIntSwitchGuard(_, _, _, _) | PUnsupportedGuard(_):
			throw "OCaml switch requires executable guard or extractor lowering";
		case _: pattern;
	};
}

private function wildcard(pattern:HxSwitchPattern):Bool {
	return switch head(pattern) {
		case PWildcard | PBind(_): true;
		case _: false;
	};
}

private function replaceRow(row:PatternRow, index:Int, patterns:Array<HxSwitchPattern>):PatternRow {
	return {patterns: row.patterns.slice(0, index).concat(patterns).concat(row.patterns.slice(index + 1)), branch: row.branch, bindings: row.bindings};
}

private function replaceColumn(columns:Array<PatternColumn>, index:Int, replacements:Array<PatternColumn>):Array<PatternColumn> {
	return columns.slice(0, index).concat(replacements).concat(columns.slice(index + 1));
}

private function expandAlternative(row:PatternRow, index:Int, pattern:HxSwitchPattern, output:Array<PatternRow>):Void {
	switch pattern {
		case POr(alternatives):
			for (alternative in alternatives)
				expandAlternative(row, index, alternative, output);
		case other:
			output.push(replaceRow(row, index, [other]));
	}
}

/** Constructor equality uses pattern structure, never rendered source or target text. */
private function sameTest(left:HxSwitchPattern, right:HxSwitchPattern):Bool {
	return switch [head(left), head(right)] {
		case [PInt(a), PInt(b)]: a == b;
		case [PString(a), PString(b)]: a == b;
		case [PBool(a), PBool(b)]: a == b;
		case [PArray(a), PArray(b)]: a.length == b.length;
		case [PEnumValue(a), PEnumValue(b)]: a == b;
		case [PEnumExtract(a, args), PEnumExtract(b, other)]: a == b && args.length == other.length;
		case _: false;
	};
}

/**
	Save each binding's access before specializing away its column.

	An alternative keeps these accesses on its own row, so [0, x] | [x, 0]
	binds x from the matching position. Deferred reads are emitted only at a leaf;
	unused alternatives cannot evaluate their captures or shadow selected values.
 */
private function captureBindings(row:PatternRow, columns:Array<PatternColumn>, context:PatternContext):PatternRow {
	var bindings = row.bindings;
	function bind(name:String, value:String):Void {
		if (name == "_")
			return;
		final type = context.names.findType(name);
		if (type == null)
			throw "OCaml pattern binding requires its exact local type";
		// Record fields retain boxed Boolean identity; root/array Bool values can
		// already be native. Restore Bool only when the typed binding requires it.
		final restored = type.getSemanticKey() == "primitive:Bool" ? "HxRuntime.unbox_bool_or_obj (Obj.repr (" + value + "))" : "Obj.magic (" + value + ")";
		bindings += "let " + context.names.targetName(name) + " = " + restored + " in ";
	}
	function strip(pattern:HxSwitchPattern, value:String):HxSwitchPattern {
		return switch pattern {
			case PCapture(name, inner):
				bind(name, value);
				strip(inner, value);
			case PBind(name):
				bind(name, value);
				PWildcard;
			case _: pattern;
		};
	}
	final patterns = [for (i in 0...columns.length) strip(row.patterns[i], columns[i].value)];
	return {patterns: patterns, branch: row.branch, bindings: bindings};
}

/** Emit decisions only for surviving rows, keeping later reads behind earlier failures. */
private function compileRows(rows:Array<PatternRow>, columns:Array<PatternColumn>, context:PatternContext):String {
	if (rows.length == 0)
		return context.fallback;
	rows = [for (row in rows) captureBindings(row, columns, context)];
	var index = 0;
	while (index < columns.length && wildcard(rows[0].patterns[index]))
		index++;
	if (index == columns.length)
		return "(" + rows[0].bindings + rows[0].branch + ")";
	if (rows.filter(row -> head(row.patterns[index]).match(POr(_))).length > 0) {
		final expanded = new Array<PatternRow>();
		for (row in rows)
			expandAlternative(row, index, row.patterns[index], expanded);
		return compileRows(expanded, columns, context);
	}
	final column = columns[index];
	if (!column.bound) {
		final name = context.freshName();
		return "(let "
			+ name
			+ " = "
			+ column.value
			+ " in "
			+ compileRows(rows, replaceColumn(columns, index, [{value: name, bound: true, nonNull: column.nonNull}]), context)
			+ ")";
	}
	final value = column.value;
	final isNull = context.dialect.runtimeIsNull(value);
	if (rows.filter(row -> head(row.patterns[index]).match(PNull)).length > 0) {
		final nullRows = [
			for (row in rows)
				if (wildcard(row.patterns[index]) || head(row.patterns[index]).match(PNull)) replaceRow(row, index, [])
		];
		final otherRows = rows.filter(row -> !head(row.patterns[index]).match(PNull));
		return "(if "
			+ isNull
			+ " then "
			+ compileRows(nullRows, replaceColumn(columns, index, []), context)
			+ " else "
			+ compileRows(otherRows, replaceColumn(columns, index, [
				{
					value: value,
					bound: true,
					nonNull: true
				}
			]), context)
			+ ")";
	}
	final pattern = head(rows[0].patterns[index]);
	final structural = switch pattern {
		case PArray(_) | PObject(_, _) | PEnumExtract(_, _) | PEnumValue(_): true;
		case _: false;
	};
	if (structural && !column.nonNull) {
		final failure = "HxRuntime.hx_throw_typed (Obj.repr " + context.quote("Null Access") + ") [\"String\"; \"Dynamic\"]";
		return "(if "
			+ isNull
			+ " then "
			+ failure
			+ " else "
			+ compileRows(rows, replaceColumn(columns, index, [{value: value, bound: true, nonNull: true}]), context)
			+ ")";
	}
	if (pattern.match(PObject(_, _))) {
		final fields = new Array<String>();
		for (row in rows)
			switch head(row.patterns[index]) {
				case PObject(names, patterns):
					if (names.length != patterns.length || names.length == 0)
						throw "OCaml object pattern requires nonempty aligned fields";
					for (name in names)
						if (fields.indexOf(name) < 0)
							fields.push(name);
				case PWildcard | PBind(_):
				case _:
					throw "OCaml object decision contains an incompatible pattern";
			}
		// Upstream tests fields by name, so written order cannot move a null access.
		fields.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		final specialized = new Array<PatternRow>();
		for (row in rows) {
			final patterns:Array<HxSwitchPattern> = [for (_ in fields) PWildcard];
			switch head(row.patterns[index]) {
				case PObject(names, nested):
					for (i in 0...names.length)
						patterns[fields.indexOf(names[i])] = nested[i];
				case _:
			}
			specialized.push(replaceRow(row, index, patterns));
		}
		final selected = [
			for (name in fields)
				{value: "(HxAnon.get (Obj.repr " + value + ") " + context.quote(name) + ")", bound: false, nonNull: false}
		];
		return compileRows(specialized, replaceColumn(columns, index, selected), context);
	}
	final children:Array<PatternColumn> = switch pattern {
		case PArray(items): [
				for (i in 0...items.length)
					{value: "(HxArray.get (Obj.magic " + value + ") " + i + ")", bound: false, nonNull: false}
			];
		case PEnumExtract(_, arguments): [
				for (i in 0...arguments.length)
					{value: "(HxArray.get (Type.enumParameters " + value + ") " + i + ")", bound: false, nonNull: false}
			];
		case _: [];
	};
	final matched = new Array<PatternRow>();
	final unmatched = new Array<PatternRow>();
	for (row in rows) {
		final candidate = head(row.patterns[index]);
		if (wildcard(candidate)) {
			matched.push(replaceRow(row, index, [for (_ in children) PWildcard]));
			unmatched.push(row);
		} else if (sameTest(pattern, candidate)) {
			final nested = switch candidate {
				case PArray(items) | PEnumExtract(_, items): items;
				case _: [];
			};
			matched.push(replaceRow(row, index, nested));
		} else {
			unmatched.push(row);
		}
	}
	final test = switch pattern {
		case PInt(literal): context.dialect.runtimeDynamicEquals(value, Std.string(literal));
		case PString(literal): context.dialect.runtimeDynamicEquals(value, context.quote(literal));
		case PBool(literal): context.dialect.runtimeDynamicEquals(value, literal ? "true" : "false");
		case PArray(items): "(HxArray.length (Obj.magic " + value + ") = " + items.length + ")";
		case PEnumValue(name): context.dialect.runtimeDynamicEquals("(Type.enumConstructor " + value + ")", context.quote(name));
		case PEnumExtract(name, arguments): "("
			+ context.dialect.runtimeDynamicEquals("(Type.enumConstructor " + value + ")", context.quote(name))
			+ " && HxArray.length (Type.enumParameters "
			+ value
			+ ") = "
			+ arguments.length
			+ ")";
		case _: throw "OCaml switch has no structural decision for this pattern";
	};
	return "(if "
		+ test
		+ " then "
		+ compileRows(matched, replaceColumn(columns, index, children), context)
		+ " else "
		+ compileRows(unmatched, columns, context)
		+ ")";
}
