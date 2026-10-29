/** Valid forwarding with unrelated state restoration on success and failure. */
function restored<T>(state:{value:Int}, body:Void->T):T {
	if (state == null)
		return body();
	final saved = state.value;
	function restore():Void {
		state.value = saved;
	}
	try {
		final result = body();
		final alias = result;
		restore();
		return alias;
	} catch (error:haxe.Exception) {
		restore();
		throw error;
	}
}

/** A second declaration owns a different T even though its short name matches. */
function other<T>(body:Void->T):T {
	return body();
}

/** Inspecting a transported value requires an erased-value contract instead. */
function inspected<T>(body:Void->T):T {
	final value = body();
	Sys.println(value);
	return value;
}

/** Generic null creation does not prove preservation of the callback's carrier. */
function manufactured<T>(body:Void->T):T {
	return null;
}

/** Mutation is outside the initial immutable forwarding rule. */
function mutated<T>(body:Void->T):T {
	var value = body();
	value = body();
	return value;
}

/** Storing the input callback makes an invocation-only adapter observable. */
function escaped<T>(body:Void->T):T {
	final callbacks = [body];
	return callbacks[0]();
}

/** A nested function cannot silently inherit the enclosing transport owner. */
function captured<T>(body:Void->T):T {
	final nested = () -> body();
	return nested();
}

/** Manipulating generic container elements is not opaque whole-value transport. */
function elements<T>(body:Void->Array<T>):T {
	return body()[0];
}
