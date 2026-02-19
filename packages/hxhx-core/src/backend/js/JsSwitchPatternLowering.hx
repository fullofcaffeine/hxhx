package backend.js;

/**
	Shared switch-pattern lowering for js-native statement/expression emitters.

	Why
	- Statement and expression switch lowering need the same pattern semantics.
	- Keeping this in one place avoids drift while js-native coverage expands.
**/
class JsSwitchPatternLowering {
	public static function lower(pattern:HxSwitchPattern, scrutineeVar:String):{cond:String, bindName:Null<String>} {
		return switch (pattern) {
			case PNull:
				{cond: scrutineeVar + " == null", bindName: null};
			case PWildcard:
				{cond: "true", bindName: null};
			case PString(value):
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(value), bindName: null};
			case PInt(value):
				{cond: scrutineeVar + " === " + Std.string(value), bindName: null};
			case PEnumValue(name):
				{cond: scrutineeVar + " === " + JsNameMangler.quoteString(name), bindName: null};
			case PBind(name):
				{cond: "true", bindName: name};
			case POr(patterns):
				final parts = new Array<String>();
				for (p in patterns) {
					final lowered = lower(p, scrutineeVar);
					parts.push("(" + lowered.cond + ")");
				}
				{cond: parts.length == 0 ? "false" : parts.join(" || "), bindName: null};
		}
	}
}
