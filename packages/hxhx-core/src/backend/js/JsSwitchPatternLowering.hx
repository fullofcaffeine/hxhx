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
	public static function lower(pattern:HxSwitchPattern, scrutineeVar:String):JsSwitchPatternLowered {
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
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(name), bindings: []};
			case PEnumExtract(name, args):
				lowerEnumExtract(name, args, scrutineeVar);
			case PObject(fieldNames, fieldPatterns):
				lowerObject(fieldNames, fieldPatterns, scrutineeVar);
			case PCapture(name, inner):
				final lowered = lower(inner, scrutineeVar);
				final bindings = copyBindings(lowered.bindings);
				bindings.push({name: name, expr: scrutineeVar});
				{cond: lowered.cond, bindings: bindings};
			case PArray(items):
				lowerArray(items, scrutineeVar);
			case PLengthGuard(inner, bindingName, length):
				final lowered = lower(inner, scrutineeVar);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + ".length === " + length;
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PStartsWithGuard(inner, bindingName, prefix):
				final lowered = lower(inner, scrutineeVar);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + ".startsWith(" + JsNameMangler.quoteString(prefix) + ")";
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PIntEqualsGuard(inner, bindingName, value):
				final lowered = lower(inner, scrutineeVar);
				final guardCond = lowerGuardBindingValue(bindingName, lowered.bindings) + " === " + Std.string(value);
				{cond: "(" + lowered.cond + ") && (" + guardCond + ")", bindings: lowered.bindings};
			case PUnsupportedGuard(inner):
				final lowered = lower(inner, scrutineeVar);
				{cond: "(" + lowered.cond + ") && false", bindings: lowered.bindings};
			case PBind(name):
				{cond: "true", bindings: [{name: name, expr: scrutineeVar}]};
			case POr(patterns):
				final parts = new Array<String>();
				var commonBindings:Null<Array<JsSwitchPatternBinding>> = null;
				for (p in patterns) {
					final lowered = lower(p, scrutineeVar);
					parts.push("(" + lowered.cond + ")");
					commonBindings = mergeCommonBindings(commonBindings, lowered.bindings);
				}
				{cond: parts.length == 0 ? "false" : parts.join(" || "), bindings: commonBindings == null ? [] : commonBindings};
		}
	}

	static function lowerEnumExtract(name:String, args:Array<HxSwitchPattern>, scrutineeVar:String):JsSwitchPatternLowered {
		final conds = [
			scrutineeVar + " != null",
			"typeof " + scrutineeVar + " === \"object\"",
			scrutineeVar + ".__hx_ctor === " + JsNameMangler.quoteString(name),
			"Array.isArray(" + scrutineeVar + ".__hx_params)"
		];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (args != null) {
			for (i in 0...args.length) {
				final paramExpr = scrutineeVar + ".__hx_params[" + i + "]";
				final lowered = lower(args[i], paramExpr);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerObject(fieldNames:Array<String>, fieldPatterns:Array<HxSwitchPattern>, scrutineeVar:String):JsSwitchPatternLowered {
		final conds = [scrutineeVar + " != null", "typeof " + scrutineeVar + " === \"object\""];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (fieldNames != null && fieldPatterns != null) {
			final count = fieldNames.length < fieldPatterns.length ? fieldNames.length : fieldPatterns.length;
			for (i in 0...count) {
				final fieldExpr = scrutineeVar + "." + JsNameMangler.identifier(fieldNames[i]);
				final lowered = lower(fieldPatterns[i], fieldExpr);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
	}

	static function lowerArray(items:Array<HxSwitchPattern>, scrutineeVar:String):JsSwitchPatternLowered {
		final count = items == null ? 0 : items.length;
		final conds = ["Array.isArray(" + scrutineeVar + ")", scrutineeVar + ".length === " + count];
		final bindings = new Array<JsSwitchPatternBinding>();
		if (items != null) {
			for (i in 0...items.length) {
				final itemExpr = scrutineeVar + "[" + i + "]";
				final lowered = lower(items[i], itemExpr);
				if (lowered.cond != "true")
					conds.push("(" + lowered.cond + ")");
				for (binding in lowered.bindings)
					bindings.push(binding);
			}
		}
		return {cond: conds.join(" && "), bindings: bindings};
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
