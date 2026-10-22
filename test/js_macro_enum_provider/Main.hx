/** Quoted expressions must carry real macro enum metadata in a JavaScript program. */
class Main {
	static function main():Void {
		final quoted = macro value?.field;
		js.Syntax.code("console.log({0})", Type.enumConstructor(quoted.expr));
		js.Syntax.code("console.log({0})", Type.enumParameters(quoted.expr).length);
		// Reflection returns dynamic payloads; consume each immediately through
		// the enum API, which must recognize its retained declaration metadata.
		js.Syntax.code("console.log({0})", Type.enumConstructor(Type.enumParameters(quoted.expr)[2]));
		final constant = macro 7;
		js.Syntax.code("console.log({0})", Type.enumConstructor(Type.enumParameters(constant.expr)[0]));
		final binary = macro value += 2;
		js.Syntax.code("console.log({0})", Type.enumConstructor(Type.enumParameters(binary.expr)[0]));
		final functionType = macro :Int->String;
		js.Syntax.code("console.log({0})", Type.enumConstructor(functionType));
		js.Syntax.code("console.log({0})", Type.enumParameters(functionType).length);
	}
}
