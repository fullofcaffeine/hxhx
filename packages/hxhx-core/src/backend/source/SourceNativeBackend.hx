package backend.source;

import backend.BackendAbi;
import backend.BackendCapabilities;
import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;
import haxe.io.Path;

private enum SourceNativeTarget {
	Python;
	Java;
	Cs;
	Php;
	Lua;
}

/**
	Minimal native source-target backend rung for Stage3 source emitters.

	Why
	- Full1 source-target burn-down has moved Python/Java/PHP past frontend,
	  macro, resolver, and typer blockers into explicit backend dispatch.
	- Keeping those targets as pure placeholders prevents focused source-target
	  smokes from proving that Stage3 can emit any non-OCaml source artifact.

	What
	- Emits a deliberately small subset for Python, Java, C#, PHP, and Lua:
	  a no-package static `main` entrypoint containing simple `Sys.println(...)`
	  statements and basic literal/string-concat expressions.
	- Fails fast with target-specific diagnostics for unsupported statements or
	  expressions instead of silently emitting invalid target code.

	How
	- This class is a real backend registration, but it is not a parity claim.
	  It is the first executable seam that replaces "backend not implemented"
	  with deterministic source artifacts for focused smokes.
	- The implementation is intentionally shared across source targets so future
	  target cores can split out once each target needs richer semantics.
**/
class SourceNativeBackend {
	public static inline var PYTHON_TARGET_ID = "python-native";
	public static inline var JAVA_TARGET_ID = "java-native";
	public static inline var CS_TARGET_ID = "cs-native";
	public static inline var PHP_TARGET_ID = "php-native";
	public static inline var LUA_TARGET_ID = "lua-native";

	static function capabilitiesStatic():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	static function descriptor(targetId:String, implId:String, description:String, hostCap:String):TargetDescriptor {
		return {
			id: targetId,
			implId: implId,
			abiVersion: BackendAbi.VERSION,
			priority: 120,
			description: description,
			capabilities: capabilitiesStatic(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", hostCap]
			}
		};
	}

	public static function pythonDescriptor():TargetDescriptor {
		return descriptor(PYTHON_TARGET_ID, "builtin/python-native-source-mvp", "Native Python source backend (MVP)", "python");
	}

	public static function javaDescriptor():TargetDescriptor {
		return descriptor(JAVA_TARGET_ID, "builtin/java-native-source-mvp", "Native Java source backend (MVP)", "java");
	}

	public static function csDescriptor():TargetDescriptor {
		return descriptor(CS_TARGET_ID, "builtin/cs-native-source-mvp", "Native C# source backend (MVP)", "dotnet");
	}

	public static function phpDescriptor():TargetDescriptor {
		return descriptor(PHP_TARGET_ID, "builtin/php-native-source-mvp", "Native PHP source backend (MVP)", "php");
	}

	public static function luaDescriptor():TargetDescriptor {
		return descriptor(LUA_TARGET_ID, "builtin/lua-native-source-mvp", "Native Lua source backend (MVP)", "lua");
	}

	static function registration(d:TargetDescriptor, target:SourceNativeTarget):BackendRegistrationSpec {
		return {
			descriptor: d,
			create: function() return new TargetCoreBackend(d, function(program, context) return emitTarget(target, program, context))
		};
	}

	public static function pythonRegistration():BackendRegistrationSpec {
		return registration(pythonDescriptor(), Python);
	}

	public static function javaRegistration():BackendRegistrationSpec {
		return registration(javaDescriptor(), Java);
	}

	public static function csRegistration():BackendRegistrationSpec {
		return registration(csDescriptor(), Cs);
	}

	public static function phpRegistration():BackendRegistrationSpec {
		return registration(phpDescriptor(), Php);
	}

	public static function luaRegistration():BackendRegistrationSpec {
		return registration(luaDescriptor(), Lua);
	}

	static function targetLabel(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "Python";
			case Java: "Java";
			case Cs: "C#";
			case Php: "PHP";
			case Lua: "Lua";
		};
	}

	static function artifactKind(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "entry_python";
			case Java: "entry_java";
			case Cs: "entry_cs";
			case Php: "entry_php";
			case Lua: "entry_lua";
		};
	}

	static function defaultFileName(target:SourceNativeTarget, className:String):String {
		return switch (target) {
			case Python: className + ".py";
			case Java: className + ".java";
			case Cs: className + ".cs";
			case Php: "index.php";
			case Lua: className + ".lua";
		};
	}

	static function ensureDirectory(path:String):Void {
		if (path == null || path.length == 0 || sys.FileSystem.exists(path))
			return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			ensureDirectory(parent);
		sys.FileSystem.createDirectory(path);
	}

	static function ensureParentDirectory(filePath:String):Void {
		final parent = Path.directory(filePath);
		if (parent != null && parent.length > 0)
			ensureDirectory(parent);
	}

	static function mainModule(program:GenIrProgram, context:BackendContext):{decl:HxModuleDecl, cls:HxClassDecl, fn:HxFunctionDecl} {
		final wanted = context.mainModule == null ? "" : context.mainModule;
		var fallback:Null<{decl:HxModuleDecl, cls:HxClassDecl, fn:HxFunctionDecl}> = null;
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			final pkg = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final clsName = HxClassDecl.getName(cls);
				final fullName = pkg == null || pkg.length == 0 ? clsName : pkg + "." + clsName;
				for (fn in HxClassDecl.getFunctions(cls)) {
					if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main") {
						final found = {decl: decl, cls: cls, fn: fn};
						if (fallback == null)
							fallback = found;
						if (wanted.length == 0 || wanted == clsName || wanted == fullName)
							return found;
					}
				}
			}
		}
		if (fallback != null)
			return fallback;
		throw "source target MVP requires a static main entrypoint";
	}

	static function emitTarget(target:SourceNativeTarget, program:GenIrProgram, context:BackendContext):EmitResult {
		final main = mainModule(program, context);
		final className = sanitizeTypeName(HxClassDecl.getName(main.cls));
		final outputPath = context.outputFileHint != null
			&& context.outputFileHint.length > 0 ? context.outputFileHint : Path.join([context.outputDir, defaultFileName(target, className)]);
		ensureParentDirectory(outputPath);
		sys.io.File.saveContent(outputPath, renderProgram(target, className, HxFunctionDecl.getBody(main.fn)));
		return new EmitResult(outputPath, [new EmitArtifact(artifactKind(target), outputPath)], false);
	}

	static function sanitizeTypeName(name:String):String {
		final s = name == null || name.length == 0 ? "Main" : name;
		final out = new StringBuf();
		for (i in 0...s.length) {
			final ch = s.charAt(i);
			final ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "_";
			out.add(ok ? ch : "_");
		}
		return out.toString();
	}

	static function quoteString(value:String):String {
		var s = value == null ? "" : value;
		s = StringTools.replace(s, "\\", "\\\\");
		s = StringTools.replace(s, "\"", "\\\"");
		s = StringTools.replace(s, "\n", "\\n");
		s = StringTools.replace(s, "\r", "\\r");
		s = StringTools.replace(s, "\t", "\\t");
		return "\"" + s + "\"";
	}

	static function renderExpr(target:SourceNativeTarget, expr:HxExpr):String {
		return switch (expr) {
			case ENull:
				switch (target) {
					case Python: "None";
					case Java: "null";
					case Cs: "null";
					case Php: "null";
					case Lua: "nil";
				}
			case EBool(value):
				switch (target) {
					case Python: value ? "True" : "False";
					case Java: value ? "true" : "false";
					case Cs: value ? "true" : "false";
					case Php: value ? "true" : "false";
					case Lua: value ? "true" : "false";
				}
			case EString(value):
				quoteString(value);
			case EInt(value):
				Std.string(value);
			case EFloat(value):
				Std.string(value);
			case EIdent(name):
				valueName(target, name);
			case EBinop("+", left, right):
				renderExpr(target, left) + " " + concatOp(target) + " " + renderExpr(target, right);
			case ECast(inner, _):
				renderExpr(target, inner);
			case EUntyped(inner):
				renderExpr(target, inner);
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				stringCall(target, renderExpr(target, args[0]));
			case _:
				throw targetLabel(target) + " source backend MVP unsupported expression: " + Std.string(expr);
		};
	}

	static function concatOp(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "+";
			case Java: "+";
			case Cs: "+";
			case Php: ".";
			case Lua: "..";
		};
	}

	static function valueName(target:SourceNativeTarget, name:String):String {
		final clean = sanitizeTypeName(name);
		return switch (target) {
			case Php: "$" + clean;
			case Python: clean;
			case Java: clean;
			case Cs: clean;
			case Lua: clean;
		};
	}

	static function stringCall(target:SourceNativeTarget, expr:String):String {
		return switch (target) {
			case Python: "str(" + expr + ")";
			case Java: "String.valueOf(" + expr + ")";
			case Cs: "System.Convert.ToString(" + expr + ")";
			case Php: "strval(" + expr + ")";
			case Lua: "tostring(" + expr + ")";
		};
	}

	static function printStmt(target:SourceNativeTarget, expr:String):String {
		return switch (target) {
			case Python: "print(" + expr + ")";
			case Java: "System.out.println(" + expr + ");";
			case Cs: "System.Console.WriteLine(" + expr + ");";
			case Php: "echo " + expr + " . PHP_EOL;";
			case Lua: "print(" + expr + ")";
		};
	}

	static function renderStmt(target:SourceNativeTarget, stmt:HxStmt, indent:String):Array<String> {
		return switch (stmt) {
			case SBlock(stmts, _):
				renderStmts(target, stmts, indent);
			case SExpr(ECall(EField(EIdent("Sys"), "println"), args), _) if (args.length == 1):
				[indent + printStmt(target, renderExpr(target, args[0]))];
			case SVar(name, _typeHint, init, _):
				final rhs = init == null ? defaultValue(target) : renderExpr(target, init);
					[indent + varDecl(target, sanitizeTypeName(name), rhs)];
			case SReturn(expr, _):
				[indent + returnStmt(target, renderExpr(target, expr))];
			case SReturnVoid(_):
				[indent + returnVoidStmt(target)];
			case _:
				throw targetLabel(target) + " source backend MVP unsupported statement: " + Std.string(stmt);
		};
	}

	static function renderStmts(target:SourceNativeTarget, stmts:Array<HxStmt>, indent:String):Array<String> {
		final out = new Array<String>();
		for (stmt in stmts)
			for (line in renderStmt(target, stmt, indent))
				out.push(line);
		if (out.length == 0)
			out.push(indent + emptyStmt(target));
		return out;
	}

	static function defaultValue(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "None";
			case Java: "null";
			case Cs: "null";
			case Php: "null";
			case Lua: "nil";
		};
	}

	static function emptyStmt(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "pass";
			case Java: "";
			case Cs: "";
			case Php: "";
			case Lua: "-- no-op";
		};
	}

	static function varDecl(target:SourceNativeTarget, name:String, rhs:String):String {
		return switch (target) {
			case Python: name + " = " + rhs;
			case Lua: "local " + name + " = " + rhs;
			case Java: "var " + name + " = " + rhs + ";";
			case Cs: "var " + name + " = " + rhs + ";";
			case Php: "$" + name + " = " + rhs + ";";
		};
	}

	static function returnStmt(target:SourceNativeTarget, expr:String):String {
		return switch (target) {
			case Python: "return " + expr;
			case Java: "return " + expr + ";";
			case Cs: "return " + expr + ";";
			case Php: "return " + expr + ";";
			case Lua: "return " + expr;
		};
	}

	static function returnVoidStmt(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "return";
			case Java: "return;";
			case Cs: "return;";
			case Php: "return;";
			case Lua: "return";
		};
	}

	static function renderProgram(target:SourceNativeTarget, className:String, body:Array<HxStmt>):String {
		final lines = new Array<String>();
		switch (target) {
			case Python:
				lines.push("# Generated by hxhx Stage3 Python source backend MVP");
				lines.push("def main():");
				for (line in renderStmts(target, body, "    "))
					lines.push(line);
				lines.push("");
				lines.push("if __name__ == \"__main__\":");
				lines.push("    main()");
			case Java:
				lines.push("// Generated by hxhx Stage3 Java source backend MVP");
				lines.push("public class " + className + " {");
				lines.push("  public static void main(String[] args) {");
				for (line in renderStmts(target, body, "    "))
					lines.push(line);
				lines.push("  }");
				lines.push("}");
			case Cs:
				lines.push("// Generated by hxhx Stage3 C# source backend MVP");
				lines.push("public class " + className + " {");
				lines.push("  public static void Main(string[] args) {");
				for (line in renderStmts(target, body, "    "))
					lines.push(line);
				lines.push("  }");
				lines.push("}");
			case Php:
				lines.push("<?php");
				lines.push("// Generated by hxhx Stage3 PHP source backend MVP");
				lines.push("function " + className + "_main() {");
				for (line in renderStmts(target, body, "  "))
					lines.push(line);
				lines.push("}");
				lines.push(className + "_main();");
			case Lua:
				lines.push("-- Generated by hxhx Stage3 Lua source backend MVP");
				lines.push("local function main()");
				for (line in renderStmts(target, body, "  "))
					lines.push(line);
				lines.push("end");
				lines.push("main()");
		}
		return lines.join("\n") + "\n";
	}
}
