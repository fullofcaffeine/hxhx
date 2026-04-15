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
			case PString(value):
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(value), bindings: []};
			case PInt(value):
				{cond: scrutineeVar + " === " + Std.string(value), bindings: []};
			case PEnumValue(name):
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(name), bindings: []};
			case PEnumExtract(name, args):
				lowerEnumExtract(name, args, scrutineeVar);
			case PBind(name):
				{cond: "true", bindings: [{name: name, expr: scrutineeVar}]};
			case POr(patterns):
				final parts = new Array<String>();
				for (p in patterns) {
					final lowered = lower(p, scrutineeVar);
					parts.push("(" + lowered.cond + ")");
				}
				{cond: parts.length == 0 ? "false" : parts.join(" || "), bindings: []};
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
}
