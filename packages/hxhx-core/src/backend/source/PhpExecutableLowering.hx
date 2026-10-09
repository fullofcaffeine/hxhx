package backend.source;

/** PHP-only closure transport produced after exact occurrence validation. */
typedef PhpClosureOperation = {
	final arguments:Array<String>;
	final body:HxExpr;
	final signature:Null<HxLambdaSignature>;
	final captures:Array<String>;
	final capturesReceiver:Bool;
}

private final closureMarker = "\x00hxhx.php.closure";

/**
	Consume original typed occurrences before PHP's syntax rewrites copy nodes.
	Runtime operands and closures share one postorder traversal, so neither
	consults another pass's reconstructed expression as semantic authority.
**/
function body(renderer:PhpFunctionBodyRenderer, statements:Array<HxStmt>):Array<HxStmt>
	return SourceFunctionBodyRewriter.bodyWithOriginal(statements, (original, rebuilt) -> lower(renderer, original, rebuilt));

function expression(renderer:PhpFunctionBodyRenderer, value:HxExpr):HxExpr
	return SourceFunctionBodyRewriter.expressionWithOriginal(value, (original, rebuilt) -> lower(renderer, original, rebuilt));

private function lower(renderer:PhpFunctionBodyRenderer, original:HxExpr, rebuilt:HxExpr):HxExpr {
	switch original {
		case ELambda(_, _):
			final storage = renderer.getPlan().getCaptureStorage();
			final facts = storage.requireClosure(original);
			return ECall(EUnsupported(closureMarker), [
				rebuilt,
				EArrayDecl([for (name in storage.captureNames(original)) EString(name)]),
				EBool(facts.capturesReceiver)
			]);
		case _:
			return PhpRuntimeTypeLowering.lower(renderer, original, rebuilt);
	}
}

/** This target operation cannot be authored by Haxe source or inferred from a readable name. */
function decodeClosure(value:HxExpr):Null<PhpClosureOperation> {
	return switch value {
		case ECall(EUnsupported(tag), [ELambda(arguments, body, signature), EArrayDecl(captures), EBool(receiver)]) if (tag == closureMarker):
			{
				arguments: arguments,
				body: body,
				signature: signature,
				captures: [
					for (capture in captures)
						switch capture {
							case EString(name):
								name;
							case _:
								throw "PHP closure operation contains an invalid capture";
						}
				],
				capturesReceiver: receiver
			};
		case ECall(EUnsupported(tag), _) if (tag == closureMarker):
			throw "PHP closure operation has an invalid layout";
		case _: null;
	};
}
