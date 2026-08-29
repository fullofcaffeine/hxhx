package reflaxe.ocaml.macros;

#if macro
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;

/**
	Reads the original Haxe declaration behind a typed local variable.

	Haxe can insert `Dynamic` locals while inlining a function whose parameter is
	`Dynamic`. Those compiler-owned locals keep the caller's source position, so
	their typed shape alone cannot prove that the caller wrote a `Dynamic`
	annotation. This boundary parses only the declaration's exact source range and
	reports an explicit annotation when that range declares the same local as
	`Dynamic`.
**/
function hasExplicitDynamicLocal(name:String, pos:Position):Bool {
	final source = sourceRange(pos);
	if (source == null)
		return false;
	final trimmed = StringTools.trim(source);
	if (trimmed.length == 0)
		return false;
	final declaration = StringTools.endsWith(trimmed, ";") ? trimmed : trimmed + ";";
	final parsed = try {
		Context.parse("{" + declaration + "}", pos);
	} catch (_:haxe.Exception) {
		return false;
	}
	return expressionDeclaresDynamicLocal(parsed, name);
}

/** Returns the exact UTF-8 source bytes covered by one compiler position. **/
function sourceRange(pos:Position):Null<String> {
	final info = Context.getPosInfos(pos);
	var path = info.file;
	if (path == null || path.length == 0)
		return null;
	if (!Path.isAbsolute(path))
		path = Path.join([Sys.getCwd(), path]);
	path = Path.normalize(path);
	if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
		return null;
	final bytes:Bytes = File.getBytes(path);
	if (info.min < 0 || info.max < info.min || info.max > bytes.length)
		return null;
	return bytes.sub(info.min, info.max - info.min).toString();
}

/** Finds the named declaration without inspecting unrelated initializer code. **/
function expressionDeclaresDynamicLocal(expr:Expr, name:String):Bool {
	return switch (expr.expr) {
		case EBlock(expressions):
			var found = false;
			for (value in expressions) {
				if (expressionDeclaresDynamicLocal(value, name)) {
					found = true;
					break;
				}
			}
			found;
		case EVars(variables):
			var found = false;
			for (variable in variables) {
				if (variable.name == name && variable.type != null && isDynamicComplexType(variable.type)) {
					found = true;
					break;
				}
			}
			found;
		case EParenthesis(inner) | EMeta(_, inner):
			expressionDeclaresDynamicLocal(inner, name);
		case _:
			false;
	}
}

/** Matches the built-in `Dynamic` type hint, including harmless parentheses. **/
function isDynamicComplexType(type:ComplexType):Bool {
	return switch (type) {
		case TPath(path): path.pack.length == 0 && path.name == "Dynamic" && path.sub == null && (path.params == null || path.params.length == 0);
		case TParent(inner) | TNamed(_, inner):
			isDynamicComplexType(inner);
		case _:
			false;
	}
}
#end
