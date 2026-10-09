package backend.js;

/**
	Plain extern values use their declared package path at the point of use.
	No eager alias is emitted: a declaration used only as a type need not have a
	host constructor. Explicit native metadata is selected separately; built-in
	adapters retain their own bindings.
 */
function defaultReference(declaration:HxClassDecl, fullName:String):Null<String> {
	if (!HxClassDecl.getIsExtern(declaration) || reference(declaration) != null || JsBuiltinExternBinding.owns(fullName))
		return null;
	final parts = fullName.split(".");
	return parts[0] + [for (index in 1...parts.length) JsNameMangler.propertySuffix(parts[index])].join("");
}

/**
	Resolve an authored extern name to an existing JavaScript host value.
	Only identifier paths are emitted. Metadata is decoded by the Haxe lexer,
	so quotes and escapes cannot become arbitrary target-language source.
	Emit this path at each value use: upstream observes getters, rebinding, and
	lexical shadowing there. A type-only declaration must not read the host.
	The caller must not emit methods, fields, or class metadata onto this value.
 */
function reference(declaration:HxClassDecl):Null<String> {
	if (!HxClassDecl.getIsExtern(declaration))
		return null;
	var result:Null<String> = null;
	for (metadata in HxClassDecl.getMetadata(declaration)) {
		final lexer = new HxLexer(metadata);
		if (!lexer.next().kind.match(TOther(64)) || !lexer.next().kind.match(TColon) || !lexer.next().kind.match(TIdent("native")))
			continue;
		if (!lexer.next().kind.match(TLParen))
			throw "JavaScript extern native metadata requires a string path";
		final path = switch (lexer.next().kind) {
			case TString(value, _): value;
			case _: throw "JavaScript extern native metadata requires a string path";
		};
		if (!lexer.next().kind.match(TRParen) || !lexer.next().kind.match(TEof))
			throw "JavaScript extern native metadata requires exactly one string path";
		final parts = path.split(".");
		for (part in parts)
			if (!~/^[A-Za-z_$][A-Za-z0-9_$]*$/.match(part))
				throw "Unsupported JavaScript extern native path: " + path;
		// Reuse the target's reserved-binding vocabulary; dollar signs are legal
		// in host identifiers even though generated Haxe identifiers escape them.
		final rootName = StringTools.replace(parts[0], "$", "_");
		if (JsNameMangler.identifier(rootName) != rootName)
			throw "Unsupported JavaScript extern native root: " + parts[0];
		final expression = parts[0] + [
			for (index in 1...parts.length)
				"[" + JsNameMangler.quoteString(parts[index]) + "]"
		].join("");
		if (result != null && result != expression)
			throw "Conflicting JavaScript extern native paths";
		result = expression;
	}
	return result;
}
