import HxTypeSyntax.HxTypeSyntaxArgument;
import HxTypeSyntax.HxTypeSyntaxParameter;

/** Include every typedef syntax fact in parsed-module cache integrity checks. */
function appendDeclaration(out:StringBuf, declaration:HxTypedefDecl):Void {
	text(out, declaration.getName());
	text(out, declaration.getVisibility() == Public ? "public" : "private");
	text(out, declaration.getIsExtern() ? "extern" : "ordinary");
	strings(out, declaration.getMetadata());
	appendParameters(out, declaration.getParameters());
	appendType(out, declaration.getTarget());
	position(out, declaration.getPos());
	position(out, declaration.getEndPos());
}

/** Shared declaration grammar has one integrity encoding for typedef and local-function binders. */
function appendParameters(out:StringBuf, values:Array<HxTypeSyntaxParameter>):Void {
	text(out, Std.string(values.length));
	for (value in values) {
		text(out, value.name);
		strings(out, value.metadata);
		text(out, Std.string(value.constraints.length));
		for (constraint in value.constraints)
			appendType(out, constraint);
		text(out, value.defaultType == null ? "no-default" : "default");
		if (value.defaultType != null)
			appendType(out, value.defaultType);
		position(out, value.pos);
		position(out, value.endPos);
	}
}

private function arguments(out:StringBuf, values:Array<HxTypeSyntaxArgument>):Void {
	text(out, Std.string(values.length));
	for (value in values) {
		text(out, value.name);
		text(out, value.isOptional ? "optional" : "required");
		text(out, value.isRest ? "rest" : "fixed");
		strings(out, value.metadata);
		appendType(out, value.type);
		position(out, value.pos);
		position(out, value.endPos);
	}
}

private function appendType(out:StringBuf, type:HxTypeSyntax):Void {
	position(out, type.getPos());
	position(out, type.getEndPos());
	switch (type.getKind()) {
		case TypePath(segments, args):
			text(out, "path");
			strings(out, segments);
			text(out, Std.string(args.length));
			for (arg in args)
				appendType(out, arg);
		case FunctionType(args, result):
			text(out, "function");
			arguments(out, args);
			appendType(out, result);
		case ArrowType(argument, result):
			text(out, "arrow");
			appendType(out, argument);
			appendType(out, result);
		case GroupedType(inner):
			text(out, "group");
			appendType(out, inner);
		case IntersectionType(members):
			text(out, "intersection");
			text(out, Std.string(members.length));
			for (member in members)
				appendType(out, member);
		case AnonymousType(fields, extensions):
			text(out, "anonymous");
			text(out, Std.string(extensions.length));
			for (extension in extensions)
				appendType(out, extension);
			text(out, Std.string(fields.length));
			for (field in fields) {
				text(out, field.name);
				text(out, field.isOptional ? "optional" : "required");
				text(out, field.visibility == Public ? "public" : "private");
				text(out, field.isVisibilityExplicit ? "written-visibility" : "default-visibility");
				strings(out, field.metadata);
				position(out, field.pos);
				position(out, field.endPos);
				switch (field.kind) {
					case Variable(type, isFinal, get, set):
						text(out, "variable");
						text(out, isFinal ? "final" : "mutable");
						text(out, get);
						text(out, set);
						appendType(out, type);
					case Method(params, args, result):
						text(out, "method");
						appendParameters(out, params);
						arguments(out, args);
						appendType(out, result);
				}
			}
	}
}

private function position(out:StringBuf, pos:HxPos):Void {
	text(out, '${pos.getIndex()}:${pos.getLine()}:${pos.getColumn()}');
}

private function strings(out:StringBuf, values:Array<String>):Void {
	text(out, Std.string(values.length));
	for (value in values)
		text(out, value);
}

private function text(out:StringBuf, value:Null<String>):Void {
	if (value == null) {
		out.add("-1:");
		return;
	}
	out.add(value.length);
	out.add(":");
	out.add(value);
}
