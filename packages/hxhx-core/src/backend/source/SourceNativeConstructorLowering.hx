package backend.source;

/** Construction representation selected before target rewrites copy the original occurrence. */
enum SourceNativeConstructionKind {
	EmittedClass(name:String);
	Runtime(path:String);
}

/** Selected native representation and argument expressions retained across target rewrites. */
typedef SourceNativeConstruction = {
	final target:SourceNativeTarget;
	final kind:SourceNativeConstructionKind;
	final arguments:Array<HxExpr>;
};

/**
	Keep an authored class's emitted owner before Java/C# copy executable syntax.

	Only an exact constructor occurrence can create this internal transport.
	Arguments come from the recursive rewrite, preserving nested lowering and
	source order. Extern and target-runtime allocations retain their own lowering.
 */
class SourceNativeConstructorLowering {
	static inline function marker():String
		return "$hxhx:native-class-constructor";

	public static function expression(locals:SourceNativeFunctionLocals, original:HxExpr, rebuilt:HxExpr):HxExpr {
		return switch original {
			case ENew(path, _):
				final name = locals.constructorName(original);
				switch rebuilt {
					case ENew(_, arguments):
						ECall(EUnsupported(marker()), [
							EString(locals.target == Java ? "java" : "cs"),
							EString(name == null ? "runtime" : "class"),
							EString(name == null ? path : name),
							EArrayDecl(arguments.copy())
						]);
					case _: throw "native constructor rewrite changed its expression kind";
				}
			case _: rebuilt;
		};
	}

	public static function body(locals:SourceNativeFunctionLocals, statements:Array<HxStmt>):Array<HxStmt>
		return SourceFunctionBodyRewriter.bodyWithOriginal(statements, (original, rebuilt) -> expression(locals, original, rebuilt));

	/** Malformed internal transport is an invariant failure, never an ordinary call. */
	public static function decode(expression:HxExpr):Null<SourceNativeConstruction> {
		return switch expression {
			case ECall(EUnsupported(value), arguments) if (value == marker()):
				switch arguments {
					case [EString(target), EString(kind), EString(name), EArrayDecl(values)]
						if ((target == "java" || target == "cs") && (kind == "class" || kind == "runtime") && name.length > 0):
						{target: target == "java" ? Java : Cs, kind: kind == "class" ? EmittedClass(name) : Runtime(name), arguments: values.copy()};
					case _: throw "native constructor transport has an invalid target or payload";
				}
			case _: null;
		};
	}
}
