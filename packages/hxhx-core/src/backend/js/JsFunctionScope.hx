package backend.js;

/**
	Function-local symbol scope for JS emission.

	Why
	- Stage3 AST keeps original Haxe identifiers; JS emission needs deterministic, valid local names.
	- A shared scope object keeps statement and expression lowering consistent.
**/
class JsFunctionScope {
	final locals:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	final used:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
	final classRefs:haxe.ds.StringMap<String>;
	var tempCounter:Int = 0;

	public function new(classRefs:haxe.ds.StringMap<String>) {
		this.classRefs = classRefs == null ? new haxe.ds.StringMap<String>() : classRefs;
	}

	function reserve(name:String):String {
		var candidate = JsNameMangler.identifier(name);
		if (candidate.length == 0)
			candidate = "_";
		if (!used.exists(candidate)) {
			used.set(candidate, true);
			return candidate;
		}
		var suffix = 1;
		while (used.exists(candidate + "_" + suffix))
			suffix++;
		final unique = candidate + "_" + suffix;
		used.set(unique, true);
		return unique;
	}

	public function declareLocal(raw:String):String {
		final existing = locals.get(raw);
		if (existing != null)
			return existing;
		final safe = reserve(raw);
		locals.set(raw, safe);
		return safe;
	}

	public function resolveLocal(raw:String):Null<String> {
		return locals.get(raw);
	}

	public function resolveClassRef(raw:String):Null<String> {
		return classRefs.get(raw);
	}

	public function freshTemp(prefix:String):String {
		final base = prefix == null || prefix.length == 0 ? "__tmp" : prefix;
		while (true) {
			final name = reserve(base + "_" + tempCounter);
			tempCounter++;
			if (name != null && name.length > 0)
				return name;
		}
		return reserve("__tmp_fallback");
	}

	public function exprScope():JsEmitScope {
		final self = this;
		return {
			resolveLocal: function(name:String):Null<String> return self.resolveLocal(name),
			resolveClassRef: function(name:String):Null<String> return self.resolveClassRef(name)
		};
	}
}
