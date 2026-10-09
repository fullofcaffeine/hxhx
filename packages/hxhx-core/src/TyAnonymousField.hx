/** Access and method-binding facts that an object-literal field cannot express. */
enum TyAnonymousFieldKind {
	Variable(isFinal:Bool, propertyGet:String, propertySet:String);
	Method(parameters:Array<TyTypeParameterId>);
}

/** A resolved structural member; absence, value nullability, and access remain distinct. */
typedef TyAnonymousField = {
	final name:String;
	final type:TyType;
	final kind:TyAnonymousFieldKind;
	final isOptional:Bool;
	final visibility:HxVisibility;
	final metadata:Array<String>;
	final position:HxPos;
};

/** Copy every mutable container while sharing immutable types and parameter identities. */
function copy(field:TyAnonymousField):TyAnonymousField {
	return withType(field, field.type);
}

/** Replace the member type without changing its declaration contract. */
function withType(field:TyAnonymousField, type:TyType):TyAnonymousField {
	return {
		name: field.name,
		type: type,
		kind: switch (field.kind) {
			case Variable(finalField, get, set): Variable(finalField, get, set);
			case Method(parameters): Method(parameters.copy());
		},
		isOptional: field.isOptional,
		visibility: field.visibility,
		metadata: field.metadata.copy(),
		position: field.position
	};
}

/** Object-literal fields have ordinary public read/write access and no generic method binders. */
function inferred(name:String, type:TyType):TyAnonymousField {
	return {
		name: name,
		type: type,
		kind: Variable(false, "", ""),
		isOptional: false,
		visibility: Public,
		metadata: [],
		position: HxPos.unknown()
	};
}

/**
	Compare declaration behavior without depending on positions or method parameter spelling.
	Method-local parameters use scope depth and ordinal for this comparison;
	the stored types retain their exact declaration identities for substitution.
 */
function semanticKey(field:TyAnonymousField, ?enclosingScopes:Array<Array<TyTypeParameterId>>, ?aliases:Array<TyAliasDefinition>):String {
	var scopes = enclosingScopes == null ? [] : enclosingScopes;
	final kind = switch (field.kind) {
		case Variable(finalField, get, set):
			(finalField ? "final:" : "") + (get.length == 0 && set.length == 0 ? "" : "property(" + get + "," + set + "):");
		case Method(parameters):
			scopes = scopes.concat([parameters]);
			"method<" + parameters.length + ">:";
	};
	return (field.visibility == Private ? "private:" : "") + (field.isOptional ? "?" : "") + field.name + ":" + kind
		+ field.type.semanticKeyInScopes(scopes, aliases);
}

/** Render the retained member contract for diagnostics and typed source projections. */
function display(field:TyAnonymousField):String {
	final visibility = field.visibility == Private ? "private " : "";
	final prefix = field.isOptional ? "?" : "";
	return switch (field.kind) {
		case Variable(finalField, get, set):
			visibility
			+ (finalField ? "final " : "var ")
			+ prefix
			+ field.name
			+ (get.length == 0 && set.length == 0 ? "" : "(" + get + "," + set + ")")
			+ ":"
			+ field.type.getCanonicalDisplay()
			+ ";";
		case Method(parameters):
			final binders = parameters.length == 0 ? "" : "<" + [for (parameter in parameters) parameter.getName()].join(",") + ">";
			final arguments = [
				for (argument in field.type.getFunctionParameters())
					(argument.isOptional ? "?" : "") + (argument.name == null ? "" : argument.name + ":") + argument.type.getCanonicalDisplay()
			];
			visibility
			+ "function "
			+ prefix
			+ field.name
			+ binders
			+ "("
			+ arguments.join(",")
			+ "):"
			+ field.type.getFunctionReturn().getCanonicalDisplay()
			+ ";";
	};
}
