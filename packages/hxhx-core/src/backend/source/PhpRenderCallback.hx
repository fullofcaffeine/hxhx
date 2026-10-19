package backend.source;

/**
	Invokes the legacy program renderer callback once and returns its value unchanged.

	The enum hint does not install ambient state. Function-owned rendering resolves
	enum owners through its explicit PhpLexicalRenderScope instead. Keep this existing
	callback boundary independent of the emitter dependency cycle so native compilation
	can infer its generic result without constraining it to one caller's result type.
**/
function withPhpPreferredEnum<T>(enumName:Null<String>, f:() -> T):T {
	return f();
}
