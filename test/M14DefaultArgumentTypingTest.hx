/** Source defaults permit omission without changing the parameter or call-result value type. */
class M14DefaultArgumentTypingTest {
	static function constructor(defaultText:String):TypedFunction {
		final source = 'class Box { public function new(value:String = ' + defaultText + ') {} }';
		final resolved = new ResolvedModule("Box", "Box.hx", ParserStage.parse(source, "Box.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
	}

	/** A changed default changes function meaning even when its body is empty. */
	static function checkDefaultRevision():Void {
		final first = constructor('"first"');
		final second = constructor('"second"');
		if (CompilerTypedTreeRevision.functionBody(first) == CompilerTypedTreeRevision.functionBody(second))
			throw "changed constructor default retained the old semantic revision";
		final defaults = first.getDefaults();
		if (defaults.length != 1
			|| defaults[0].getParameterIndex() != 0
			|| defaults[0].getExpression().getType().getSemanticKey() != "primitive:String")
			throw "constructor default lost its slot or checked String type";
		defaults.pop();
		if (first.getDefaults().length != 1 || first.withBody(first.getBody()).getDefaults()[0] != first.getDefaults()[0])
			throw "body lowering or a caller changed retained defaults";
		final arguments = HxFunctionDecl.getArgs(first.getSourceDeclaration());
		arguments[0] = HxFunctionDecl.getArgs(second.getSourceDeclaration())[0];
		var rejected = false;
		try {
			first.withBody(first.getBody());
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("revision mismatch") >= 0;
		}
		if (!rejected)
			throw "changed source default was accepted by body lowering";
		rejected = false;
		try {
			TypedBodySource.functionProjection(first);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("revision mismatch") >= 0;
		}
		if (!rejected)
			throw "changed source default was accepted by backend projection";
	}

	/** Defaults participate in input inference and reject incompatible written types. */
	static function checkDefaultTypes():Void {
		final source = 'class Defaults { static function inferred(value = 4):Int return value; static function nullable(value:Int = (null)):Void {} }';
		final resolved = new ResolvedModule("Defaults", "Defaults.hx", ParserStage.parse(source, "Defaults.hx"));
		final functions = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions();
		final fn = functions[0];
		if (fn.getEnvironment().getParams()[0].getType().getSemanticKey() != "primitive:Int")
			throw "default did not infer the body parameter type";
		if (functions[1].getEnvironment().getParams()[0].getType().getSemanticKey() != "nullable:primitive:Int")
			throw "an explicit null default lost its nullable body type";
		final previous = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		var rejected = false;
		try {
			final bad = new ResolvedModule("Bad", "Bad.hx", ParserStage.parse('class Bad { static function bad(value:Int = "wrong"):Void {} }', "Bad.hx"));
			TyperStage.typeResolvedModule(bad, TyperIndex.build([bad]));
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("String") >= 0 && error.message.indexOf("not compatible with Int") >= 0;
		}
		Sys.putEnv("HXHX_TYPER_STRICT", previous == null ? "" : previous);
		if (!rejected)
			throw "incompatible declared default was accepted";
	}

	/** Cached body inference must read exact default syntax, not stale source text. */
	static function checkInferredResultFreshness():Void {
		final source = 'class Defaults { public static function value(text = "Aa") return text; }';
		final resolved = new ResolvedModule("Defaults", "Defaults.hx", ParserStage.parse(source, "Defaults.hx"));
		final index = TyperIndex.build([resolved]);
		final fn = TyperStage.typeResolvedModule(resolved, index).getTypedClasses()[0].getFunctions()[0];
		if (index.getMethodBodyResults().result(fn.getDeclaration()).getSemanticKey() != "primitive:String")
			throw "default did not infer the method result";
		final arguments = HxFunctionDecl.getArgs(fn.getSourceDeclaration());
		final original = arguments[0];
		arguments[0] = new HxFunctionArg(original.name, original.typeHint, HxDefaultValue.Default(HxExpr.EString("BB")), original.isOptional, original.isRest,
			original.defaultValueText, original.metadata);
		var rejected = false;
		try {
			index.getMethodBodyResults().result(fn.getDeclaration());
		} catch (error:haxe.Exception) {
			rejected = error.message == "method body result belongs to a changed declaration";
		}
		if (!rejected)
			throw "changed parsed default retained cached parameter and result inference";
	}

	public static function run():Void {
		checkDefaultRevision();
		checkDefaultTypes();
		checkInferredResultFreshness();
		final source = 'class Defaults {
 static function probe():Void {
  Receiver.staticAnswer();
  Receiver.staticAnswer(false);
  new Receiver();
  var receiver = new Receiver();
  receiver.answer();
  receiver.answer(false);
 }
}
class Receiver {
 public function new(value:Int = 4) {}
 public function answer(value:Bool = true):Bool return value;
 public static function staticAnswer(value:Bool = true):Bool return value;
 public static function required(value:Bool):Bool return value;
 public static function optional(?value:Bool):Bool return value == true;
}';
		final resolved = new ResolvedModule("Defaults", "Defaults.hx", ParserStage.parse(source, "Defaults.hx"));
		final index = TyperIndex.build([resolved]);
		final receiver = index.getByFullName("Defaults.Receiver");
		if (receiver == null)
			throw "Default argument fixture lost its indexed receiver";
		for (signature in [
			receiver.staticMethodCandidates("staticAnswer")[0],
			receiver.instanceMethodCandidates("answer")[0],
			receiver.instanceMethodCandidates("new")[0]
		]) {
			if (!signature.acceptsArity(0) || !signature.acceptsArity(1) || !signature.getArgOptional()[0])
				throw "A source default must permit omission: " + signature.getName();
			if (signature.getArgs()[0].getDisplay() != (signature.getName() == "new" ? "Int" : "Bool"))
				throw "Default argument optionality changed the declared value type";
		}
		if (receiver.staticMethodCandidates("required")[0].acceptsArity(0)
			|| !receiver.staticMethodCandidates("optional")[0].acceptsArity(0))
			throw "Default handling changed required or question-mark optional arity";
		final typed = TyperStage.typeResolvedModule(resolved, index);
		for (owner in typed.getTypedClasses()) {
			if (HxClassDecl.getName(owner.getSourceDeclaration()) != "Defaults")
				continue;
			final statements = owner.getFunctions()[0].getBody().getStatements();
			final omitted = statements[0].getExpressions()[0];
			final supplied = statements[1].getExpressions()[0];
			if (omitted.getType().getDisplay() != "Bool" || supplied.getType().getDisplay() != "Bool")
				throw "Omitting a default lost the concrete call result";
			if (omitted.getDeclaration() == null || omitted.getDeclaration() != supplied.getDeclaration())
				throw "Omitting a default changed the selected declaration";
			final omittedInstance = statements[4].getExpressions()[0];
			final suppliedInstance = statements[5].getExpressions()[0];
			if (omittedInstance.getType().getDisplay() != "Bool"
				|| suppliedInstance.getType().getDisplay() != "Bool"
				|| omittedInstance.getDeclaration() == null
				|| omittedInstance.getDeclaration() != suppliedInstance.getDeclaration())
				throw "Instance default omission lost its result or selected declaration";
			if (statements[2].getExpressions()[0].getType().getDisplay() == "Unknown")
				throw "Constructor default omission lost its result type";
		}
		Sys.println("DEFAULT_ARGUMENT_TYPING:PASS");
	}

	static function main():Void
		run();
}
