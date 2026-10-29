import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

/** Raw comprehensions require typed lowering; the preceding HXML stage proves their runtime behavior. */
class M14JsExprEmitterArrayComprehensionIntegrationTest {
	static function assertRawRejected(expression:HxExpr, scope:backend.js.JsEmitScope, label:String):Void {
		try {
			JsExprEmitter.emit(expression, scope);
		} catch (message:String) {
			if (message.indexOf("source control must be lowered before JavaScript emission") < 0)
				throw label + ": unexpected rejection: " + message;
			return;
		}
		throw label + ": raw source unexpectedly bypassed typed lowering";
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final rangeExpr = HxParser.parseExprText("[for (i in 0...3) i * 2]");
		assertRawRejected(rangeExpr, exprScope, "range comprehension");

		final iterExpr = HxParser.parseExprText("[for (value in values) value + 1]");
		assertRawRejected(iterExpr, exprScope, "iterable comprehension");

		final guardedExpr = HxParser.parseExprText("[for (value in values) if (keep(value)) value]");
		assertRawRejected(guardedExpr, exprScope, "guarded comprehension");

		final staticNamesInit = HxParser.parseExprText('["ok", [for (i in 0...100) "a"].join(""),].concat(switch Sys.systemName() { case "Windows": []; case _: [
			#if !(python || neko || cpp || java || cs)
			[for (i in 0...255) "b"].join(""),
			#end
		]; })');
		assertRawRejected(staticNamesInit, exprScope, "static initializer with switch argument");

		final scannedModule = new HxParser('class FileNames {
			static public var names(default, never) = [
				"ok",
				[for (i in 0...100) "a"].join(""),
			].concat(switch (Sys.systemName()) {
				case "Windows":
					[];
				case _:
				[
					#if !(python || neko || cpp || java || cs)
					[for (i in 0...255) "b"].join(""),
					#end
				];
			});
		}').parseModule("FileNames");
		final scannedFields = HxClassDecl.getFields(HxModuleDecl.getMainClass(scannedModule));
		if (scannedFields.length != 1)
			throw "expected one scanned static field";
		final scannedInit = HxFieldDecl.getInit(scannedFields[0]);
		if (scannedInit == null)
			throw "expected FileNames.names static initializer to parse through scanner path";
		assertRawRejected(scannedInit, exprScope, "scanned static initializer");
		Sys.println("JS_RAW_COMPREHENSION_BOUNDARY:PASS");
	}
}
