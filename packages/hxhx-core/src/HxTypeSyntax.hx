/** A parameter binder in authored type syntax, before semantic name resolution. */
typedef HxTypeSyntaxParameter = {
	final name:String;
	final constraints:Array<HxTypeSyntax>;
	final defaultType:Null<HxTypeSyntax>;
	final metadata:Array<String>;
	final pos:HxPos;
	final endPos:HxPos;
};

/** An unnamed arrow component or a named function-type argument. */
typedef HxTypeSyntaxArgument = {
	final name:Null<String>;
	final type:HxTypeSyntax;
	final isOptional:Bool;

	/** Authored ellipsis; type remains the element type, not its runtime container. */
	final isRest:Bool;

	final metadata:Array<String>;
	final pos:HxPos;
	final endPos:HxPos;
};

/** Preserve structural field and method declarations without treating them as classes. */
enum HxTypeSyntaxFieldKind {
	Variable(type:HxTypeSyntax, isFinal:Bool, propertyGet:String, propertySet:String);
	Method(parameters:Array<HxTypeSyntaxParameter>, arguments:Array<HxTypeSyntaxArgument>, result:HxTypeSyntax);
}

/** One declaration-grade anonymous field, including optionality and access rules. */
typedef HxTypeSyntaxField = {
	final name:String;
	final kind:HxTypeSyntaxFieldKind;
	final isOptional:Bool;
	final visibility:HxVisibility;
	final isVisibilityExplicit:Bool;
	final metadata:Array<String>;
	final pos:HxPos;
	final endPos:HxPos;
};

/** Syntax categories only; imports, aliases, and recursive types are resolved later. */
enum HxTypeSyntaxKind {
	TypePath(segments:Array<String>, arguments:Array<HxTypeSyntax>);
	FunctionType(arguments:Array<HxTypeSyntaxArgument>, result:HxTypeSyntax);

	/** Keep legacy arrow spelling distinct from parenthesized argument-list syntax. */
	ArrowType(argument:HxTypeSyntax, result:HxTypeSyntax);

	GroupedType(inner:HxTypeSyntax);

	/** Preserve an authored intersection as one type, including nested grouping. */
	IntersectionType(members:Array<HxTypeSyntax>);

	AnonymousType(fields:Array<HxTypeSyntaxField>, extensions:Array<HxTypeSyntax>);
}

/**
	Retain authored type structure and source ranges without resolving names.

	For example, Array<Alias> retains a path and an argument node. A later
	resolver can interpret Alias in the correct module rather than reparsing a
	type-hint string. Constructor and accessor copies protect every mutable
	array; nested nodes and source positions are immutable values.
**/
class HxTypeSyntax {
	final kind:HxTypeSyntaxKind;
	final pos:HxPos;
	final endPos:HxPos;

	public function new(kind:HxTypeSyntaxKind, pos:HxPos, endPos:HxPos) {
		this.kind = copyKind(kind);
		this.pos = pos;
		this.endPos = endPos;
	}

	public function getKind():HxTypeSyntaxKind
		return copyKind(kind);

	public function getPos():HxPos
		return pos;

	public function getEndPos():HxPos
		return endPos;

	/** Copy parameter containers while sharing their immutable nested type nodes. */
	public static function copyParameters(parameters:Array<HxTypeSyntaxParameter>):Array<HxTypeSyntaxParameter> {
		return [
			for (parameter in parameters)
				{
					name: parameter.name,
					constraints: parameter.constraints.copy(),
					defaultType: parameter.defaultType,
					metadata: parameter.metadata.copy(),
					pos: parameter.pos,
					endPos: parameter.endPos
				}
		];
	}

	static function copyArguments(arguments:Array<HxTypeSyntaxArgument>):Array<HxTypeSyntaxArgument> {
		return [
			for (argument in arguments)
				{
					name: argument.name,
					type: argument.type,
					isOptional: argument.isOptional,
					isRest: argument.isRest,
					metadata: argument.metadata.copy(),
					pos: argument.pos,
					endPos: argument.endPos
				}
		];
	}

	static function copyFieldKind(kind:HxTypeSyntaxFieldKind):HxTypeSyntaxFieldKind {
		return switch (kind) {
			case Variable(type, isFinal, get, set): Variable(type, isFinal, get, set);
			case Method(parameters, arguments, result): Method(copyParameters(parameters), copyArguments(arguments), result);
		};
	}

	static function copyKind(kind:HxTypeSyntaxKind):HxTypeSyntaxKind {
		return switch (kind) {
			case TypePath(segments, arguments): TypePath(segments.copy(), arguments.copy());
			case FunctionType(arguments, result): FunctionType(copyArguments(arguments), result);
			case ArrowType(argument, result): ArrowType(argument, result);
			case GroupedType(inner): GroupedType(inner);
			case IntersectionType(members): IntersectionType(members.copy());
			case AnonymousType(fields, extensions): AnonymousType([
					for (field in fields)
						{
							name: field.name,
							kind: copyFieldKind(field.kind),
							isOptional: field.isOptional,
							visibility: field.visibility,
							isVisibilityExplicit: field.isVisibilityExplicit,
							metadata: field.metadata.copy(),
							pos: field.pos,
							endPos: field.endPos
						}
				], extensions.copy());
		};
	}
}
