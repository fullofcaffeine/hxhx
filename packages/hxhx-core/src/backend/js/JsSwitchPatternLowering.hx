package backend.js;

typedef JsSwitchPatternBinding = {
	final name:String;
	final expr:String;
};

typedef JsSwitchPatternLowered = {
	final cond:String;
	final bindings:Array<JsSwitchPatternBinding>;
};

/**
	Shared switch-pattern lowering for js-native statement/expression emitters.

	Why
	- Statement and expression switch lowering need the same pattern semantics.
	- Keeping this in one place avoids drift while js-native coverage expands.
**/
class JsSwitchPatternLowering {
	public static function lower(pattern:HxSwitchPattern, scrutineeVar:String, ?scope:JsEmitScope):JsSwitchPatternLowered {
		return switch (pattern) {
			case PNull:
				{cond: scrutineeVar + " == null", bindings: []};
			case PWildcard:
				{cond: "true", bindings: []};
			case PBool(value):
				{cond: scrutineeVar + " === " + (value ? "true" : "false"), bindings: []};
			case PString(value):
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(value), bindings: []};
			case PInt(value):
				{cond: scrutineeVar + " === " + Std.string(value), bindings: []};
			case PEnumValue(name):
				lowerNamed(pattern, [], scrutineeVar, scope);
			case PEnumExtract(name, args):
				lowerNamed(pattern, args, scrutineeVar, scope);
			case PObject(fieldNames, fieldPatterns):
				lowerObject(fieldNames, fieldPatterns, scrutineeVar, scope);
			case PCapture(name, inner):
				final lowered = lower(inner, scrutineeVar, scope);
				final bindings = copyBindings(lowered.bindings);
				bindings.push({name: name, expr: scrutineeVar});
				{cond: lowered.cond, bindings: bindings};
			case PArray(items):
				lowerArray(items, scrutineeVar, scope);
			case PExtractor(extractorText, resultPattern):
				lowerExtractor(extractorText, resultPattern, scrutineeVar, scope);
			case PLengthGuard(inner, bindingName, length):
				final lowered = lower(inner, scrutineeVar, scope);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + ".length === " + length;
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PStartsWithGuard(inner, bindingName, prefix):
				final lowered = lower(inner, scrutineeVar, scope);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + ".startsWith(" + JsNameMangler.quoteString(prefix) + ")";
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PIntEqualsGuard(inner, bindingName, value):
				final lowered = lower(inner, scrutineeVar, scope);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + " === " + Std.string(value);
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PIntCompareGuard(inner, bindingName, op, value):
				final lowered = lower(inner, scrutineeVar, scope);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + " " + op + " " + Std.string(value);
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PUnsupportedGuard(inner):
				final lowered = lower(inner, scrutineeVar, scope);
				{cond: "(" + lowered.cond + ") && false", bindings: lowered.bindings};
			case PParsedIntSwitchGuard(inner, _, _, _):
				final lowered = lower(inner, scrutineeVar, scope);
				{cond: "(" + lowered.cond + ") && false", bindings: lowered.bindings};
			case PBind(name):
				{cond: "true", bindings: [{name: name, expr: scrutineeVar}]};
			case POr(patterns):
				final parts = new Array<String>();
				var commonBindings:Null<Array<JsSwitchPatternBinding>> = null;
				for (p in patterns) {
					final lowered = lower(p, scrutineeVar, scope);
					parts.push("(" + lowered.cond + ")");
					commonBindings = mergeCommonBindings(commonBindings, lowered.bindings);
				}
				{cond: parts.length == 0 ? "false" : parts.join(" || "), bindings: commonBindings == null ? [] : commonBindings};
		}
	}

	/** Use the selected declaration's representation; constructor spellings alone never choose a match. */
	static function lowerNamed(pattern:HxSwitchPattern, args:Array<HxSwitchPattern>, scrutineeVar:String, scope:Null<JsEmitScope>):JsSwitchPatternLowered {
		final selected = scope == null || scope.namedPatterns == null ? null : scope.namedPatterns(pattern);
		if (selected == null)
			throw "JavaScript named pattern requires its exact selected declaration";
		return switch selected.getKind() {
			case Constant(field):
				if (args.length != 0)
					throw "enum-abstract constant cannot have payload patterns";
				final value = field.getConstant().project();
				if (value == null)
					throw "named constant pattern requires a resolved value";
				{cond: scrutineeVar + " === " + JsExprEmitter.emit(value, scope), bindings: []};
			case Constructor(identity, name, index, arity):
				if (scope.enumDeclarations == null)
					throw "JavaScript named pattern requires its retained enum provider";
				final owner = scope.enumDeclarations(identity.getCanonicalName());
				if (owner == null || owner.enumConstructors == null || index < 0 || index >= owner.enumConstructors.length)
					throw "JavaScript pattern enum declaration differs from typing";
				final constructor = owner.enumConstructors[index];
				if (constructor.name != name
					|| constructor.index != index
					|| arity != args.length
					|| (constructor.parameters == null ? 0 : constructor.parameters.length) != arity)
					throw "JavaScript pattern constructor differs from typing";
				final reference = owner.reference + JsNameMangler.propertySuffix(name);
				if (constructor.parameters == null) {
					{cond: scrutineeVar + " === " + reference, bindings: []};
				} else {
					lowerEnumExtract(reference, constructor.parameters, args, scrutineeVar, scope);
				}
		};
	}

	static function lowerEnumExtract(reference:String, parameters:Array<String>, args:Array<HxSwitchPattern>, scrutineeVar:String,
			scope:JsEmitScope):JsSwitchPatternLowered {
		final conds = [
			scrutineeVar + " != null",
			"$hx_enum_constructor(" + scrutineeVar + ") === " + reference
		];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (args != null) {
			for (i in 0...args.length) {
				final paramExpr = scrutineeVar + JsNameMangler.propertySuffix(parameters[i]);
				final lowered = lower(args[i], paramExpr, scope);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerObject(fieldNames:Array<String>, fieldPatterns:Array<HxSwitchPattern>, scrutineeVar:String,
			scope:Null<JsEmitScope>):JsSwitchPatternLowered {
		final conds = [scrutineeVar + " != null", "typeof " + scrutineeVar + " === \"object\""];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (fieldNames != null && fieldPatterns != null) {
			final count = fieldNames.length < fieldPatterns.length ? fieldNames.length : fieldPatterns.length;
			for (i in 0...count) {
				final fieldExpr = scrutineeVar + "." + JsNameMangler.identifier(fieldNames[i]);
				final lowered = lower(fieldPatterns[i], fieldExpr, scope);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerArray(items:Array<HxSwitchPattern>, scrutineeVar:String, scope:Null<JsEmitScope>):JsSwitchPatternLowered {
		final count = items == null ? 0 : items.length;
		final conds = ["Array.isArray(" + scrutineeVar + ")", scrutineeVar + ".length === " + count];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (items != null) {
			for (i in 0...items.length) {
				final itemExpr = scrutineeVar + "[" + i + "]";
				final lowered = lower(items[i], itemExpr, scope);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerExtractor(extractorText:String, resultPattern:HxSwitchPattern, scrutineeVar:String, scope:Null<JsEmitScope>):JsSwitchPatternLowered {
		final applied = switch (StringTools.trim(extractorText)) {
			case "Std.parseInt(_)":
				"parseInt(" + scrutineeVar + ", 10)";
			case "_.slice(0, 1)" | "_.slice(0,1)":
				scrutineeVar + ".slice(0, 1)";
			case _:
				null;
		}
		final lowered = lower(resultPattern, applied == null ? scrutineeVar : applied, scope);
		if (applied == null)
			return {cond: "false", bindings: lowered.bindings};
		return lowered;
	}

	static function lowerGuardBindingValue(name:String, bindings:Array<JsSwitchPatternBinding>):String {
		if (bindings != null) {
			for (binding in bindings) {
				if (binding.name == name)
					return binding.expr;
			}
		}
		return JsNameMangler.identifier(name);
	}

	static function mergeCommonBindings(existing:Null<Array<JsSwitchPatternBinding>>, next:Array<JsSwitchPatternBinding>):Array<JsSwitchPatternBinding> {
		if (existing == null)
			return copyBindings(next);
		if (next == null || existing.length != next.length)
			return [];
		final out = new Array<JsSwitchPatternBinding>();
		for (binding in existing) {
			var found = false;
			for (candidate in next) {
				if (candidate.name == binding.name && candidate.expr == binding.expr) {
					found = true;
					break;
				}
			}
			if (!found)
				return [];
			out.push(binding);
		}
		return out;
	}

	static function copyBindings(bindings:Array<JsSwitchPatternBinding>):Array<JsSwitchPatternBinding> {
		final out = new Array<JsSwitchPatternBinding>();
		if (bindings != null) {
			for (binding in bindings)
				out.push({name: binding.name, expr: binding.expr});
		}
		return out;
	}
}
