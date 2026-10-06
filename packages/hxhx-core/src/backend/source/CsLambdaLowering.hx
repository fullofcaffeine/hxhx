package backend.source;

/** A checked callback signature and the structurally lowered function it describes. */
typedef CsLoweredLambda = {
	final delegateType:String;
	final arguments:Array<String>;
	final body:HxExpr;
};

/**
	Keep a C# callback's exact callable type before source-shaped rewrites copy it.

	Only a lambda retained by the current typed function projection can select a
	delegate signature. Shared control lowering owns return and loop destinations;
	C# consumes its statement adapter instead of synthesizing expression returns.
**/
function body(projection:TypedBackendFunctionProjection, program:backend.GenIrProgram, noRoot:Bool):Array<HxStmt> {
	var locals:Null<SourceNativeFunctionLocals> = null;
	return SourceFunctionBodyRewriter.bodyWithOriginal(projection.getBody(), (original, rebuilt) -> {
		switch original {
			case ELambda(_, ELoweredControl(FunctionBody, _, _, _)):
				final occurrence = projection.findLambda(original);
				if (occurrence == null)
					throw "C# callback requires its exact typed lambda occurrence";
				if (locals == null)
					locals = new SourceNativeFunctionLocals({
						target: Cs,
						program: program,
						projection: projection,
						noRoot: noRoot
					});
				final parameters = occurrence.callableType.getFunctionParameters();
				final types = new Array<String>();
				for (parameter in parameters) {
					if (parameter.isOptional || parameter.isRest)
						throw "C# optional/rest callbacks require a checked invocation adapter";
					types.push(locals.typeName(parameter.type));
				}
				final result = occurrence.callableType.getFunctionReturn();
				if (result == null)
					throw "C# callback lost its checked result type";
				if (!result.isVoid())
					types.push(locals.typeName(result));
				final delegateType = "System." + (result.isVoid() ? "Action" : "Func") + (types.length == 0 ? "" : "<" + types.join(", ") + ">");
				return ECall(EUnsupported(marker()), [EString(delegateType), rebuilt]);
			case ECast(ELambda(_, _), hint) if (hint.indexOf("->") >= 0):
				switch rebuilt {
					case ECast(inner, _) if (decode(inner) != null): return inner;
					case _:
				}
			case _:
		}
		return rebuilt;
	});
}

/** Decode only this target's internal transport, never an authored Haxe call. */
function decode(expression:HxExpr):Null<CsLoweredLambda> {
	return switch expression {
		case ECall(EUnsupported(name), [EString(delegateType), ELambda(arguments, body)]) if (name == marker()):
			{delegateType: delegateType, arguments: arguments.copy(), body: body};
		case _: null;
	};
}

private inline function marker():String
	return "$hxhx:cs-typed-lambda";
