/** Exact iterable/query identities and function ownership survive only legitimate replay. */
class M14KeyValueProtocolFactsTest {
	static function rejected(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message != expected)
				throw error;
			return;
		}
		throw "iterator protocol accepted invalid facts: " + expected;
	}

	public static function run():Void {
		final owner = "Main.first";
		final arguments:Array<HxExpr> = [];
		final source:HxExpr = ECall(EIdent("source"), arguments);
		final inference = new TyFunctionInference(owner);
		final record = inference.keyValueProtocolSource(source, value -> new TyKeyValueProtocolSource(value, owner));
		if (record.owns(ECall(EIdent("source"), [])))
			throw "equal source text replaced an exact iterator occurrence";
		final foreign = new TyFunctionInference("Main.other");
		rejected(() -> {
			foreign.keyValueProtocolSource(source, _ -> record);
		}, "iterator protocol belongs to another inference owner");
		final copiedSource:HxExpr = ECall(EIdent("source"), []);
		rejected(() -> {
			inference.keyValueProtocolSource(copiedSource, _ -> record);
		}, "selected iterator protocol belongs to another source occurrence");
		inference.seal([]);
		if (inference.keyValueProtocolSource(source) != record || inference.fork().keyValueProtocolSource(source) != record)
			throw "sealed replay or speculation replaced selected query occurrences";
		rejected(() -> {
			inference.keyValueProtocolSource(copiedSource);
		}, "iterator protocol source is absent from sealed inference");
		arguments.push(EInt(1));
		rejected(() -> {
			inference.keyValueProtocolSource(source);
		}, "iterator source or protocol queries changed after inference selection");
		arguments.pop();
		switch record.next {
			case ECall(_, operands):
				operands.push(EInt(1));
				rejected(() -> {
					inference.keyValueProtocolSource(source);
				}, "iterator source or protocol queries changed after inference selection");
				operands.pop();
			case _:
				throw "iterator next query must remain a call";
		}
		if (inference.keyValueProtocolSource(source) != record)
			throw "restored immutable facts did not retain their selected record";
		assertScopedSourceReference(source, copiedSource, arguments);
		Sys.println("KEY_VALUE_PROTOCOL_FACTS:PASS");
	}

	/** A query reference cannot escape its scope, authorize copied syntax, or survive source mutation. */
	static function assertScopedSourceReference(source:HxExpr, copiedSource:HxExpr, arguments:Array<HxExpr>):Void {
		final type = TyType.fromHintText("Int");
		final environment = new TyFunctionEnv("main", [], [], type, type, "Main.main");
		final foreign = new TyFunctionEnv("other", [], [], type, type, "Main.other");
		final typed = TypedExpr.intLiteral(7, type, HxPos.unknown());
		environment.withProtocolSource(source, type, () -> {
			if (environment.protocolSourceType(source) != type
				|| environment.protocolSourceExpression(source) != typed
				|| environment.copyForInference().protocolSourceExpression(source) != typed)
				throw "query did not retain the checked source expression";
			if (environment.protocolSourceType(copiedSource) != null || foreign.protocolSourceType(source) != null)
				throw "query reference authorized foreign syntax or another environment";
			environment.withProtocolSource(copiedSource, type, () -> {
				if (environment.protocolSourceType(source) != null)
					throw "nested query retained the wrong source occurrence";
			});
			if (environment.protocolSourceExpression(source) != typed)
				throw "nested query failed to restore its enclosing reference";
		}, typed);
		if (environment.protocolSourceType(source) != null)
			throw "query reference escaped successful completion";
		rejected(() -> environment.withProtocolSource(source, type, () -> {
			arguments.push(EInt(1));
			environment.protocolSourceType(source);
		}), "protocol source changed during its checked query");
		arguments.pop();
		if (environment.protocolSourceType(source) != null)
			throw "query reference escaped a diagnostic";
		rejected(() -> environment.withProtocolSource(source, type, () -> {}, TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), HxPos.unknown())),
			"protocol source reference changed its checked type");
	}

	static function main():Void
		run();
}
