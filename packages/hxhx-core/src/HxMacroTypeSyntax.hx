import haxe.macro.Expr;
import HxTypeSyntax.HxTypeSyntaxArgument;
import HxTypeSyntax.HxTypeSyntaxParameter;

/** Convert parsed type structure to macro structure without hiding type arguments in path names. */
function convert(type:HxTypeSyntax, position:Position, parseMetadata:Null<Array<String>->Metadata>):ComplexType {
	return switch type.getKind() {
		case TypePath(segments, arguments):
			path(segments, [for (argument in arguments) TPType(convert(argument, position, parseMetadata))]);
		case GroupedType(inner): TParent(convert(inner, position, parseMetadata));
		case IntersectionType(members): TIntersection([for (member in members) convert(member, position, parseMetadata)]);
		case FunctionType(arguments, result):
			final converted = [for (argument in arguments) argumentType(argument, position, parseMetadata)];
			// Upstream retains grouping for a single optional or rest component.
			if (arguments.length == 1 && (arguments[0].isOptional || arguments[0].isRest))
				converted[0] = TParent(converted[0]);
			TFunction(converted, convert(result, position, parseMetadata));
		case ArrowType(argument, result):
			final first = convert(argument, position, parseMetadata);
			final last = convert(result, position, parseMetadata);
			switch last {
				case TFunction(arguments, result): TFunction([first].concat(arguments), result);
				case _: TFunction([first], last);
			}
		case AnonymousType(fields, extensions):
			final converted:Array<Field> = [
				for (field in fields) {
					final annotations = metadata(field.metadata, parseMetadata);
					if (field.isOptional) annotations.push({name: ":optional", params: [], pos: position});
					final access:Array<Access> = field.isVisibilityExplicit ? [field.visibility == Private ? APrivate : APublic] : [];
					final kind:FieldType = switch field.kind {
						case Variable(type, isFinal, get, set): {
								if (isFinal)
									access.push(AFinal);
								final value = convert(type, position, parseMetadata);
								get.length == 0
							&& set.length == 0 ? FVar(value, null) : FProp(get, set, value, null);
							}
						case Method(parameters, arguments, result):
							FFun({
								params: parameterDeclarations(parameters, position, parseMetadata),
								args: [
									for (argument in arguments)
										{
											name: argument.name == null ? "" : argument.name,
											type: restType(argument, position, parseMetadata),
											opt: argument.isOptional,
											meta: metadata(argument.metadata, parseMetadata)
										}
								],
								ret: convert(result, position, parseMetadata),
								expr: null
							});
					};
					{
						name: field.name,
						kind: kind,
						access: access,
						meta: annotations,
						pos: position
					};
				}
			];
			if (extensions.length == 0) {
				TAnonymous(converted);
			} else {
				TExtend([
					for (extension in extensions)
						switch convert(extension, position, parseMetadata) {
							case TPath(value):
								value;
							case _:
								throw "macro structural extension requires a type path";
						}
				], converted);
			}
	};
}

/** Haxe's public function syntax omits type-parameter defaults; executable typing owns their rejection. */
function parameterDeclarations(parameters:Array<HxTypeSyntaxParameter>, position:Position, parseMetadata:Null<Array<String>->Metadata>):Array<TypeParamDecl> {
	return [
		for (parameter in parameters)
			{
				name: parameter.name,
				constraints: [
					for (constraint in parameter.constraints)
						convert(constraint, position, parseMetadata)
				],
				defaultType: null,
				params: [],
				meta: metadata(parameter.metadata, parseMetadata)
			}
	];
}

private function metadata(values:Array<String>, parseMetadata:Null<Array<String>->Metadata>):Metadata {
	if (values.length == 0)
		return [];
	if (parseMetadata == null)
		throw "written type metadata requires a macro metadata adapter";
	return parseMetadata(values);
}

private function restType(argument:HxTypeSyntaxArgument, position:Position, parseMetadata:Null<Array<String>->Metadata>):ComplexType {
	final value = convert(argument.type, position, parseMetadata);
	return argument.isRest ? TPath({pack: ["haxe"], name: "Rest", params: [TPType(value)]}) : value;
}

private function argumentType(argument:HxTypeSyntaxArgument, position:Position, parseMetadata:Null<Array<String>->Metadata>):ComplexType {
	var value = restType(argument, position, parseMetadata);
	// Rest type syntax exposes the element container, not its optional source label.
	if (argument.name != null && !argument.isRest)
		value = TNamed(argument.name, value);
	return argument.isOptional ? TOptional(value) : value;
}

/** Keep a module-qualified subtype separate from its package and module name. */
private function path(segments:Array<String>, arguments:Array<TypeParam>):ComplexType {
	if (segments.length == 0)
		throw "macro type path requires a name";
	final pack = segments.copy();
	var name = pack.pop();
	var sub:Null<String> = null;
	if (pack.length > 0) {
		final candidate = pack[pack.length - 1];
		final first = candidate.charCodeAt(0);
		if (first >= "A".code && first <= "Z".code || first == "_".code) {
			name = pack.pop();
			sub = segments[segments.length - 1];
		}
	}
	return TPath({
		pack: pack,
		name: name,
		sub: sub,
		params: arguments
	});
}
