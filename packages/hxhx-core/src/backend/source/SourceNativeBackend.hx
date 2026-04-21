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
		sys.io.File.saveContent(outputPath, renderProgram(target, program, main.decl, className, HxFunctionDecl.getBody(main.fn)));
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
			case EEnumValue(name):
				quoteString(name);
			case EThis:
				switch (target) {
					case Python: "self";
					case Java: "this";
					case Cs: "this";
					case Php: "$this";
					case Lua: "self";
				}
			case ESuper:
				superExpr(target);
			case EUnop(op, inner):
				unopExpr(target, op, inner);
			case EIdent(name):
				valueName(target, name);
			case EBinop(op, left, right):
				binopExpr(target, op, left, right);
			case ETernary(cond, thenExpr, elseExpr):
				conditionalExpr(target, renderExpr(target, cond), renderExpr(target, thenExpr), renderExpr(target, elseExpr));
			case EAnon(fieldNames, fieldValues):
				anonExpr(target, fieldNames, fieldValues);
			case ECast(inner, _):
				renderExpr(target, inner);
			case EUntyped(inner):
				renderExpr(target, inner);
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				stringCall(target, renderExpr(target, args[0]));
			case EField(receiver, field):
				fieldAccess(target, renderExpr(target, receiver), field);
			case EArrayAccess(receiver, index):
				arrayAccessExpr(target, receiver, index);
			case ECall(ESuper, args):
				superConstructorCallExpr(target, args);
			case ECall(callee, args):
				callExpr(target, renderExpr(target, callee), args);
			case EArrayDecl(items):
				arrayLiteral(target, items);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				arrayComprehensionExpr(target, name, iterable, guardExpr, yieldExpr);
			case ERange(start, end):
				rangeIterable(target, start, end);
			case ELambda(args, body):
				lambdaExpr(target, args, body);
			case ESwitch(scrutinee, patterns, exprs):
				switchExpr(target, scrutinee, patterns, exprs);
			case ENew(typePath, args):
				constructorExpr(target, typePath, args);
			case _:
				throw targetLabel(target) + " source backend MVP unsupported expression: " + exprKind(expr);
		};
	}

	static function exprKind(expr:HxExpr):String {
		return switch (expr) {
			case ENull: "ENull";
			case EBool(_): "EBool";
			case EString(_): "EString";
			case EInt(_): "EInt";
			case EFloat(_): "EFloat";
			case EEnumValue(_): "EEnumValue";
			case EThis: "EThis";
			case ESuper: "ESuper";
			case EIdent(_): "EIdent";
			case EField(_, _): "EField";
			case ECall(_, _): "ECall";
			case EMacroExpr(_, _): "EMacroExpr";
			case EMacroType(_): "EMacroType";
			case ELambda(_, _): "ELambda";
			case ETryCatchRaw(_): "ETryCatchRaw";
			case ESwitchRaw(_): "ESwitchRaw";
			case ESwitch(_, _, _): "ESwitch";
			case ENew(_, _): "ENew";
			case EUnop(_, _): "EUnop";
			case EBinop(op, _, _): "EBinop(" + op + ")";
			case ETernary(_, _, _): "ETernary";
			case EAnon(_, _): "EAnon";
			case EArrayComprehension(_, _, _, _): "EArrayComprehension";
			case EArrayDecl(_): "EArrayDecl";
			case EArrayAccess(_, _): "EArrayAccess";
			case ERange(_, _): "ERange";
			case ECast(_, _): "ECast";
			case EUntyped(_): "EUntyped";
			case EUnsupported(_): "EUnsupported";
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

	static function binopExpr(target:SourceNativeTarget, op:String, left:HxExpr, right:HxExpr):String {
		final a = renderExpr(target, left);
		final b = renderExpr(target, right);
		if (op == ">>>")
			return unsignedRightShiftExpr(target, a, b);
		final mapped = binopToken(target, op);
		if (mapped == null)
			throw targetLabel(target) + " source backend MVP unsupported binary operator: " + op;
		if (op == "=" || op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%=")
			return a + " " + mapped + " " + b;
		return "(" + a + " " + mapped + " " + b + ")";
	}

	static function unsignedRightShiftExpr(target:SourceNativeTarget, left:String, right:String):String {
		return switch (target) {
			case Python:
				"__hxhx_ushr(" + left + ", " + right + ")";
			case Java:
				"(" + left + " >>> " + right + ")";
			case Cs:
				"((int)((uint)(" + left + ") >> (" + right + ")))";
			case Php:
				"__hxhx_ushr(" + left + ", " + right + ")";
			case Lua:
				"__hxhx_ushr(" + left + ", " + right + ")";
		};
	}

	static function unopExpr(target:SourceNativeTarget, op:String, inner:HxExpr):String {
		final rendered = renderExpr(target, inner);
		return switch (op) {
			case "!":
				if (target == Python || target == Lua) "(not " + rendered + ")"; else "(!" + rendered + ")";
			case "post++":
				postIncrementExpr(target, inner, 1);
			case "post--":
				postIncrementExpr(target, inner, -1);
			case "-", "+", "~":
				"(" + op + rendered + ")";
			default:
				throw targetLabel(target) + " source backend MVP unsupported unary operator: " + op;
		};
	}

	static function postIncrementExpr(target:SourceNativeTarget, expr:HxExpr, delta:Int):String {
		return switch (target) {
			case Python:
				final suffix = delta < 0 ? " - " + Std.string(-delta) : " + " + Std.string(delta);
				switch (expr) {
					case EIdent(name):
						final targetName = valueName(target, name);
						"((__hxhx_post_old := "
						+ targetName
						+ "), ("
						+ targetName
						+ " := (__hxhx_post_old"
						+ suffix
						+ ")), __hxhx_post_old)[2]";
					case EField(receiver, field):
						"__hxhx_post_update_attr("
						+ renderExpr(target, receiver)
						+ ", "
						+ quoteString(sanitizeTypeName(field))
						+ ", "
						+ Std.string(delta)
						+ ")";
					case EArrayAccess(receiver, index):
						"__hxhx_post_update_index("
						+ renderExpr(target, receiver)
						+ ", "
						+ renderExpr(target, index)
						+ ", "
						+ Std.string(delta)
						+ ")";
					case _:
						throw targetLabel(target) + " source backend MVP unsupported postfix target: " + exprKind(expr);
				}
			case Java, Cs, Php, Lua:
				throw targetLabel(target) + " source backend MVP unsupported unary operator: " + (delta < 0 ? "post--" : "post++");
		};
	}

	static function binopToken(target:SourceNativeTarget, op:String):Null<String> {
		return switch (op) {
			case "+":
				concatOp(target);
			case "!=" if (target == Lua):
				"~=";
			case "&&" if (target == Python || target == Lua):
				"and";
			case "||" if (target == Python || target == Lua):
				"or";
			case "==", "!=", "<", "<=", ">", ">=", "-", "*", "/", "%", "=", "+=", "-=", "*=", "/=", "%=", "&", "|", "^", "<<", ">>", "&&", "||":
				op;
			default:
				null;
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

	static function fieldAccess(target:SourceNativeTarget, receiver:String, field:String):String {
		final safeField = sanitizeTypeName(field);
		return switch (target) {
			case Php: receiver + "->" + safeField;
			case Python: receiver + "." + safeField;
			case Java: receiver + "." + safeField;
			case Cs: receiver + "." + safeField;
			case Lua: receiver + "." + safeField;
		};
	}

	static function superExpr(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "super()";
			case Java, Cs, Php, Lua:
				throw targetLabel(target) + " source backend MVP unsupported expression: ESuper";
		};
	}

	static function superConstructorCallExpr(target:SourceNativeTarget, args:Array<HxExpr>):String {
		final rendered = [for (arg in args) renderExpr(target, arg)].join(", ");
		return switch (target) {
			case Python: "super().__init__(" + rendered + ")";
			case Java, Cs, Php, Lua:
				throw targetLabel(target) + " source backend MVP unsupported expression: ESuper";
		};
	}

	static function callExpr(target:SourceNativeTarget, callee:String, args:Array<HxExpr>):String {
		final rendered = [for (arg in args) renderExpr(target, arg)].join(", ");
		return callee + "(" + rendered + ")";
	}

	static function arrayAccessExpr(target:SourceNativeTarget, receiver:HxExpr, index:HxExpr):String {
		final renderedReceiver = renderExpr(target, receiver);
		final renderedIndex = renderExpr(target, index);
		return switch (target) {
			case Python, Java, Cs, Php, Lua:
				renderedReceiver + "[" + renderedIndex + "]";
		};
	}

	static function arrayComprehensionExpr(target:SourceNativeTarget, name:String, iterable:HxExpr, guardExpr:Null<HxExpr>, yieldExpr:HxExpr):String {
		return switch (target) {
			case Python:
				final binder = valueName(target, name);
				final renderedYield = renderExpr(target, yieldExpr);
				final renderedIterable = switch (iterable) {
					case ERange(start, end):
						rangeIterable(target, start, end);
					case _:
						renderExpr(target, iterable);
				};
				final renderedGuard = guardExpr == null ? "" : " if " + renderExpr(target, guardExpr);
				"[" + renderedYield + " for " + binder + " in " + renderedIterable + renderedGuard + "]";
			case Java, Cs, Php, Lua:
				throw targetLabel(target) + " source backend MVP unsupported expression: EArrayComprehension";
		};
	}

	static function lambdaExpr(target:SourceNativeTarget, args:Array<String>, body:HxExpr):String {
		final renderedArgs = [for (arg in args) valueName(target, arg)].join(", ");
		final renderedBody = renderExpr(target, body);
		return switch (target) {
			case Python:
				"lambda " + renderedArgs + ": " + renderedBody;
			case Java:
				"(" + renderedArgs + ") -> " + renderedBody;
			case Cs:
				"(" + renderedArgs + ") => " + renderedBody;
			case Php:
				"function(" + renderedArgs + ") { return " + renderedBody + "; }";
			case Lua:
				"function(" + renderedArgs + ") return " + renderedBody + " end";
		};
	}

	static function switchExpr(target:SourceNativeTarget, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>):String {
		final scrutineeExpr = renderExpr(target, scrutinee);
		var chain = defaultValue(target);
		if (patterns != null && exprs != null) {
			final count = patterns.length < exprs.length ? patterns.length : exprs.length;
			for (i in 0...count) {
				final idx = count - 1 - i;
				final cond = switchPatternCond(target, scrutineeExpr, patterns[idx]);
				final body = renderExpr(target, exprs[idx]);
				chain = conditionalExpr(target, cond, body, chain);
			}
		}
		return chain;
	}

	static function conditionalExpr(target:SourceNativeTarget, cond:String, thenExpr:String, elseExpr:String):String {
		return switch (target) {
			case Python:
				"(" + thenExpr + " if (" + cond + ") else " + elseExpr + ")";
			case Java:
				"(" + cond + " ? " + thenExpr + " : " + elseExpr + ")";
			case Cs:
				"(" + cond + " ? " + thenExpr + " : " + elseExpr + ")";
			case Php:
				"(" + cond + " ? " + thenExpr + " : " + elseExpr + ")";
			case Lua:
				"((" + cond + ") and " + thenExpr + " or " + elseExpr + ")";
		};
	}

	static function anonExpr(target:SourceNativeTarget, fieldNames:Array<String>, fieldValues:Array<HxExpr>):String {
		return switch (target) {
			case Python:
				final pairs = new Array<String>();
				final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
				for (i in 0...count)
					pairs.push(sanitizeTypeName(fieldNames[i]) + "=" + renderExpr(target, fieldValues[i]));
				"__hxhx_anon(" + pairs.join(", ") + ")";
			case Java, Cs, Php, Lua:
				throw targetLabel(target) + " source backend MVP unsupported expression: EAnon";
		};
	}

	static function switchPatternCond(target:SourceNativeTarget, scrutinee:String, pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PNull:
				equalityCond(target, scrutinee, defaultValue(target));
			case PWildcard:
				trueLiteral(target);
			case PBool(value):
				equalityCond(target, scrutinee, renderExpr(target, EBool(value)));
			case PString(value):
				equalityCond(target, scrutinee, quoteString(value));
			case PInt(value):
				equalityCond(target, scrutinee, Std.string(value));
			case PEnumValue(name):
				equalityCond(target, scrutinee, quoteString(name));
			case PEnumExtract(name, _args):
				equalityCond(target, scrutinee, quoteString(name));
			case PCapture(_name, inner):
				switchPatternCond(target, scrutinee, inner);
			case PBind(_name):
				trueLiteral(target);
			case POr(patterns):
				if (patterns == null || patterns.length == 0) {
					falseLiteral(target);
				} else {
					final op = target == Python || target == Lua ? " or " : " || ";
					final parts = [
						for (p in patterns)
							"(" + switchPatternCond(target, scrutinee, p) + ")"
					].join(op);
					"(" + parts + ")";
				}
			case PObject(_, _) | PArray(_) | PExtractor(_, _) | PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PIntEqualsGuard(_, _, _) |
				PUnsupportedGuard(_):
				throw targetLabel(target) + " source backend MVP unsupported switch pattern: " + patternKind(pattern);
		};
	}

	static function equalityCond(target:SourceNativeTarget, left:String, right:String):String {
		return "(" + left + " " + (target == Lua ? "==" : "==") + " " + right + ")";
	}

	static function trueLiteral(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "True";
			case Java: "true";
			case Cs: "true";
			case Php: "true";
			case Lua: "true";
		};
	}

	static function falseLiteral(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "False";
			case Java: "false";
			case Cs: "false";
			case Php: "false";
			case Lua: "false";
		};
	}

	static function patternKind(pattern:HxSwitchPattern):String {
		return switch (pattern) {
			case PNull: "PNull";
			case PWildcard: "PWildcard";
			case PBool(_): "PBool";
			case PString(_): "PString";
			case PInt(_): "PInt";
			case PEnumValue(_): "PEnumValue";
			case PEnumExtract(_, _): "PEnumExtract";
			case PObject(_, _): "PObject";
			case PCapture(_, _): "PCapture";
			case PArray(_): "PArray";
			case PExtractor(_, _): "PExtractor";
			case PLengthGuard(_, _, _): "PLengthGuard";
			case PStartsWithGuard(_, _, _): "PStartsWithGuard";
			case PIntEqualsGuard(_, _, _): "PIntEqualsGuard";
			case PUnsupportedGuard(_): "PUnsupportedGuard";
			case PBind(_): "PBind";
			case POr(_): "POr";
		};
	}

	static function arrayLiteral(target:SourceNativeTarget, items:Array<HxExpr>):String {
		final rendered = [for (item in items) renderExpr(target, item)].join(", ");
		return switch (target) {
			case Java: "new Object[] { " + rendered + " }";
			case Cs: "new object[] { " + rendered + " }";
			case Python: "[" + rendered + "]";
			case Php: "[" + rendered + "]";
			case Lua: "{" + rendered + "}";
		};
	}

	static function constructorExpr(target:SourceNativeTarget, typePath:String, args:Array<HxExpr>):String {
		final rendered = [for (arg in args) renderExpr(target, arg)].join(", ");
		final safeType = sanitizeDottedPath(typePath);
		return switch (target) {
			case Python: safeType + "(" + rendered + ")";
			case Java: "new " + safeType + "(" + rendered + ")";
			case Cs: "new " + safeType + "(" + rendered + ")";
			case Php: "new " + safeType + "(" + rendered + ")";
			case Lua: safeType + ".new(" + rendered + ")";
		};
	}

	static function sanitizeDottedPath(path:String):String {
		if (path == null || path.length == 0)
			return "Unknown";
		return [for (part in path.split(".")) sanitizeTypeName(part)].join(".");
	}

	static function rangeIterable(target:SourceNativeTarget, start:HxExpr, end:HxExpr):String {
		final a = renderExpr(target, start);
		final b = renderExpr(target, end);
		return switch (target) {
			case Python: "range(" + a + ", " + b + ")";
			case Java: "range(" + a + ", " + b + ")";
			case Cs: "range(" + a + ", " + b + ")";
			case Php: "range(" + a + ", " + b + " - 1)";
			case Lua: "hxhx_range(" + a + ", " + b + ")";
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

	static function postIncrementStmt(target:SourceNativeTarget, expr:HxExpr, delta:Int):String {
		final targetExpr = switch (expr) {
			case EIdent(name):
				valueName(target, name);
			case EField(receiver, field):
				fieldAccess(target, renderExpr(target, receiver), field);
			case _:
				throw targetLabel(target) + " source backend MVP unsupported postfix target: " + exprKind(expr);
		};
		final absDelta = Std.string(delta < 0 ? -delta : delta);
		final rhs = if (delta < 0) "(" + targetExpr + " - " + absDelta + ")" else "(" + targetExpr + " + " + absDelta + ")";
		return exprStmt(target, targetExpr + " = " + rhs);
	}

	static function exprStmt(target:SourceNativeTarget, expr:String):String {
		return switch (target) {
			case Python: expr;
			case Java: expr + ";";
			case Cs: expr + ";";
			case Php: expr + ";";
			case Lua: expr;
		};
	}

	static function renderStmt(target:SourceNativeTarget, stmt:HxStmt, indent:String):Array<String> {
		return switch (stmt) {
			case SBlock(stmts, _):
				renderStmts(target, stmts, indent);
			case SExpr(ECall(EField(EIdent("Sys"), "println"), args), _) if (args.length == 1):
				[indent + printStmt(target, renderExpr(target, args[0]))];
			case SExpr(ECall(EIdent("trace"), args), _) if (args.length >= 1):
				[indent + printStmt(target, renderExpr(target, args[0]))];
			case SExpr(EUnop("post++", inner), _):
				[indent + postIncrementStmt(target, inner, 1)];
			case SExpr(EUnop("post--", inner), _):
				[indent + postIncrementStmt(target, inner, -1)];
			case SExpr(expr, _):
				[indent + exprStmt(target, renderExpr(target, expr))];
			case SVar(name, _typeHint, init, _):
				final rhs = init == null ? defaultValue(target) : renderExpr(target, init);
					[indent + varDecl(target, sanitizeTypeName(name), rhs)];
			case SIf(cond, thenBranch, elseBranch, _):
				renderIf(target, cond, thenBranch, elseBranch, indent);
			case SForIn(name, iterable, body, _):
				renderForIn(target, name, iterable, body, indent);
			case SWhile(cond, body, _):
				renderWhile(target, cond, body, indent);
			case SSwitch(scrutinee, patterns, bodies, _):
				renderSwitchStmt(target, scrutinee, patterns, bodies, indent);
			case STry(tryBody, catches, _):
				renderTry(target, tryBody, catches, indent);
			case SBreak(_):
				[indent + breakStmt(target)];
			case SContinue(_):
				[indent + continueStmt(target)];
			case SThrow(expr, _):
				[indent + throwStmt(target, renderExpr(target, expr))];
			case SReturn(expr, _):
				[indent + returnStmt(target, renderExpr(target, expr))];
			case SReturnVoid(_):
				[indent + returnVoidStmt(target)];
			case _:
				throw targetLabel(target) + " source backend MVP unsupported statement: " + stmtKind(stmt);
		};
	}

	static function stmtKind(stmt:HxStmt):String {
		return switch (stmt) {
			case SBlock(_, _): "SBlock";
			case SVar(_, _, _, _): "SVar";
			case SIf(_, _, _, _): "SIf";
			case SForIn(_, _, _, _): "SForIn";
			case SForKeyValue(_, _, _, _, _): "SForKeyValue";
			case SWhile(_, _, _): "SWhile";
			case SDoWhile(_, _, _): "SDoWhile";
			case SSwitch(_, _, _, _): "SSwitch";
			case STry(_, _, _): "STry";
			case SBreak(_): "SBreak";
			case SContinue(_): "SContinue";
			case SThrow(_, _): "SThrow";
			case SReturnVoid(_): "SReturnVoid";
			case SReturn(_, _): "SReturn";
			case SExpr(_, _): "SExpr";
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

	static function indentStep(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "    ";
			case Java: "    ";
			case Cs: "    ";
			case Php: "  ";
			case Lua: "  ";
		};
	}

	static function renderIf(target:SourceNativeTarget, cond:HxExpr, thenBranch:HxStmt, elseBranch:Null<HxStmt>, indent:String):Array<String> {
		final renderedCond = renderExpr(target, cond);
		final childIndent = indent + indentStep(target);
		final out = new Array<String>();
		switch (target) {
			case Python:
				out.push(indent + "if " + renderedCond + ":");
				for (line in renderStmt(target, thenBranch, childIndent))
					out.push(line);
				if (elseBranch != null) {
					out.push(indent + "else:");
					for (line in renderStmt(target, elseBranch, childIndent))
						out.push(line);
				}
			case Java:
				out.push(indent + "if (" + renderedCond + ") {");
				for (line in renderStmt(target, thenBranch, childIndent))
					out.push(line);
				if (elseBranch == null) {
					out.push(indent + "}");
				} else {
					out.push(indent + "} else {");
					for (line in renderStmt(target, elseBranch, childIndent))
						out.push(line);
					out.push(indent + "}");
				}
			case Cs:
				out.push(indent + "if (" + renderedCond + ") {");
				for (line in renderStmt(target, thenBranch, childIndent))
					out.push(line);
				if (elseBranch == null) {
					out.push(indent + "}");
				} else {
					out.push(indent + "} else {");
					for (line in renderStmt(target, elseBranch, childIndent))
						out.push(line);
					out.push(indent + "}");
				}
			case Php:
				out.push(indent + "if (" + renderedCond + ") {");
				for (line in renderStmt(target, thenBranch, childIndent))
					out.push(line);
				if (elseBranch == null) {
					out.push(indent + "}");
				} else {
					out.push(indent + "} else {");
					for (line in renderStmt(target, elseBranch, childIndent))
						out.push(line);
					out.push(indent + "}");
				}
			case Lua:
				out.push(indent + "if " + renderedCond + " then");
				for (line in renderStmt(target, thenBranch, childIndent))
					out.push(line);
				if (elseBranch != null) {
					out.push(indent + "else");
					for (line in renderStmt(target, elseBranch, childIndent))
						out.push(line);
				}
				out.push(indent + "end");
		}
		return out;
	}

	static function renderForIn(target:SourceNativeTarget, name:String, iterable:HxExpr, body:HxStmt, indent:String):Array<String> {
		final cleanName = sanitizeTypeName(name);
		final value = valueName(target, cleanName);
		final source = renderExpr(target, iterable);
		final childIndent = indent + indentStep(target);
		final out = new Array<String>();
		switch (target) {
			case Python:
				out.push(indent + "for " + cleanName + " in " + source + ":");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
			case Java:
				out.push(indent + "for (var " + cleanName + " : " + source + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Cs:
				out.push(indent + "foreach (var " + cleanName + " in " + source + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Php:
				out.push(indent + "foreach (" + source + " as " + value + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Lua:
				out.push(indent + "for _, " + cleanName + " in ipairs(" + source + ") do");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "end");
		}
		return out;
	}

	static function renderWhile(target:SourceNativeTarget, cond:HxExpr, body:HxStmt, indent:String):Array<String> {
		final renderedCond = renderExpr(target, cond);
		final childIndent = indent + indentStep(target);
		final out = new Array<String>();
		switch (target) {
			case Python:
				out.push(indent + "while " + renderedCond + ":");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
			case Java:
				out.push(indent + "while (" + renderedCond + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Cs:
				out.push(indent + "while (" + renderedCond + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Php:
				out.push(indent + "while (" + renderedCond + ") {");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "}");
			case Lua:
				out.push(indent + "while " + renderedCond + " do");
				for (line in renderStmt(target, body, childIndent))
					out.push(line);
				out.push(indent + "end");
		}
		return out;
	}

	static function renderSwitchStmt(target:SourceNativeTarget, scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, bodies:Array<HxStmt>,
			indent:String):Array<String> {
		final scrutineeExpr = renderExpr(target, scrutinee);
		final childIndent = indent + indentStep(target);
		final out = new Array<String>();
		final count = patterns == null || bodies == null ? 0 : (patterns.length < bodies.length ? patterns.length : bodies.length);
		switch (target) {
			case Python:
				if (count == 0) {
					out.push(indent + emptyStmt(target));
					return out;
				}
				for (i in 0...count) {
					final keyword = i == 0 ? "if" : "elif";
					out.push(indent + keyword + " " + switchPatternCond(target, scrutineeExpr, patterns[i]) + ":");
					for (line in renderStmt(target, bodies[i], childIndent))
						out.push(line);
				}
			case Java | Cs | Php | Lua:
				throw targetLabel(target) + " source backend MVP unsupported statement: SSwitch";
		}
		return out;
	}

	static function renderTry(target:SourceNativeTarget, tryBody:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>,
			indent:String):Array<String> {
		final childIndent = indent + indentStep(target);
		final out = new Array<String>();
		switch (target) {
			case Python:
				out.push(indent + "try:");
				for (line in renderStmt(target, tryBody, childIndent))
					out.push(line);
				if (catches == null || catches.length == 0) {
					out.push(indent + "except Exception:");
					out.push(childIndent + "raise");
				} else {
					for (c in catches) {
						final catchName = sanitizeTypeName(c.name);
						out.push(indent + "except Exception as " + catchName + ":");
						for (line in renderStmt(target, c.body, childIndent))
							out.push(line);
					}
				}
			case Java:
				out.push(indent + "try {");
				for (line in renderStmt(target, tryBody, childIndent))
					out.push(line);
				out.push(indent + "}");
				if (catches == null || catches.length == 0) {
					out.push(indent + "catch (RuntimeException e) {");
					out.push(childIndent + "throw e;");
					out.push(indent + "}");
				} else {
					for (c in catches) {
						final catchName = sanitizeTypeName(c.name);
						out.push(indent + "catch (RuntimeException " + catchName + ") {");
						for (line in renderStmt(target, c.body, childIndent))
							out.push(line);
						out.push(indent + "}");
					}
				}
			case Cs:
				out.push(indent + "try {");
				for (line in renderStmt(target, tryBody, childIndent))
					out.push(line);
				out.push(indent + "}");
				if (catches == null || catches.length == 0) {
					out.push(indent + "catch (System.Exception e) {");
					out.push(childIndent + "throw;");
					out.push(indent + "}");
				} else {
					for (c in catches) {
						final catchName = sanitizeTypeName(c.name);
						out.push(indent + "catch (System.Exception " + catchName + ") {");
						for (line in renderStmt(target, c.body, childIndent))
							out.push(line);
						out.push(indent + "}");
					}
				}
			case Php:
				out.push(indent + "try {");
				for (line in renderStmt(target, tryBody, childIndent))
					out.push(line);
				out.push(indent + "}");
				if (catches == null || catches.length == 0) {
					out.push(indent + "catch (\\Exception $e) {");
					out.push(childIndent + "throw $e;");
					out.push(indent + "}");
				} else {
					for (c in catches) {
						final catchName = sanitizeTypeName(c.name);
						out.push(indent + "catch (\\Exception $" + catchName + ") {");
						for (line in renderStmt(target, c.body, childIndent))
							out.push(line);
						out.push(indent + "}");
					}
				}
			case Lua:
				throw targetLabel(target) + " source backend MVP unsupported statement: STry";
		}
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

	static function breakStmt(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "break";
			case Java: "break;";
			case Cs: "break;";
			case Php: "break;";
			case Lua: "break";
		};
	}

	static function continueStmt(target:SourceNativeTarget):String {
		return switch (target) {
			case Python: "continue";
			case Java: "continue;";
			case Cs: "continue;";
			case Php: "continue;";
			case Lua: "continue";
		};
	}

	static function throwStmt(target:SourceNativeTarget, expr:String):String {
		return switch (target) {
			case Python: "raise Exception(" + expr + ")";
			case Java: "throw new RuntimeException(String.valueOf(" + expr + "));";
			case Cs: "throw new System.Exception(System.Convert.ToString(" + expr + "));";
			case Php: "throw new \\Exception(strval(" + expr + "));";
			case Lua: "error(" + expr + ")";
		};
	}

	static function renderSupportClasses(target:SourceNativeTarget, program:GenIrProgram, decl:HxModuleDecl, mainClassName:String):Array<String> {
		return switch (target) {
			case Python:
				renderPythonSupportClasses(program, decl, mainClassName);
			case Java | Cs | Php | Lua:
				[];
		};
	}

	static function renderPythonSupportClasses(program:GenIrProgram, decl:HxModuleDecl, mainClassName:String):Array<String> {
		final out = new Array<String>();
		final seen = new Map<String, Bool>();
		final pending = new Array<HxClassDecl>();
		function appendDeclClasses(moduleDecl:HxModuleDecl):Void {
			for (cls in HxModuleDecl.getClasses(moduleDecl)) {
				final className = sanitizeTypeName(HxClassDecl.getName(cls));
				if (className == mainClassName || seen.exists(className))
					continue;
				seen.set(className, true);
				pending.push(cls);
			}
		}
		appendDeclClasses(decl);
		for (typed in program.getTypedModules())
			appendDeclClasses(typed.getParsed().getDecl());
		final pendingNames = new Map<String, Bool>();
		for (cls in pending)
			pendingNames.set(sanitizeTypeName(HxClassDecl.getName(cls)), true);
		final ordered = new Array<HxClassDecl>();
		final emittedNames = new Map<String, Bool>();
		final remaining = pending.copy();
		while (remaining.length > 0) {
			var progressed = false;
			var i = 0;
			while (i < remaining.length) {
				final cls = remaining[i];
				final baseName = pythonBaseClassName(HxClassDecl.getExtendsPath(cls));
				if (baseName == null || baseName.length == 0 || !pendingNames.exists(baseName) || emittedNames.exists(baseName)) {
					ordered.push(cls);
					emittedNames.set(sanitizeTypeName(HxClassDecl.getName(cls)), true);
					remaining.splice(i, 1);
					progressed = true;
					continue;
				}
				i++;
			}
			if (!progressed) {
				for (cls in remaining)
					ordered.push(cls);
				break;
			}
		}
		for (cls in ordered) {
			if (out.length > 0)
				out.push("");
			for (line in renderPythonHelperClass(cls))
				out.push(line);
		}
		return out;
	}

	static function renderPythonHelperClass(cls:HxClassDecl):Array<String> {
		final className = sanitizeTypeName(HxClassDecl.getName(cls));
		final baseName = pythonBaseClassName(HxClassDecl.getExtendsPath(cls));
		final classHeader = baseName == null
			|| baseName.length == 0 ? "class " + className + ":" : "class " + className + "(" + baseName + "):";
		final out = [classHeader];
		var memberCount = 0;
		final instanceFields = new Array<HxFieldDecl>();
		for (field in HxClassDecl.getFields(cls)) {
			if (!HxFieldDecl.getIsStatic(field)) {
				instanceFields.push(field);
				continue;
			}
			final init = HxFieldDecl.getInit(field);
			final rhs = init == null ? defaultValue(Python) : renderExpr(Python, init);
			out.push("    " + sanitizeTypeName(HxFieldDecl.getName(field)) + " = " + rhs);
			memberCount += 1;
		}
		var sawConstructor = false;
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "main")
				continue;
			final isStatic = HxFunctionDecl.getIsStatic(fn);
			final isCtor = HxFunctionDecl.getName(fn) == "new";
			if (isCtor)
				sawConstructor = true;
			if (isStatic && !isCtor)
				out.push("    @staticmethod");
			final args = new Array<String>();
			if (!isStatic || isCtor)
				args.push("self");
			for (arg in HxFunctionDecl.getArgs(fn))
				args.push(sanitizeTypeName(HxFunctionArg.getName(arg)));
			final methodName = isCtor ? "__init__" : sanitizeTypeName(HxFunctionDecl.getName(fn));
			out.push("    def " + methodName + "(" + args.join(", ") + "):");
			if (isCtor) {
				for (field in instanceFields) {
					final init = HxFieldDecl.getInit(field);
					final rhs = init == null ? defaultValue(Python) : renderExpr(Python, init);
					out.push("        self." + sanitizeTypeName(HxFieldDecl.getName(field)) + " = " + rhs);
				}
			}
			for (line in renderStmts(Python, HxFunctionDecl.getBody(fn), "        "))
				out.push(line);
			memberCount += 1;
		}
		if (!sawConstructor && instanceFields.length > 0) {
			out.push("    def __init__(self):");
			for (field in instanceFields) {
				final init = HxFieldDecl.getInit(field);
				final rhs = init == null ? defaultValue(Python) : renderExpr(Python, init);
				out.push("        self." + sanitizeTypeName(HxFieldDecl.getName(field)) + " = " + rhs);
			}
			memberCount += 1;
		}
		if (memberCount == 0)
			out.push("    pass");
		return out;
	}

	static function pythonBaseClassName(extendsPath:String):String {
		if (extendsPath == null || extendsPath.length == 0)
			return "";
		final parts = extendsPath.split(".");
		return sanitizeTypeName(parts[parts.length - 1]);
	}

	static function renderProgram(target:SourceNativeTarget, program:GenIrProgram, decl:HxModuleDecl, className:String, body:Array<HxStmt>):String {
		final lines = new Array<String>();
		switch (target) {
			case Python:
				lines.push("# Generated by hxhx Stage3 Python source backend MVP");
				lines.push("def __hxhx_anon(**kwargs):");
				lines.push("    obj = type(\"HxAnon\", (), {})()");
				lines.push("    obj.__dict__.update(kwargs)");
				lines.push("    return obj");
				lines.push("");
				lines.push("def __hxhx_post_update_attr(obj, field, delta):");
				lines.push("    old = getattr(obj, field)");
				lines.push("    setattr(obj, field, (old + delta))");
				lines.push("    return old");
				lines.push("");
				lines.push("def __hxhx_post_update_index(obj, index, delta):");
				lines.push("    old = obj[index]");
				lines.push("    obj[index] = (old + delta)");
				lines.push("    return old");
				lines.push("");
				lines.push("def __hxhx_ushr(value, bits):");
				lines.push("    return ((value & 0xffffffff) >> (bits & 31))");
				lines.push("");
				for (line in renderSupportClasses(target, program, decl, className))
					lines.push(line);
				if (lines[lines.length - 1] != "# Generated by hxhx Stage3 Python source backend MVP")
					lines.push("");
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
