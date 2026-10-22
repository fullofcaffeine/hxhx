/** Preserves a generic callback result across both direct and caught returns. */
function isolate<T>(direct:Bool, body:Void->T):T {
	if (direct)
		return body();
	try {
		return body();
	} catch (error:haxe.Exception) {
		throw error;
	}
}

/** Restores unrelated state while retaining the callback's exact value and identity. */
function restored<T>(state:Box, body:Void->T):T {
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
