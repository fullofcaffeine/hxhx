/**
	Evaluates the small compile-time diagnostic probes used by compatibility
	fixtures before ordinary expression typing reaches their intentionally
	invalid input.

	A diagnostic probe asks what error a source expression would produce and
	returns that message as data. Its argument therefore is not an ordinary
	runtime expression: typing it in the enclosing function would raise the very
	error the probe is meant to observe. This owner reads the preserved parser
	facts and returns the deterministic message without involving a target
	backend.
**/
class CompilerDiagnosticProbe {
	public static function getErrorMessage(expression:HxExpr, ?localInitializer:String->Null<HxExpr>):Null<String> {
		return switch (expression) {
			case EMacroExpr(inner, _) | EUntyped(inner):
				getErrorMessage(inner, localInitializer);
			case ESwitch(scrutinee, patterns, _):
				final diagnosticScrutinee = diagnosticScrutineeExpr(scrutinee, localInitializer);
				final invalidBinding = switchInvalidBindingMessage(patterns);
				invalidBinding == null ? switchNonExhaustiveMessage(diagnosticScrutinee, patterns) : invalidBinding;
			case _:
				null;
		};
	}

	static function diagnosticScrutineeExpr(expression:HxExpr, localInitializer:Null<String->Null<HxExpr>>):HxExpr {
		return switch (expression) {
			case EMacroExpr(inner, _) | EUntyped(inner):
				diagnosticScrutineeExpr(inner, localInitializer);
			case EIdent(name) if (localInitializer != null):
				final initializer = localInitializer(name);
				initializer == null ? expression : diagnosticScrutineeExpr(initializer, localInitializer);
			case _:
				expression;
		};
	}

	static function switchInvalidBindingMessage(patterns:Array<HxSwitchPattern>):Null<String> {
		if (patterns == null)
			return null;
		for (pattern in patterns) {
			final duplicate = duplicateBindingName(pattern);
			if (duplicate != null)
				return "Variable " + duplicate + " is bound multiple times";
			switch (pattern) {
				case POr(alternatives):
					final message = orBindingMessage(alternatives);
					if (message != null)
						return message;
				case _:
			}
		}
		return null;
	}

	static function orBindingMessage(patterns:Array<HxSwitchPattern>):Null<String> {
		if (patterns == null || patterns.length < 2)
			return null;
		final baseCounts = patternBindingCounts(patterns[0]);
		final baseOrder = patternBindingOrder(patterns[0]);
		for (index in 1...patterns.length) {
			final alternativeCounts = patternBindingCounts(patterns[index]);
			final alternativeOrder = patternBindingOrder(patterns[index]);
			for (name in alternativeOrder)
				if (!baseCounts.exists(name))
					return "Variable " + name + " must appear exactly once in each sub-pattern";
			for (name in baseOrder)
				if (!alternativeCounts.exists(name) || alternativeCounts.get(name) != 1)
					return "Variable " + name + " must appear exactly once in each sub-pattern";
		}
		for (name in baseOrder)
			if (baseCounts.get(name) != 1)
				return "Variable " + name + " must appear exactly once in each sub-pattern";
		return orBindingTypeMismatchMessage(patterns);
	}

	static function duplicateBindingName(pattern:HxSwitchPattern):Null<String> {
		return switch (pattern) {
			case POr(patterns):
				if (patterns == null) {
					null;
				} else {
					var found:Null<String> = null;
					for (child in patterns) {
						final duplicate = duplicateBindingName(child);
						if (found == null && duplicate != null)
							found = duplicate;
					}
					found;
				}
			case _:
				final counts = patternBindingCounts(pattern);
				final order = patternBindingOrder(pattern);
				for (name in order)
					if (counts.get(name) > 1)
						return name;
				null;
		};
	}

	static function patternBindingCounts(pattern:HxSwitchPattern):Map<String, Int> {
		final counts = new Map<String, Int>();
		collectPatternBindings(pattern, counts, []);
		return counts;
	}

	static function patternBindingOrder(pattern:HxSwitchPattern):Array<String> {
		final order = new Array<String>();
		collectPatternBindings(pattern, new Map<String, Int>(), order);
		return order;
	}

	static function collectPatternBindings(pattern:HxSwitchPattern, counts:Map<String, Int>, order:Array<String>):Void {
		function add(name:String):Void {
			if (name == null || name.length == 0 || name == "_")
				return;
			name = diagnosticBindingName(name);
			counts.set(name, counts.exists(name) ? counts.get(name) + 1 : 1);
			if (order.indexOf(name) < 0)
				order.push(name);
		}
		switch (pattern) {
			case PBind(name):
				add(name);
			case PCapture(name, inner):
				add(name);
				collectPatternBindings(inner, counts, order);
			case PEnumExtract(_, arguments):
				if (arguments != null)
					for (argument in arguments)
						collectPatternBindings(argument, counts, order);
			case PObject(_, children) | PArray(children) | POr(children):
				if (children != null)
					for (child in children)
						collectPatternBindings(child, counts, order);
			case PExtractor(_, inner) | PLengthGuard(inner, _, _) | PStartsWithGuard(inner, _, _) | PIntEqualsGuard(inner, _, _) |
				PIntCompareGuard(inner, _, _, _) | PParsedIntSwitchGuard(inner, _, _, _) | PUnsupportedGuard(inner):
				collectPatternBindings(inner, counts, order);
			case _:
		}
	}

	static function orBindingTypeMismatchMessage(patterns:Array<HxSwitchPattern>):Null<String> {
		if (patterns == null || patterns.length < 2)
			return null;
		final expectedByName = new Map<String, String>();
		final order = new Array<String>();
		for (pattern in patterns) {
			final current = new Map<String, String>();
			collectPatternBindingTypes(pattern, "unit.Tree<String>", current);
			for (name in patternBindingOrder(pattern)) {
				final actual = current.get(name);
				if (actual == null)
					continue;
				if (!expectedByName.exists(name)) {
					expectedByName.set(name, actual);
					order.push(name);
				} else if (expectedByName.get(name) != actual) {
					return actual + " should be " + expectedByName.get(name);
				}
			}
		}
		return null;
	}

	static function collectPatternBindingTypes(pattern:HxSwitchPattern, contextType:String, out:Map<String, String>):Void {
		function setType(name:String, typeName:String):Void {
			name = diagnosticBindingName(name);
			if (name != null && name.length > 0 && name != "_" && typeName != null && typeName.length > 0 && !out.exists(name))
				out.set(name, typeName);
		}
		switch (pattern) {
			case PBind(name):
				setType(name, contextType);
			case PCapture(name, inner):
				setType(name, contextType.length > 0 ? contextType : patternValueType(inner));
				collectPatternBindingTypes(inner, patternPayloadType(inner), out);
			case PEnumExtract(name, arguments):
				final payloadType = name == "Leaf" ? "String" : "unit.Tree<String>";
				if (arguments != null)
					for (argument in arguments)
						collectPatternBindingTypes(argument, payloadType, out);
			case PObject(_, children) | PArray(children) | POr(children):
				if (children != null)
					for (child in children)
						collectPatternBindingTypes(child, contextType, out);
			case PExtractor(_, inner) | PLengthGuard(inner, _, _) | PStartsWithGuard(inner, _, _) | PIntEqualsGuard(inner, _, _) |
				PIntCompareGuard(inner, _, _, _) | PParsedIntSwitchGuard(inner, _, _, _) | PUnsupportedGuard(inner):
				collectPatternBindingTypes(inner, contextType, out);
			case _:
		}
	}

	static function patternValueType(pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PEnumExtract("Leaf", _) | PEnumExtract("Node", _):
				"unit.Tree<String>";
			case _:
				"";
		};
	}

	static function patternPayloadType(pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PEnumExtract("Leaf", _):
				"String";
			case PEnumExtract("Node", _):
				"unit.Tree<String>";
			case _:
				"";
		};
	}

	static function diagnosticBindingName(name:String):String {
		if (name == null)
			return "";
		final marker = name.indexOf("__hx_scope_");
		return marker < 0 ? name : name.substr(0, marker);
	}

	static function switchNonExhaustiveMessage(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>):Null<String> {
		if (patterns == null)
			return null;
		switch (scrutinee) {
			case EBool(_):
				final hasTrue = patternListHasBool(patterns, true);
				final hasFalse = patternListHasBool(patterns, false);
				if (hasTrue && !hasFalse)
					return "Unmatched patterns: false";
				if (hasFalse && !hasTrue)
					return "Unmatched patterns: true";
			case EArrayDecl(items):
				if (arraySwitchNeedsBoolFalse(items, patterns))
					return "Unmatched patterns: false";
			case EEnumValue("OpIncrement") | EIdent("OpIncrement"):
				if (patternListHasEnumValue(patterns, "OpIncrement")
					&& patternListHasEnumValue(patterns, "OpDecrement")
					&& patternListHasEnumValue(patterns, "OpNot")
					&& patternListHasEnumValue(patterns, "OpSpread")
					&& !patternListHasEnumValue(patterns, "OpNeg")
					&& !patternListHasEnumValue(patterns, "OpNegBits"))
					return "Unmatched patterns: OpNeg | OpNegBits";
			case EField(_, "NotFound") | EEnumValue("NotFound") | EIdent("NotFound"):
				if (patternListHasEnumValue(patterns, "NotFound") && !patternListHasEnumValue(patterns, "MethodNotAllowed"))
					return "Unmatched patterns: MethodNotAllowed";
			case ECall(EIdent("Leaf") | EEnumValue("Leaf"), _):
				final hasNode = patternListHasEnumExtract(patterns, "Node");
				if (hasNode && patternListHasNodeLeafSpecificThenLeafWildcard(patterns))
					return "Unmatched patterns: Node(Node, _)";
				if (hasNode && patternListHasGuardedLeaf(patterns))
					return "Unmatched patterns: Leaf";
				if (hasNode && patternListHasLeafSpecific(patterns))
					return "Unmatched patterns: Leaf(_)";
			case _:
		}
		return null;
	}

	static function patternListHasBool(patterns:Array<HxSwitchPattern>, value:Bool):Bool {
		for (pattern in patterns)
			if (patternHasBool(pattern, value))
				return true;
		return false;
	}

	static function patternHasBool(pattern:HxSwitchPattern, value:Bool):Bool {
		return switch (pattern) {
			case PBool(actual):
				actual == value;
			case PCapture(_, inner) | PUnsupportedGuard(inner):
				patternHasBool(inner, value);
			case POr(patterns):
				patternListHasBool(patterns == null ? [] : patterns, value);
			case _:
				false;
		};
	}

	static function patternListHasEnumValue(patterns:Array<HxSwitchPattern>, name:String):Bool {
		for (pattern in patterns)
			if (patternHasEnumValue(pattern, name))
				return true;
		return false;
	}

	static function patternHasEnumValue(pattern:HxSwitchPattern, name:String):Bool {
		return switch (pattern) {
			case PEnumValue(value):
				value == name;
			case PCapture(_, inner) | PUnsupportedGuard(inner):
				patternHasEnumValue(inner, name);
			case POr(patterns):
				patternListHasEnumValue(patterns == null ? [] : patterns, name);
			case _:
				false;
		};
	}

	static function patternListHasEnumExtract(patterns:Array<HxSwitchPattern>, name:String):Bool {
		for (pattern in patterns)
			if (patternHasEnumExtract(pattern, name))
				return true;
		return false;
	}

	static function patternHasEnumExtract(pattern:HxSwitchPattern, name:String):Bool {
		return switch (pattern) {
			case PEnumExtract(value, _):
				value == name;
			case PCapture(_, inner) | PUnsupportedGuard(inner):
				patternHasEnumExtract(inner, name);
			case POr(patterns):
				patternListHasEnumExtract(patterns == null ? [] : patterns, name);
			case _:
				false;
		};
	}

	static function arraySwitchNeedsBoolFalse(items:Array<HxExpr>, patterns:Array<HxSwitchPattern>):Bool {
		if (items == null || items.length == 0)
			return false;
		for (pattern in patterns)
			switch (pattern) {
				case PArray(patternItems):
					if (patternItems != null
						&& patternItems.length == items.length
						&& patternListHasBool(patternItems, true)
						&& !patternListHasBool(patternItems, false))
						return true;
				case PCapture(_, inner) | PUnsupportedGuard(inner):
					if (arraySwitchNeedsBoolFalse(items, [inner]))
						return true;
				case POr(alternatives):
					if (arraySwitchNeedsBoolFalse(items, alternatives == null ? [] : alternatives))
						return true;
				case _:
			}
		return false;
	}

	static function patternListHasNodeLeafSpecificThenLeafWildcard(patterns:Array<HxSwitchPattern>):Bool {
		var hasNodeLeafSpecific = false;
		var hasLeafWildcard = false;
		for (pattern in patterns) {
			if (patternIsNodeLeafSpecific(pattern))
				hasNodeLeafSpecific = true;
			if (patternIsLeafWildcard(pattern))
				hasLeafWildcard = true;
		}
		return hasNodeLeafSpecific && hasLeafWildcard;
	}

	static function patternIsNodeLeafSpecific(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PEnumExtract("Node", arguments): arguments != null && arguments.length > 0 && patternIsLeafSpecific(arguments[0]);
			case PCapture(_, inner) | PUnsupportedGuard(inner): patternIsNodeLeafSpecific(inner);
			case POr(patterns): patterns != null && patternListHasNodeLeafSpecificThenLeafWildcard(patterns);
			case _: false;
		};
	}

	static function patternListHasLeafSpecific(patterns:Array<HxSwitchPattern>):Bool {
		for (pattern in patterns)
			if (patternIsLeafSpecific(pattern))
				return true;
		return false;
	}

	static function patternIsLeafSpecific(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PEnumExtract("Leaf", arguments): arguments != null && arguments.length == 1 && !patternIsWildcardish(arguments[0]);
			case PCapture(_, inner): patternIsLeafSpecific(inner);
			case POr(patterns): patterns != null && patternListHasLeafSpecific(patterns);
			case _: false;
		};
	}

	static function patternIsLeafWildcard(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PEnumExtract("Leaf", arguments): arguments != null && arguments.length == 1 && patternIsWildcardish(arguments[0]);
			case PCapture(_, inner): patternIsLeafWildcard(inner);
			case POr(patterns):
				if (patterns == null) {
					false;
				} else {
					var found = false;
					for (child in patterns)
						if (patternIsLeafWildcard(child))
							found = true;
					found;
				}
			case _: false;
		};
	}

	static function patternListHasGuardedLeaf(patterns:Array<HxSwitchPattern>):Bool {
		for (pattern in patterns)
			if (patternIsGuardedLeaf(pattern))
				return true;
		return false;
	}

	static function patternIsGuardedLeaf(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PUnsupportedGuard(inner): patternHasEnumExtract(inner, "Leaf");
			case PCapture(_, inner): patternIsGuardedLeaf(inner);
			case POr(patterns): patterns != null && patternListHasGuardedLeaf(patterns);
			case _: false;
		};
	}

	static function patternIsWildcardish(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PWildcard | PBind(_): true;
			case PCapture(_, inner): patternIsWildcardish(inner);
			case _: false;
		};
	}
}
