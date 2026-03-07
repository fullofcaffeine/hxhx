package hxhxmacrohost.api;

import haxe.macro.Expr;
import hxhxmacrohost.api.Compiler as HostCompiler;
import StringTools;

typedef RuntimeMacroRenderedTypeDefinition = {
	final modulePath:String;
	final source:String;
}

typedef RuntimeMacroRenderedModuleDefinition = {
	final modulePath:String;
	final source:String;
}

/**
	Narrow `TypeDefinition` printer for runtime external-host bring-up.

	Why
	- `Context.defineType(...)` and a narrow `defineModule(...)` rung are useful for Reflaxe-style
	  helper layers, but upstream `haxe.macro.Printer` still does not OCaml-compile cleanly in the
	  macro-host build path.
	- The bring-up rung therefore needs a repo-owned printer for the subset we can support honestly
	  today.

	What
	- Supports a narrow source-emission-backed subset:
	  - `TDClass(...)`
	  - no type params
	  - no metadata/doc emission
	  - optional `extends` / `implements` with simple type paths
	  - fields only through a minimal printer equivalent to the current build-field subset
	  - optional simple `import` / `using` headers for `defineModule(...)`

	Gotchas
	- Unsupported shapes return `null`; callers should fail fast instead of pretending parity.
**/
class RuntimeMacroTypeDefinitions {
	static function validateModulePath(modulePath:String):Null<Array<String>> {
		if (modulePath == null)
			return null;
		final trimmed = StringTools.trim(modulePath);
		if (trimmed.length == 0)
			return null;
		final segments = trimmed.split(".");
		if (segments.length == 0)
			return null;
		for (segment in segments)
			if (!isValidIdent(segment))
				return null;
		return segments;
	}

	static function escapeHaxeString(s:String):String {
		if (s == null)
			return "";
		return s.split("\\")
			.join("\\\\")
			.split("\"")
			.join("\\\"")
			.split("\n")
			.join("\\n")
			.split("\r")
			.join("\\r")
			.split("\t")
			.join("\\t");
	}

	static function trimNonEmptySegments(values:Array<String>):Array<String> {
		final out = new Array<String>();
		if (values == null)
			return out;
		for (value in values) {
			if (value == null)
				continue;
			final trimmed = StringTools.trim(value);
			if (trimmed.length > 0)
				out.push(trimmed);
		}
		return out;
	}

	static function isValidIdent(name:String):Bool {
		if (name == null)
			return false;
		final trimmed = StringTools.trim(name);
		if (trimmed.length == 0)
			return false;
		inline function isAlpha(c:Int):Bool
			return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool
			return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool
			return c == "_".code;
		final first = trimmed.charCodeAt(0);
		if (!(isAlpha(first) || isUnderscore(first)))
			return false;
		for (i in 1...trimmed.length) {
			final c = trimmed.charCodeAt(i);
			if (!(isAlpha(c) || isDigit(c) || isUnderscore(c)))
				return false;
		}
		return true;
	}

	static function printTypePath(tp:TypePath):Null<String> {
		if (tp == null || !isValidIdent(tp.name))
			return null;
		if (tp.params != null && tp.params.length > 0)
			return null;
		final pack = trimNonEmptySegments(tp.pack);
		final parts = pack.concat([tp.name]);
		if (tp.sub != null) {
			final sub = StringTools.trim(tp.sub);
			if (!isValidIdent(sub))
				return null;
			parts.push(sub);
		}
		return parts.join(".");
	}

	static function printImportExpr(expr:ImportExpr):Null<String> {
		if (expr == null || expr.path == null || expr.path.length == 0)
			return null;
		final parts = new Array<String>();
		for (segment in expr.path) {
			if (segment == null || !isValidIdent(segment.name))
				return null;
			parts.push(segment.name);
		}
		if (parts.length == 0)
			return null;
		return switch (expr.mode) {
			case INormal:
				"import " + parts.join(".") + ";";
			case IAll:
				"import " + parts.join(".") + ".*;";
			case IAsName(alias):
				if (!isValidIdent(alias))
					return null;
				"import " + parts.join(".") + " as " + alias + ";";
		};
	}

	static function printUsingPath(tp:TypePath):Null<String> {
		final path = printTypePath(tp);
		return path == null ? null : "using " + path + ";";
	}

	static function renderMetadataLines(typePath:String):Array<String> {
		final out = new Array<String>();
		for (entry in HostCompiler.listAppliedTypeMetadata(typePath)) {
			final trimmed = entry == null ? "" : StringTools.trim(entry);
			if (trimmed.length > 0)
				out.push(trimmed);
		}
		return out;
	}

	static function tryConstToHaxe(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EConst(CString(s, _)):
				"\"" + escapeHaxeString(s) + "\"";
			case EConst(CInt(s)):
				s;
			case EConst(CFloat(s)):
				s;
			case EConst(CIdent("true")):
				"true";
			case EConst(CIdent("false")):
				"false";
			case EConst(CIdent("null")):
				"null";
			case _:
				null;
		};
	}

	static function renderSingleTypeSource(typePath:String, t:TypeDefinition):Null<String> {
		final body = renderTypeBody(t);
		if (body == null)
			return null;
		final metadata = renderMetadataLines(typePath);
		return metadata.length == 0 ? body : metadata.join("\n") + "\n" + body;
	}

	static function tryExtractTraceString(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractTraceString(stmts[0]);
			case ECall(target, params):
				switch (target.expr) {
					case EConst(CIdent("trace")):
						if (params != null && params.length == 1) {
							switch (params[0].expr) {
								case EConst(CString(s, _)):
									s;
								case _:
									null;
							}
						} else null;
					case _:
						null;
				}
			case _:
				null;
		};
	}

	static function tryExtractReturnString(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractReturnString(stmts[0]);
			case EReturn(v):
				if (v == null) null else switch (v.expr) {
					case EConst(CString(s, _)):
						s;
					case _:
						null;
				}
			case _:
				null;
		};
	}

	static function tryExtractReturnInt(e:Null<Expr>):Null<Int> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractReturnInt(stmts[0]);
			case EReturn(v):
				if (v == null) null else switch (v.expr) {
					case EConst(CInt(s)):
						Std.parseInt(s);
					case _:
						null;
				}
			case _:
				null;
		};
	}

	static function printFieldMinimal(f:Field):Null<String> {
		if (f == null || !isValidIdent(f.name))
			return null;

		final isStatic = f.access != null && f.access.indexOf(AStatic) != -1;
		final isPublic = f.access != null && f.access.indexOf(APublic) != -1;
		final vis = isPublic ? "public" : "private";
		final stat = isStatic ? " static" : "";

		return switch (f.kind) {
			case FFun(fn):
				if (fn == null)
					return null;
				final argNames = new Array<String>();
				if (fn.args != null) {
					for (a in fn.args) {
						if (a == null || !isValidIdent(a.name) || a.opt == true || a.type != null || a.value != null)
							return null;
						argNames.push(a.name);
					}
				}
				final msg = tryExtractTraceString(fn.expr);
				if (msg != null)
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") { trace(\"" + escapeHaxeString(msg) + "\"); }";
				final retStr = tryExtractReturnString(fn.expr);
				if (retStr != null)
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") { return \"" + escapeHaxeString(retStr) + "\"; }";
				final retInt = tryExtractReturnInt(fn.expr);
				if (retInt != null)
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") { return " + Std.string(retInt) + "; }";
				null;
			case FVar(_t, e):
				final init = tryConstToHaxe(e);
				if (init != null) vis + stat + " var " + f.name + " = " + init + ";"; else vis + stat + " var " + f.name + ":Dynamic;";
			case _:
				null;
		};
	}

	static function renderTypeBody(t:TypeDefinition):Null<String> {
		if (t == null || !isValidIdent(t.name))
			return null;
		if (t.params != null && t.params.length > 0)
			return null;
		return switch (t.kind) {
			case TDClass(superClass, interfaces, isInterface, isFinal, isAbstract):
				final head = new Array<String>();
				if (t.isExtern)
					head.push("extern");
				if (isFinal)
					head.push("final");
				if (isAbstract)
					head.push("abstract");
				head.push(isInterface ? "interface" : "class");
				head.push(t.name);
				if (superClass != null) {
					final superText = printTypePath(superClass);
					if (superText == null)
						return null;
					head.push("extends " + superText);
				}
				if (interfaces != null) {
					for (iface in interfaces) {
						final ifaceText = printTypePath(iface);
						if (ifaceText == null)
							return null;
						head.push((isInterface ? "extends " : "implements ") + ifaceText);
					}
				}
				final fieldLines = new Array<String>();
				if (t.fields != null) {
					for (field in t.fields) {
						final printed = printFieldMinimal(field);
						if (printed == null)
							return null;
						fieldLines.push("  " + printed);
					}
				}
				if (fieldLines.length == 0) head.join(" ") + " {\n}"; else head.join(" ") + " {\n" + fieldLines.join("\n") + "\n}";
			case _:
				return null;
		};
	}

	public static function renderTypeDefinition(t:TypeDefinition):Null<RuntimeMacroRenderedTypeDefinition> {
		if (t == null || !isValidIdent(t.name))
			return null;
		final pack = trimNonEmptySegments(t.pack);
		for (segment in pack)
			if (!isValidIdent(segment))
				return null;
		final modulePath = (pack.length == 0 ? "" : pack.join(".") + ".") + t.name;
		final header = new Array<String>();
		if (pack.length > 0)
			header.push("package " + pack.join(".") + ";");
		final body = renderSingleTypeSource(modulePath, t);
		if (body == null)
			return null;
		header.push(body);
		return {modulePath: modulePath, source: header.join("\n\n")};
	}

	public static function emitTypeDefinitionResult(t:TypeDefinition):Bool {
		final rendered = renderTypeDefinition(t);
		if (rendered == null)
			return false;
		HostCompiler.emitHxModule(rendered.modulePath, rendered.source);
		return true;
	}

	public static function renderModuleDefinition(modulePath:String, types:Array<TypeDefinition>, ?imports:Array<ImportExpr>,
			?usings:Array<TypePath>):Null<RuntimeMacroRenderedModuleDefinition> {
		final segments = validateModulePath(modulePath);
		if (segments == null || types == null || types.length == 0)
			return null;
		final moduleName = segments[segments.length - 1];
		final pack = segments.slice(0, segments.length - 1);
		var hasPrimary = false;
		final typeBodies = new Array<String>();
		for (typeDef in types) {
			if (typeDef == null)
				return null;
			final typePack = trimNonEmptySegments(typeDef.pack);
			if (typePack.join(".") != pack.join("."))
				return null;
			if (typeDef.name == moduleName)
				hasPrimary = true;
			final typePath = typeDef.name == moduleName ? modulePath : modulePath + "." + typeDef.name;
			final body = renderSingleTypeSource(typePath, typeDef);
			if (body == null)
				return null;
			typeBodies.push(body);
		}
		if (!hasPrimary)
			return null;

		final header = new Array<String>();
		if (pack.length > 0)
			header.push("package " + pack.join(".") + ";");
		if (imports != null) {
			for (expr in imports) {
				final line = printImportExpr(expr);
				if (line == null)
					return null;
				header.push(line);
			}
		}
		if (usings != null) {
			for (tp in usings) {
				final line = printUsingPath(tp);
				if (line == null)
					return null;
				header.push(line);
			}
		}
		header.push(typeBodies.join("\n\n"));
		return {modulePath: segments.join("."), source: header.join("\n\n")};
	}
}
