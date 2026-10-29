/** Keeps a generic callback result across an exception boundary. */
function isolate<T>(body:Void->T):T {
	try {
		return body();
	} catch (error:haxe.Exception) {
		throw error;
	}
}
