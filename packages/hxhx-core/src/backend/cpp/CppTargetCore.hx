package backend.cpp;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrProgram;
import haxe.io.Path;

typedef CppAnonStruct = {
	var name:String;
	var fieldNames:Array<String>;
	var fieldTypes:Array<String>;
}

typedef CppTryStringProbe = {
	var expr:String;
	var fallback:String;
}

typedef CppFieldReadCatchString = {
	var receiver:String;
	var field:String;
	var fallback:String;
}

typedef CppConstructorFieldInitializer = {
	var field:String;
	var arg:String;
}

typedef CppFunctionScopePrep = {
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var localTypeOverrides:haxe.ds.StringMap<String>;
	var argLocalTypes:haxe.ds.StringMap<String>;
	var argLocalTypeHints:haxe.ds.StringMap<String>;
	var argLocalNames:haxe.ds.StringMap<String>;
	var argLocalNameCounts:haxe.ds.StringMap<Int>;
}

/**
	Coarse render policy bucket for reachable Cpp helper classes.

	FullBody keeps rendering parsed helper fields/method bodies. DeclarationOnly
	emits no body or only an interface/signature surface. RuntimeModule means the
	target owns a compact support/template body instead of rendering the parsed
	helper implementation. UnsupportedDiagnostic is reserved for future explicit
	"do not fake this as parity" helpers.
**/
enum CppHelperRenderKind {
	FullBody;
	DeclarationOnly;
	RuntimeModule;
	UnsupportedDiagnostic;
}

typedef CppHelperRenderKindCounts = {
	var fullBody:Int;
	var declarationOnly:Int;
	var runtimeModule:Int;
	var unsupportedDiagnostic:Int;
}

/**
	Small native C++ source-emission target core.

	Why
	- Full1 Cpp evidence now reaches Stage3 target dispatch after hxcpp's Neko
	  helper-tool path succeeds. The next useful seam is not another placeholder;
	  it is a concrete target core that can emit and optionally build the smallest
	  C++ artifact.
	- This must not pretend to be hxcpp parity. Unsupported Haxe semantics should
	  fail with C++-specific diagnostics until they are implemented deliberately.

	What
	- Emits one `src/<Main>.cpp` for a static `main`.
	- Supports a tiny smoke subset: blocks, local vars, `Sys.println(...)`,
	  literals, identifiers, `Std.string(...)`, and `+` concatenation/arithmetic.
	- If build is requested and `-D no-compilation` is absent, invokes a local C++
	  compiler (`c++`, `g++`, or `clang++`) to produce an executable.

	How
	- Keep this target independent from `SourceTargetCommon`; C++/hxcpp will need
	  different runtime and packaging rules from Python/C#/Lua/PHP.
	- Grow support one focused CI blocker at a time, with repo-local coverage
	  before rerunning the upstream-derived Cpp gate.
**/
class CppTargetCore {
	static final inferredSignatureStack = new haxe.ds.StringMap<Bool>();
	static final erasedDynamicReturnStack = new haxe.ds.StringMap<Bool>();
	static var erasedDynamicReturnCache = new haxe.ds.StringMap<Bool>();
	static final functionScopePrepStack = new haxe.ds.StringMap<Bool>();
	static var functionScopePrepCache = new haxe.ds.StringMap<CppFunctionScopePrep>();
	static var functionArgDeclaredTypeCache = new haxe.ds.StringMap<String>();
	static var fieldCppTypeCache = new haxe.ds.StringMap<String>();
	static var functionArgTypesCache = new haxe.ds.StringMap<Array<String>>();
	static var functionReturnTypesCache = new haxe.ds.StringMap<String>();
	static var traceCppDeepEnabledCache = -1;
	static var traceCppTimingsEnabledCache = -1;
	static var traceCppHelperClassificationDetailsEnabledCache = -1;
	static var traceCppTimingMethodFilterCache:Null<String> = null;

	public static function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		traceCppPhase("emit_before_main_module");
		final main = mainModule(program, context);
		final className = sanitizeIdentifier(HxClassDecl.getName(main.cls));
		traceCppPhase("emit_after_main_module class=" + className);
		final sourceDir = Path.join([context.outputDir, "src"]);
		final sourcePath = context.outputFileHint != null
			&& context.outputFileHint.length > 0 ? context.outputFileHint : Path.join([sourceDir, className + ".cpp"]);
		traceCppPhase("emit_before_render_program");
		final source = renderProgram(program, main, context.resources);
		traceCppPhase("emit_after_render_program");
		ensureParentDirectory(sourcePath);
		traceCppPhase("emit_before_save_content path=" + sourcePath);
		sys.io.File.saveContent(sourcePath, source);
		traceCppPhase("emit_after_save_content");

		if (context.buildExecutable && !context.hasDefine("no-compilation")) {
			final exePath = executablePath(context.outputDir, className);
			ensureParentDirectory(exePath);
			final compiler = cppCompilerCommand();
			if (compiler == null)
				throw "C++ source backend MVP executable packaging requires `c++`, `g++`, or `clang++` on PATH";
			traceCppPhase("emit_before_native_compile compiler=" + compiler);
			final code = Sys.command(compiler, ["-std=c++17", sourcePath, "-o", exePath]);
			traceCppPhase("emit_after_native_compile code=" + code);
			if (code != 0)
				throw "C++ source backend MVP executable packaging failed with exit code " + code;
			return new EmitResult(exePath, [
				new EmitArtifact("entry_cpp_source", sourcePath),
				new EmitArtifact("entry_cpp_exe", exePath)
			], true);
		}

		return new EmitResult(sourcePath, [new EmitArtifact("entry_cpp_source", sourcePath)], false);
	}

	static function envFlagEnabled(name:String):Bool {
		final raw = Sys.getEnv(name);
		if (raw == null)
			return false;
		return switch (StringTools.trim(raw).toLowerCase()) {
			case "1" | "true" | "yes" | "on":
				true;
			case _:
				false;
		};
	}

	static function traceCppEnabled():Bool {
		return envFlagEnabled("HXHX_TRACE_STAGE3_DRIVER");
	}

	static function traceCppPhase(label:String):Void {
		if (traceCppEnabled())
			Sys.println("cpp_target_phase=" + label);
	}

	static function traceCppDeepEnabled():Bool {
		if (traceCppDeepEnabledCache < 0)
			traceCppDeepEnabledCache = envFlagEnabled("HXHX_TRACE_STAGE3_CPP_DEEP") ? 1 : 0;
		return traceCppDeepEnabledCache == 1;
	}

	static function traceCppDeepPhase(label:String):Void {
		if (traceCppDeepEnabled())
			Sys.println("cpp_target_phase=" + label);
	}

	static function traceCppTimingsEnabled():Bool {
		if (traceCppTimingsEnabledCache < 0)
			traceCppTimingsEnabledCache = envFlagEnabled("HXHX_TRACE_STAGE3_CPP_TIMINGS") ? 1 : 0;
		return traceCppTimingsEnabledCache == 1;
	}

	static function traceCppTimingPhase(label:String):Void {
		if (traceCppTimingsEnabled())
			Sys.println("cpp_target_phase=" + label);
	}

	static function traceCppHelperClassificationDetailsEnabled():Bool {
		if (traceCppHelperClassificationDetailsEnabledCache < 0)
			traceCppHelperClassificationDetailsEnabledCache = envFlagEnabled("HXHX_TRACE_STAGE3_CPP_HELPER_CLASSIFICATION_DETAILS") ? 1 : 0;
		return traceCppHelperClassificationDetailsEnabledCache == 1;
	}

	static function traceCppHelperClassificationDetailPhase(label:String):Void {
		if (traceCppHelperClassificationDetailsEnabled())
			Sys.println("cpp_target_phase=" + label);
	}

	static function traceCppTimingMethodFilter():String {
		if (traceCppTimingMethodFilterCache == null) {
			final raw = Sys.getEnv("HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER");
			traceCppTimingMethodFilterCache = raw == null ? "" : StringTools.trim(raw);
		}
		return traceCppTimingMethodFilterCache;
	}

	static function traceCppMethodStmtTimingsEnabled(ownerName:String, methodName:String):Bool {
		if (!traceCppTimingsEnabled())
			return false;
		final filter = traceCppTimingMethodFilter();
		if (filter.length == 0)
			return false;
		final owner = sanitizeTypePath(typeBaseName(ownerName == null ? "" : ownerName));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		return filter == owner + "." + method || filter == ownerName + "." + methodName || filter == method;
	}

	static function traceCppScopeStmtTimingEnabled(?scope:CppRenderScope):Bool {
		return scope != null
			&& scope.traceOwnerName != null
			&& scope.traceMethodName != null
			&& traceCppMethodStmtTimingsEnabled(scope.traceOwnerName, scope.traceMethodName);
	}

	static function traceCppScopeStmtTimingPhase(scope:CppRenderScope, label:String):Void {
		if (!traceCppScopeStmtTimingEnabled(scope))
			return;
		final index = scope.traceStmtIndex == null ? -1 : scope.traceStmtIndex;
		traceCppTimingPhase("render_helper_expr_timing owner=" + scope.traceOwnerName + " name=" + sanitizeIdentifier(scope.traceMethodName) + " index="
			+ Std.string(index) + " " + label);
	}

	static function traceCppTypeToken(typeName:String):String {
		return StringTools.replace(traceCppSnippet(typeName), " ", "_");
	}

	static function traceCallArgRenderPhase(scope:CppRenderScope, arg:HxExpr, param:Null<HxFunctionArg>, phase:String, elapsed:Float,
			declaredType:String = "", expectedType:String = "", valueType:String = "", actualType:String = "", detail:String = ""):Void {
		if (!traceCppScopeStmtTimingEnabled(scope))
			return;
		final index = scope.traceStmtIndex == null ? -1 : scope.traceStmtIndex;
		final paramName = param == null ? "" : sanitizeIdentifier(HxFunctionArg.getName(param));
		traceCppTimingPhase("render_helper_call_arg_render_phase_timing owner=" + scope.traceOwnerName + " name="
			+ sanitizeIdentifier(scope.traceMethodName) + " index=" + Std.string(index) + " kind=" + exprKind(arg) + " phase=" + phase + " seconds="
			+ Std.string(elapsed) + " param=" + paramName + " declared_type=" + traceCppTypeToken(declaredType) + " expected_type="
			+ traceCppTypeToken(expectedType) + " value_type=" + traceCppTypeToken(valueType) + " actual_type=" + traceCppTypeToken(actualType)
			+ (detail.length == 0 ? "" : " " + detail));
	}

	static function traceCallableArgExprPhase(scope:CppRenderScope, expr:HxExpr, phase:String, elapsed:Float, candidates:haxe.ds.StringMap<Bool>,
			expectedType:String):Void {
		if (!traceCppScopeStmtTimingEnabled(scope))
			return;
		final index = scope.traceStmtIndex == null ? -1 : scope.traceStmtIndex;
		final expected = traceCppTypeToken(expectedType);
		traceCppTimingPhase("render_helper_callable_arg_expr_phase_timing owner=" + scope.traceOwnerName + " name="
			+ sanitizeIdentifier(scope.traceMethodName) + " index=" + Std.string(index) + " kind=" + exprKind(expr) + " phase=" + phase + " seconds="
			+ Std.string(elapsed) + " expected_type=" + expected + " candidates=" + Std.string(countStringMap(candidates)) + " arg_overrides="
			+ Std.string(countStringMap(scope.argTypeOverrides)) + " local_overrides=" + Std.string(countStringMap(scope.localTypeOverrides))
			+ " local_types=" + Std.string(countStringMap(scope.localTypes)));
	}

	static function traceForwardedCallPhase(scope:CppRenderScope, callee:HxExpr, phase:String, elapsed:Float, candidates:haxe.ds.StringMap<Bool>,
			args:Array<HxExpr>, params:Null<Array<HxFunctionArg>>, paramIndex:Int = -1, argIndex:Int = -1, paramName:String = "", argKind:String = "",
			detail:String = ""):Void {
		if (!traceCppScopeStmtTimingEnabled(scope))
			return;
		final index = scope.traceStmtIndex == null ? -1 : scope.traceStmtIndex;
		traceCppTimingPhase("render_helper_forwarded_call_phase_timing owner=" + scope.traceOwnerName + " name=" + sanitizeIdentifier(scope.traceMethodName)
			+ " index=" + Std.string(index) + " callee=" + exprKind(callee) + " phase=" + phase + " seconds=" + Std.string(elapsed) + " args="
			+ Std.string(args == null ? 0 : args.length) + " params=" + Std.string(params == null ? 0 : params.length) + " param_index="
			+ Std.string(paramIndex) + " arg_index=" + Std.string(argIndex) + " param=" + sanitizeIdentifier(paramName) + " arg_kind=" + argKind
			+ " candidates=" + Std.string(countStringMap(candidates)) + " arg_overrides=" + Std.string(countStringMap(scope.argTypeOverrides))
			+ " local_overrides=" + Std.string(countStringMap(scope.localTypeOverrides)) + " local_types=" + Std.string(countStringMap(scope.localTypes))
			+ (detail.length == 0 ? "" : " " + detail));
	}

	static function traceCppMemberPhase(className:String, kind:String, memberName:String, stage:String):Void {
		if (!traceCppDeepEnabled())
			return;
		traceCppPhase(kind + " class=" + className + " member=" + sanitizeIdentifier(memberName) + " stage=" + stage);
	}

	static function traceCppSnippet(value:String):String {
		if (value == null)
			return "";
		var out = StringTools.replace(value, "\n", " ");
		out = StringTools.replace(out, "\r", " ");
		out = StringTools.replace(out, "\t", " ");
		return out.length > 160 ? out.substr(0, 160) + "..." : out;
	}

	static function findMainModule(program:GenIrProgram, context:BackendContext):Null<{decl:HxModuleDecl, cls:HxClassDecl, fn:HxFunctionDecl}> {
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
		return fallback;
	}

	static function mainModule(program:GenIrProgram, context:BackendContext):{decl:HxModuleDecl, cls:HxClassDecl, fn:HxFunctionDecl} {
		final found = findMainModule(program, context);
		if (found == null)
			throw "C++ source backend MVP requires a static main entrypoint";
		return found;
	}

	static function renderProgram(program:GenIrProgram, main:{decl:HxModuleDecl, cls:HxClassDecl, fn:HxFunctionDecl},
			resources:Array<backend.BackendResource>):String {
		functionScopePrepCache = new haxe.ds.StringMap<CppFunctionScopePrep>();
		functionArgDeclaredTypeCache = new haxe.ds.StringMap<String>();
		fieldCppTypeCache = new haxe.ds.StringMap<String>();
		functionArgTypesCache = new haxe.ds.StringMap<Array<String>>();
		functionReturnTypesCache = new haxe.ds.StringMap<String>();
		erasedDynamicReturnCache = new haxe.ds.StringMap<Bool>();
		traceCppTimingMethodFilterCache = null;
		final className = sanitizeIdentifier(HxClassDecl.getName(main.cls));
		final typedModules = program.getTypedModules();
		traceCppPhase("render_enter main=" + className + " typed_modules=" + typedModules.length);
		final out = new Array<String>();
		out.push("// Generated by hxhx Stage3 C++ source backend MVP");
		out.push("#include <cctype>");
		out.push("#include <algorithm>");
		out.push("#include <any>");
		out.push("#include <chrono>");
		out.push("#include <cmath>");
		out.push("#include <condition_variable>");
		out.push("#include <cstddef>");
		out.push("#include <cstdint>");
		out.push("#include <cstdlib>");
		out.push("#include <cstring>");
		out.push("#include <fstream>");
		out.push("#include <functional>");
		out.push("#include <iostream>");
		out.push("#include <limits>");
		out.push("#include <map>");
		out.push("#include <memory>");
		out.push("#include <mutex>");
		out.push("#include <optional>");
		out.push("#include <sstream>");
		out.push("#include <stdexcept>");
		out.push("#include <string>");
		out.push("#include <ctime>");
		out.push("#include <type_traits>");
		out.push("#include <typeinfo>");
		out.push("#include <utility>");
		out.push("#include <vector>");
		out.push("");
		out.push("template<typename T>");
		out.push("struct RawConstPointer {");
		out.push("  const char* ptr;");
		out.push("  explicit RawConstPointer(const char* ptr = nullptr) : ptr(ptr) {}");
		out.push("};");
		out.push("");
		out.push("template<typename T>");
		out.push("struct ConstPointer {");
		out.push("  const char* ptr;");
		out.push("  explicit ConstPointer(const char* ptr = nullptr) : ptr(ptr) {}");
		out.push("};");
		out.push("");
		for (line in CppRuntimeSupport.enumValueTypeLines())
			out.push(line);
		out.push("");
		out.push("static std::string __hxhx_string_from_pointer(const char* ptr) {");
		out.push("  return ptr == nullptr ? std::string() : std::string(ptr);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_string_from_pointer(const char* ptr, int len) {");
		out.push("  if (ptr == nullptr || len <= 0) return std::string();");
		out.push("  return std::string(ptr, static_cast<std::size_t>(len));");
		out.push("}");
		out.push("");
		for (line in CppRuntimeSupport.fpReinterpretLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.dateIntrinsicLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.stdIntrinsicLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.vectorSupportLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.borrowedSharedPtrLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.sysEventLoopLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.rttiMetaLines())
			out.push(line);
		out.push("");
		out.push("template<typename T>");
		out.push("struct __hxhx_iterator {");
		out.push("  virtual ~__hxhx_iterator() = default;");
		out.push("  virtual bool hasNext() = 0;");
		out.push("  virtual T next() = 0;");
		out.push("};");
		out.push("");
		out.push("template<typename T>");
		out.push("struct __hxhx_vector_iterator : public __hxhx_iterator<T> {");
		out.push("  const std::vector<T>* values;");
		out.push("  std::size_t index;");
		out.push("  explicit __hxhx_vector_iterator(const std::vector<T>& values) : values(&values), index(0) {}");
		out.push("  bool hasNext() override { return values != nullptr && index < values->size(); }");
		out.push("  T next() override { return (*values)[index++]; }");
		out.push("};");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::shared_ptr<__hxhx_iterator<T>> __hxhx_vector_iterator_of(const std::vector<T>& values) {");
		out.push("  return std::make_shared<__hxhx_vector_iterator<T>>(values);");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::vector<T> __hxhx_iterator_to_vector(std::shared_ptr<__hxhx_iterator<T>> iterator) {");
		out.push("  std::vector<T> out;");
		out.push("  while (iterator && iterator->hasNext()) out.push_back(iterator->next());");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("template<typename T, typename F>");
		out.push("static void __hxhx_vector_sort(std::vector<T>& values, F compare) {");
		out.push("  std::sort(values.begin(), values.end(), [&](const auto& left, const auto& right) { return compare(left, right) < 0; });");
		out.push("}");
		out.push("");
		for (line in CppMacroExpr.runtimePreludeLines())
			out.push(line);
		out.push("static std::string __hxhx_stringify(const __HxMacroExpr& value) {");
		out.push("  return __hxhx_macro_to_string(value);");
		out.push("}");
		out.push("");
		out.push("static std::vector<std::string> __hxhx_args(int argc, char** argv) {");
		out.push("  std::vector<std::string> out;");
		out.push("  for (int i = 1; i < argc; ++i) out.push_back(std::string(argv[i]));");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_index_of(const std::string& source, const std::string& needle, int start) {");
		out.push("  auto pos = source.find(needle, start < 0 ? 0 : static_cast<std::size_t>(start));");
		out.push("  return pos == std::string::npos ? -1 : static_cast<int>(pos);");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_index_of(const std::vector<std::string>& values, const std::string& needle, int start) {");
		out.push("  int begin = start < 0 ? 0 : start;");
		out.push("  for (int i = begin; i < static_cast<int>(values.size()); ++i) if (values[i] == needle) return i;");
		out.push("  return -1;");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_index_of(const std::vector<int>& values, int needle, int start) {");
		out.push("  int begin = start < 0 ? 0 : start;");
		out.push("  for (int i = begin; i < static_cast<int>(values.size()); ++i) if (values[i] == needle) return i;");
		out.push("  return -1;");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::string __hxhx_join(const std::vector<T>& values, const std::string& separator) {");
		out.push("  std::ostringstream out;");
		out.push("  for (std::size_t i = 0; i < values.size(); ++i) {");
		out.push("    if (i > 0) out << separator;");
		out.push("    out << values[i];");
		out.push("  }");
		out.push("  return out.str();");
		out.push("}");
		out.push("");
		out.push("static std::vector<std::string> __hxhx_split(const std::string& source, const std::string& delimiter) {");
		out.push("  std::vector<std::string> out;");
		out.push("  if (delimiter.empty()) {");
		out.push("    for (char c : source) out.push_back(std::string(1, c));");
		out.push("    return out;");
		out.push("  }");
		out.push("  std::size_t start = 0;");
		out.push("  while (true) {");
		out.push("    std::size_t pos = source.find(delimiter, start);");
		out.push("    if (pos == std::string::npos) {");
		out.push("      out.push_back(source.substr(start));");
		out.push("      return out;");
		out.push("    }");
		out.push("    out.push_back(source.substr(start, pos - start));");
		out.push("    start = pos + delimiter.size();");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_ends_with(const std::string& source, const std::string& suffix) {");
		out.push("  return suffix.size() <= source.size() && source.compare(source.size() - suffix.size(), suffix.size(), suffix) == 0;");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_last_index_of(const std::string& source, const std::string& needle, int start) {");
		out.push("  if (start < 0) return -1;");
		out.push("  std::size_t pos = source.rfind(needle, static_cast<std::size_t>(start));");
		out.push("  return pos == std::string::npos ? -1 : static_cast<int>(pos);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_replace(const std::string& source, const std::string& needle, const std::string& replacement) {");
		out.push("  if (needle.empty()) {");
		out.push("    if (source.empty()) return std::string();");
		out.push("    std::ostringstream out;");
		out.push("    for (std::size_t i = 0; i < source.size(); ++i) {");
		out.push("      if (i > 0) out << replacement;");
		out.push("      out << source[i];");
		out.push("    }");
		out.push("    return out.str();");
		out.push("  }");
		out.push("  std::string out;");
		out.push("  std::size_t start = 0;");
		out.push("  while (true) {");
		out.push("    std::size_t pos = source.find(needle, start);");
		out.push("    if (pos == std::string::npos) {");
		out.push("      out.append(source, start, std::string::npos);");
		out.push("      return out;");
		out.push("    }");
		out.push("    out.append(source, start, pos - start);");
		out.push("    out.append(replacement);");
		out.push("    start = pos + needle.size();");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_bytes_blit(std::vector<int>& dst, int dstPos, const std::vector<int>& src, int srcPos, int len) {");
		out.push("  if (dstPos < 0 || srcPos < 0 || len < 0 || dstPos + len > static_cast<int>(dst.size()) || srcPos + len > static_cast<int>(src.size()))");
		out.push("    throw std::runtime_error(\"OutsideBounds\");");
		out.push("  if (&dst == &src && dstPos > srcPos) {");
		out.push("    for (int i = len - 1; i >= 0; --i) dst[dstPos + i] = src[srcPos + i] & 0xFF;");
		out.push("  } else {");
		out.push("    for (int i = 0; i < len; ++i) dst[dstPos + i] = src[srcPos + i] & 0xFF;");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("static std::vector<int> __hxhx_bytes_slice(const std::vector<int>& src, int start, int end) {");
		out.push("  if (start < 0 || end < start || end > static_cast<int>(src.size())) throw std::runtime_error(\"OutsideBounds\");");
		out.push("  return std::vector<int>(src.begin() + start, src.begin() + end);");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_bytes_memcmp(const std::vector<int>& a, const std::vector<int>& b) {");
		out.push("  int len = static_cast<int>(std::min(a.size(), b.size()));");
		out.push("  for (int i = 0; i < len; ++i) {");
		out.push("    int diff = (a[i] & 0xFF) - (b[i] & 0xFF);");
		out.push("    if (diff != 0) return diff;");
		out.push("  }");
		out.push("  return static_cast<int>(a.size()) - static_cast<int>(b.size());");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_bytes_fill(std::vector<int>& dst, int pos, int len, int value) {");
		out.push("  if (pos < 0 || len < 0 || pos + len > static_cast<int>(dst.size())) throw std::runtime_error(\"OutsideBounds\");");
		out.push("  std::fill(dst.begin() + pos, dst.begin() + pos + len, value & 0xFF);");
		out.push("}");
		out.push("");
		out.push("static double __hxhx_memory_get_double(const std::vector<int>& src, int pos) {");
		out.push("  unsigned char bytes[8];");
		out.push("  for (int i = 0; i < 8; ++i) bytes[i] = static_cast<unsigned char>(src[pos + i] & 0xFF);");
		out.push("  double out = 0;");
		out.push("  std::memcpy(&out, bytes, 8);");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static double __hxhx_memory_get_float(const std::vector<int>& src, int pos) {");
		out.push("  unsigned char bytes[4];");
		out.push("  for (int i = 0; i < 4; ++i) bytes[i] = static_cast<unsigned char>(src[pos + i] & 0xFF);");
		out.push("  float out = 0;");
		out.push("  std::memcpy(&out, bytes, 4);");
		out.push("  return static_cast<double>(out);");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_memory_set_double(std::vector<int>& dst, int pos, double value) {");
		out.push("  unsigned char bytes[8];");
		out.push("  std::memcpy(bytes, &value, 8);");
		out.push("  for (int i = 0; i < 8; ++i) dst[pos + i] = static_cast<int>(bytes[i]);");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_memory_set_float(std::vector<int>& dst, int pos, double value) {");
		out.push("  float f = static_cast<float>(value);");
		out.push("  unsigned char bytes[4];");
		out.push("  std::memcpy(bytes, &f, 4);");
		out.push("  for (int i = 0; i < 4; ++i) dst[pos + i] = static_cast<int>(bytes[i]);");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_string_of_bytes(const std::vector<int>& src, std::string& out, int pos, int len) {");
		out.push("  out.clear();");
		out.push("  out.reserve(static_cast<std::size_t>(len));");
		out.push("  for (int i = 0; i < len; ++i) out.push_back(static_cast<char>(src[pos + i] & 0xFF));");
		out.push("}");
		out.push("");
		out.push("static void __hxhx_bytes_of_string(std::vector<int>& out, const std::string& source) {");
		out.push("  out.clear();");
		out.push("  out.reserve(source.size());");
		out.push("  for (unsigned char c : source) out.push_back(static_cast<int>(c));");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_bytes_to_hex(const std::vector<int>& bytes) {");
		out.push("  static const char* hex = \"0123456789abcdef\";");
		out.push("  std::string out;");
		out.push("  out.reserve(bytes.size() * 2);");
		out.push("  for (int value : bytes) {");
		out.push("    const unsigned char byte = static_cast<unsigned char>(value & 0xFF);");
		out.push("    out.push_back(hex[(byte >> 4) & 0x0F]);");
		out.push("    out.push_back(hex[byte & 0x0F]);");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		for (line in CppRuntimeSupport.resourceLines(resources))
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.baseCodeLines())
			out.push(line);
		out.push("");
		for (line in CppRuntimeSupport.sha1Lines())
			out.push(line);
		out.push("");
		out.push("static std::string __hxhx_base64_encode_bytes(const std::vector<int>& bytes, bool complement, const std::string& alphabet) {");
		out.push("  std::string out;");
		out.push("  int buf = 0;");
		out.push("  int curbits = 0;");
		out.push("  const int nbits = 6;");
		out.push("  const int mask = (1 << nbits) - 1;");
		out.push("  const int size = static_cast<int>((bytes.size() * 8) / nbits);");
		out.push("  int pin = 0;");
		out.push("  int pout = 0;");
		out.push("  out.reserve(static_cast<std::size_t>(size + 3));");
		out.push("  while (pout < size) {");
		out.push("    while (curbits < nbits) {");
		out.push("      curbits += 8;");
		out.push("      buf <<= 8;");
		out.push("      buf |= bytes[static_cast<std::size_t>(pin++)] & 0xFF;");
		out.push("    }");
		out.push("    curbits -= nbits;");
		out.push("    out.push_back(alphabet[static_cast<std::size_t>((buf >> curbits) & mask)]);");
		out.push("    ++pout;");
		out.push("  }");
		out.push("  if (curbits > 0) out.push_back(alphabet[static_cast<std::size_t>((buf << (nbits - curbits)) & mask)]);");
		out.push("  if (complement) {");
		out.push("    switch (bytes.size() % 3) {");
		out.push("      case 1: out += \"==\"; break;");
		out.push("      case 2: out += \"=\"; break;");
		out.push("      default: break;");
		out.push("    }");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::vector<int> __hxhx_base64_decode_bytes(const std::string& input, bool complement, const std::string& alphabet) {");
		out.push("  std::string source = input;");
		out.push("  if (complement) while (!source.empty() && source[source.size() - 1] == '=') source.resize(source.size() - 1);");
		out.push("  std::vector<int> table(256, -1);");
		out.push("  for (std::size_t i = 0; i < alphabet.size(); ++i) table[static_cast<unsigned char>(alphabet[i])] = static_cast<int>(i);");
		out.push("  const int nbits = 6;");
		out.push("  const int size = static_cast<int>((source.size() * nbits) >> 3);");
		out.push("  std::vector<int> out(static_cast<std::size_t>(size));");
		out.push("  int buf = 0;");
		out.push("  int curbits = 0;");
		out.push("  int pin = 0;");
		out.push("  int pout = 0;");
		out.push("  while (pout < size) {");
		out.push("    while (curbits < 8) {");
		out.push("      if (pin >= static_cast<int>(source.size())) throw std::runtime_error(\"BaseCode : invalid encoded char\");");
		out.push("      curbits += nbits;");
		out.push("      buf <<= nbits;");
		out.push("      int value = table[static_cast<unsigned char>(source[static_cast<std::size_t>(pin++)])];");
		out.push("      if (value == -1) throw std::runtime_error(\"BaseCode : invalid encoded char\");");
		out.push("      buf |= value;");
		out.push("    }");
		out.push("    curbits -= 8;");
		out.push("    out[static_cast<std::size_t>(pout++)] = (buf >> curbits) & 0xFF;");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::uint32_t __hxhx_md5_rotate_left(std::uint32_t value, std::uint32_t shift) {");
		out.push("  return (value << shift) | (value >> (32 - shift));");
		out.push("}");
		out.push("");
		out.push("static std::vector<int> __hxhx_md5_digest_bytes(const std::vector<int>& input) {");
		out.push("  static const std::uint32_t shifts[64] = {");
		out.push("    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,");
		out.push("    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,");
		out.push("    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,");
		out.push("    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21");
		out.push("  };");
		out.push("  static const std::uint32_t constants[64] = {");
		out.push("    0xd76aa478U, 0xe8c7b756U, 0x242070dbU, 0xc1bdceeeU, 0xf57c0fafU, 0x4787c62aU, 0xa8304613U, 0xfd469501U,");
		out.push("    0x698098d8U, 0x8b44f7afU, 0xffff5bb1U, 0x895cd7beU, 0x6b901122U, 0xfd987193U, 0xa679438eU, 0x49b40821U,");
		out.push("    0xf61e2562U, 0xc040b340U, 0x265e5a51U, 0xe9b6c7aaU, 0xd62f105dU, 0x02441453U, 0xd8a1e681U, 0xe7d3fbc8U,");
		out.push("    0x21e1cde6U, 0xc33707d6U, 0xf4d50d87U, 0x455a14edU, 0xa9e3e905U, 0xfcefa3f8U, 0x676f02d9U, 0x8d2a4c8aU,");
		out.push("    0xfffa3942U, 0x8771f681U, 0x6d9d6122U, 0xfde5380cU, 0xa4beea44U, 0x4bdecfa9U, 0xf6bb4b60U, 0xbebfbc70U,");
		out.push("    0x289b7ec6U, 0xeaa127faU, 0xd4ef3085U, 0x04881d05U, 0xd9d4d039U, 0xe6db99e5U, 0x1fa27cf8U, 0xc4ac5665U,");
		out.push("    0xf4292244U, 0x432aff97U, 0xab9423a7U, 0xfc93a039U, 0x655b59c3U, 0x8f0ccc92U, 0xffeff47dU, 0x85845dd1U,");
		out.push("    0x6fa87e4fU, 0xfe2ce6e0U, 0xa3014314U, 0x4e0811a1U, 0xf7537e82U, 0xbd3af235U, 0x2ad7d2bbU, 0xeb86d391U");
		out.push("  };");
		out.push("  std::vector<unsigned char> message;");
		out.push("  message.reserve(input.size() + 72);");
		out.push("  for (int value : input) message.push_back(static_cast<unsigned char>(value & 0xFF));");
		out.push("  std::uint64_t bitLength = static_cast<std::uint64_t>(message.size()) * 8ULL;");
		out.push("  message.push_back(0x80);");
		out.push("  while ((message.size() % 64) != 56) message.push_back(0);");
		out.push("  for (int i = 0; i < 8; ++i) message.push_back(static_cast<unsigned char>((bitLength >> (8 * i)) & 0xFF));");
		out.push("  std::uint32_t a0 = 0x67452301U;");
		out.push("  std::uint32_t b0 = 0xefcdab89U;");
		out.push("  std::uint32_t c0 = 0x98badcfeU;");
		out.push("  std::uint32_t d0 = 0x10325476U;");
		out.push("  for (std::size_t offset = 0; offset < message.size(); offset += 64) {");
		out.push("    std::uint32_t words[16];");
		out.push("    for (int i = 0; i < 16; ++i) {");
		out.push("      std::size_t p = offset + static_cast<std::size_t>(i * 4);");
		out.push("      words[i] = static_cast<std::uint32_t>(message[p])");
		out.push("        | (static_cast<std::uint32_t>(message[p + 1]) << 8)");
		out.push("        | (static_cast<std::uint32_t>(message[p + 2]) << 16)");
		out.push("        | (static_cast<std::uint32_t>(message[p + 3]) << 24);");
		out.push("    }");
		out.push("    std::uint32_t a = a0;");
		out.push("    std::uint32_t b = b0;");
		out.push("    std::uint32_t c = c0;");
		out.push("    std::uint32_t d = d0;");
		out.push("    for (std::uint32_t i = 0; i < 64; ++i) {");
		out.push("      std::uint32_t f = 0;");
		out.push("      std::uint32_t g = 0;");
		out.push("      if (i < 16) {");
		out.push("        f = (b & c) | ((~b) & d);");
		out.push("        g = i;");
		out.push("      } else if (i < 32) {");
		out.push("        f = (d & b) | ((~d) & c);");
		out.push("        g = (5 * i + 1) % 16;");
		out.push("      } else if (i < 48) {");
		out.push("        f = b ^ c ^ d;");
		out.push("        g = (3 * i + 5) % 16;");
		out.push("      } else {");
		out.push("        f = c ^ (b | (~d));");
		out.push("        g = (7 * i) % 16;");
		out.push("      }");
		out.push("      std::uint32_t next = d;");
		out.push("      d = c;");
		out.push("      c = b;");
		out.push("      b = b + __hxhx_md5_rotate_left(a + f + constants[i] + words[g], shifts[i]);");
		out.push("      a = next;");
		out.push("    }");
		out.push("    a0 += a;");
		out.push("    b0 += b;");
		out.push("    c0 += c;");
		out.push("    d0 += d;");
		out.push("  }");
		out.push("  std::vector<int> out;");
		out.push("  out.reserve(16);");
		out.push("  std::uint32_t digest[4] = {a0, b0, c0, d0};");
		out.push("  for (std::uint32_t word : digest) {");
		out.push("    out.push_back(static_cast<int>(word & 0xFF));");
		out.push("    out.push_back(static_cast<int>((word >> 8) & 0xFF));");
		out.push("    out.push_back(static_cast<int>((word >> 16) & 0xFF));");
		out.push("    out.push_back(static_cast<int>((word >> 24) & 0xFF));");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::vector<int> __hxhx_md5_digest_string(const std::string& source) {");
		out.push("  std::vector<int> bytes;");
		out.push("  bytes.reserve(source.size());");
		out.push("  for (unsigned char c : source) bytes.push_back(static_cast<int>(c));");
		out.push("  return __hxhx_md5_digest_bytes(bytes);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_md5_hex(const std::vector<int>& digest) {");
		out.push("  static const char* hex = \"0123456789abcdef\";");
		out.push("  std::string out;");
		out.push("  out.reserve(digest.size() * 2);");
		out.push("  for (int value : digest) {");
		out.push("    unsigned char byte = static_cast<unsigned char>(value & 0xFF);");
		out.push("    out.push_back(hex[(byte >> 4) & 0x0F]);");
		out.push("    out.push_back(hex[byte & 0x0F]);");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_md5_hex_string(const std::string& source) {");
		out.push("  return __hxhx_md5_hex(__hxhx_md5_digest_string(source));");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_char_at(const std::string& source, int index) {");
		out.push("  if (index < 0 || index >= static_cast<int>(source.size())) return std::string();");
		out.push("  return std::string(1, source[static_cast<std::size_t>(index)]);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_to_upper_case(const std::string& source) {");
		out.push("  std::string out = source;");
		out.push("  std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_to_lower_case(const std::string& source) {");
		out.push("  std::string out = source;");
		out.push("  std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static std::optional<int> __hxhx_string_code_at(const std::string& source, int index) {");
		out.push("  if (index < 0 || index >= static_cast<int>(source.size())) return std::nullopt;");
		out.push("  return static_cast<int>(static_cast<unsigned char>(source[static_cast<std::size_t>(index)]));");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_substring(const std::string& source, int start, int end) {");
		out.push("  int len = static_cast<int>(source.size());");
		out.push("  if (start < 0) start = 0;");
		out.push("  if (end < 0) end = 0;");
		out.push("  if (start > len) start = len;");
		out.push("  if (end > len) end = len;");
		out.push("  if (start > end) std::swap(start, end);");
		out.push("  return source.substr(static_cast<std::size_t>(start), static_cast<std::size_t>(end - start));");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_ltrim(const std::string& value) {");
		out.push("  std::size_t start = 0;");
		out.push("  while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) ++start;");
		out.push("  return value.substr(start);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_rtrim(const std::string& value) {");
		out.push("  std::size_t end = value.size();");
		out.push("  while (end > 0 && std::isspace(static_cast<unsigned char>(value[end - 1]))) --end;");
		out.push("  return value.substr(0, end);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_trim(const std::string& value) {");
		out.push("  return __hxhx_rtrim(__hxhx_ltrim(value));");
		out.push("}");
		out.push("");
		out.push("static char __hxhx_hex_digit(unsigned char value) {");
		out.push("  return value < 10 ? static_cast<char>('0' + value) : static_cast<char>('A' + (value - 10));");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_url_encode(const std::string& value) {");
		out.push("  std::ostringstream out;");
		out.push("  for (unsigned char c : value) {");
		out.push("    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {");
		out.push("      out << static_cast<char>(c);");
		out.push("    } else {");
		out.push("      out << '%' << __hxhx_hex_digit(static_cast<unsigned char>(c >> 4)) << __hxhx_hex_digit(static_cast<unsigned char>(c & 15));");
		out.push("    }");
		out.push("  }");
		out.push("  return out.str();");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_from_hex(unsigned char c) {");
		out.push("  if (c >= '0' && c <= '9') return c - '0';");
		out.push("  if (c >= 'A' && c <= 'F') return 10 + (c - 'A');");
		out.push("  if (c >= 'a' && c <= 'f') return 10 + (c - 'a');");
		out.push("  return -1;");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_url_decode(const std::string& value) {");
		out.push("  std::ostringstream out;");
		out.push("  for (std::size_t i = 0; i < value.size(); ++i) {");
		out.push("    unsigned char c = static_cast<unsigned char>(value[i]);");
		out.push("    if (c == '%' && i + 2 < value.size()) {");
		out.push("      int hi = __hxhx_from_hex(static_cast<unsigned char>(value[i + 1]));");
		out.push("      int lo = __hxhx_from_hex(static_cast<unsigned char>(value[i + 2]));");
		out.push("      if (hi >= 0 && lo >= 0) {");
		out.push("        out << static_cast<char>((hi << 4) | lo);");
		out.push("        i += 2;");
		out.push("        continue;");
		out.push("      }");
		out.push("    }");
		out.push("    out << static_cast<char>(c);");
		out.push("  }");
		out.push("  return out.str();");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_quote_unix_safe_char(unsigned char c) {");
		out.push("  return std::isalnum(c) || c == '_' || c == '@' || c == '%' || c == '+' || c == '=' || c == ':' || c == ',' || c == '.' || c == '/' || c == '-';");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_quote_unix_arg(const std::string& argument) {");
		out.push("  if (argument.empty()) return std::string(\"''\");");
		out.push("  bool safe = true;");
		out.push("  for (unsigned char c : argument) {");
		out.push("    if (!__hxhx_quote_unix_safe_char(c)) { safe = false; break; }");
		out.push("  }");
		out.push("  if (safe) return argument;");
		out.push("  std::string out = \"'\";");
		out.push("  for (char c : argument) {");
		out.push("    if (c == 39) out += \"'\\\"'\\\"'\";");
		out.push("    else out.push_back(c);");
		out.push("  }");
		out.push("  out += \"'\";");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_quote_win_simple_arg(const std::string& argument) {");
		out.push("  if (argument.empty()) return false;");
		out.push("  std::size_t start = argument[0] == '/' ? 1 : 0;");
		out.push("  if (start >= argument.size()) return false;");
		out.push("  for (std::size_t i = start; i < argument.size(); ++i) {");
		out.push("    unsigned char c = static_cast<unsigned char>(argument[i]);");
		out.push("    if (c == 32 || c == 9 || c == '/' || c == 92 || c == 34) return false;");
		out.push("  }");
		out.push("  return true;");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_quote_win_meta_char(unsigned char c) {");
		out.push("  switch (c) {");
		out.push("    case 32: case 40: case 41: case 37: case 33: case 94: case 34: case 60: case 62: case 38: case 124: case 10: case 13: case 44: case 59:");
		out.push("      return true;");
		out.push("    default:");
		out.push("      return false;");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_quote_win_arg(std::string argument, bool escapeMetaCharacters) {");
		out.push("  if (!__hxhx_quote_win_simple_arg(argument)) {");
		out.push("    std::string result;");
		out.push("    bool needquote = argument.find(' ') != std::string::npos || argument.find(static_cast<char>(9)) != std::string::npos || argument.empty() || argument.find('/') > 0;");
		out.push("    if (needquote) result.push_back(static_cast<char>(34));");
		out.push("    std::string bs;");
		out.push("    for (char ch : argument) {");
		out.push("      if (ch == 92) {");
		out.push("        bs.push_back(static_cast<char>(92));");
		out.push("      } else if (ch == 34) {");
		out.push("        result += bs;");
		out.push("        result += bs;");
		out.push("        bs.clear();");
		out.push("        result.push_back(static_cast<char>(92));");
		out.push("        result.push_back(static_cast<char>(34));");
		out.push("      } else {");
		out.push("        if (!bs.empty()) { result += bs; bs.clear(); }");
		out.push("        result.push_back(ch);");
		out.push("      }");
		out.push("    }");
		out.push("    result += bs;");
		out.push("    if (needquote) { result += bs; result.push_back(static_cast<char>(34)); }");
		out.push("    argument = result;");
		out.push("  }");
		out.push("  if (!escapeMetaCharacters) return argument;");
		out.push("  std::string escaped;");
		out.push("  for (unsigned char c : argument) {");
		out.push("    if (__hxhx_quote_win_meta_char(c)) escaped.push_back('^');");
		out.push("    escaped.push_back(static_cast<char>(c));");
		out.push("  }");
		out.push("  return escaped;");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("static bool __hxhx_is_type(const T&, const std::string& type) {");
		out.push("  return type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_is_type(const std::string&, const std::string& type) {");
		out.push("  return type == \"String\" || type == \"StdTypes.String\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_is_type(const char*, const std::string& type) {");
		out.push("  return type == \"String\" || type == \"StdTypes.String\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_is_type(int, const std::string& type) {");
		out.push("  return type == \"Int\" || type == \"StdTypes.Int\" || type == \"Float\" || type == \"StdTypes.Float\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_is_type(double, const std::string& type) {");
		out.push("  return type == \"Float\" || type == \"StdTypes.Float\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("static bool __hxhx_is_type(bool, const std::string& type) {");
		out.push("  return type == \"Bool\" || type == \"StdTypes.Bool\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		for (line in CppRuntimeSupport.anyIsTypeLines())
			out.push(line);
		out.push("");
		out.push("template<typename T>");
		out.push("static bool __hxhx_is_type(const std::vector<T>&, const std::string& type) {");
		out.push("  return type == \"Array\" || type == \"Dynamic\" || type == \"Any\";");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::string __hxhx_type_name(const T&) {");
		out.push("  return std::string(\"Dynamic\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(const std::string&) {");
		out.push("  return std::string(\"String\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(const char*) {");
		out.push("  return std::string(\"String\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(int) {");
		out.push("  return std::string(\"Int\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(double) {");
		out.push("  return std::string(\"Float\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(bool) {");
		out.push("  return std::string(\"Bool\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(const std::shared_ptr<EnumValue>& value) {");
		out.push("  return value == nullptr ? std::string(\"Null\") : value->getName();");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_type_name(const std::any& value) {");
		out.push("  if (!value.has_value()) return std::string(\"Null\");");
		out.push("  const std::type_info& type = value.type();");
		out.push("  if (type == typeid(std::string) || type == typeid(const char*)) return std::string(\"String\");");
		out.push("  if (type == typeid(bool)) return std::string(\"Bool\");");
		out.push("  if (type == typeid(int)) return std::string(\"Int\");");
		out.push("  if (type == typeid(double) || type == typeid(float)) return std::string(\"Float\");");
		out.push("  if (type == typeid(std::shared_ptr<EnumValue>)) return __hxhx_type_name(std::any_cast<std::shared_ptr<EnumValue>>(value));");
		out.push("  return std::string(\"Dynamic\");");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::string __hxhx_type_name(const std::vector<T>&) {");
		out.push("  return std::string(\"Array\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_stringify(const std::string& value) {");
		out.push("  return value;");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_stringify(const char* value) {");
		out.push("  return value == nullptr ? std::string() : std::string(value);");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_stringify(bool value) {");
		out.push("  return value ? std::string(\"true\") : std::string(\"false\");");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_stringify(const std::shared_ptr<EnumValue>& value) {");
		out.push("  return value == nullptr ? std::string(\"null\") : value->getName();");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_stringify(const std::any& value) {");
		out.push("  if (!value.has_value()) return std::string();");
		out.push("  const std::type_info& type = value.type();");
		out.push("  if (type == typeid(std::string)) return std::any_cast<std::string>(value);");
		out.push("  if (type == typeid(const char*)) return __hxhx_stringify(std::any_cast<const char*>(value));");
		out.push("  if (type == typeid(bool)) return __hxhx_stringify(std::any_cast<bool>(value));");
		out.push("  if (type == typeid(int)) return std::to_string(std::any_cast<int>(value));");
		out.push("  if (type == typeid(double)) return std::to_string(std::any_cast<double>(value));");
		out.push("  if (type == typeid(float)) return std::to_string(std::any_cast<float>(value));");
		out.push("  if (type == typeid(std::shared_ptr<EnumValue>)) return __hxhx_stringify(std::any_cast<std::shared_ptr<EnumValue>>(value));");
		out.push("  return __hxhx_type_name(value);");
		out.push("}");
		out.push("");
		for (line in CppRuntimeSupport.enumValueDynamicLines())
			out.push(line);
		out.push("");
		out.push("template<typename T, typename = void>");
		out.push("struct __hxhx_is_streamable : std::false_type {};");
		out.push("");
		out.push("template<typename T>");
		out.push("struct __hxhx_is_streamable<T, std::void_t<decltype(std::declval<std::ostringstream&>() << std::declval<const T&>())>> : std::true_type {};");
		out.push("");
		out.push("template<typename T>");
		out.push("static std::string __hxhx_stringify(const T& value) {");
		out.push("  if constexpr (__hxhx_is_streamable<T>::value) {");
		out.push("    std::ostringstream out;");
		out.push("    out << value;");
		out.push("    return out.str();");
		out.push("  } else {");
		out.push("    return __hxhx_type_name(value);");
		out.push("  }");
		out.push("}");
		out.push("");
		for (line in CppRuntimeSupport.compareLines())
			out.push(line);
		out.push("");
		out.push("template<typename T>");
		out.push("static std::string __hxhx_stringify(const std::vector<T>& values) {");
		out.push("  std::ostringstream out;");
		out.push("  out << \"[\";");
		out.push("  for (std::size_t i = 0; i < values.size(); ++i) {");
		out.push("    if (i > 0) out << \",\";");
		out.push("    out << __hxhx_stringify(values[i]);");
		out.push("  }");
		out.push("  out << \"]\";");
		out.push("  return out.str();");
		out.push("}");
		out.push("");
		out.push("template<typename K, typename V>");
		out.push("static std::string __hxhx_map_literal_to_string(const std::vector<std::pair<K, V>>& values) {");
		out.push("  std::ostringstream out;");
		out.push("  out << \"[\";");
		out.push("  for (std::size_t i = 0; i < values.size(); ++i) {");
		out.push("    if (i > 0) out << \", \";");
		out.push("    out << __hxhx_stringify(values[i].first) << \" => \" << __hxhx_stringify(values[i].second);");
		out.push("  }");
		out.push("  out << \"]\";");
		out.push("  return out.str();");
		out.push("}");
		out.push("");
		out.push("template<typename T, typename U, typename = void>");
		out.push("struct __hxhx_has_equals_method : std::false_type {};");
		out.push("");
		out.push("template<typename T, typename U>");
		out.push("struct __hxhx_has_equals_method<T, U, std::void_t<decltype(std::declval<T>()->equals(std::declval<U>()))>> : std::true_type {};");
		out.push("");
		out.push("template<typename T, typename U>");
		out.push("static bool __hxhx_key_eq(const T& left, const U& right) {");
		out.push("  if constexpr (__hxhx_has_equals_method<T, U>::value) {");
		out.push("    if (left == nullptr || right == nullptr) return left == right;");
		out.push("    return left->equals(right);");
		out.push("  } else {");
		out.push("    return left == right;");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("template<typename T, typename F>");
		out.push("static std::vector<std::string> __hxhx_vector_map_string(const std::vector<T>& values, F f) {");
		out.push("  std::vector<std::string> out;");
		out.push("  out.reserve(values.size());");
		out.push("  for (const auto& value : values) {");
		out.push("    if constexpr (std::is_void_v<decltype(f(value))>) {");
		out.push("      f(value);");
		out.push("      out.push_back(std::string());");
		out.push("    } else {");
		out.push("      out.push_back(__hxhx_stringify(f(value)));");
		out.push("    }");
		out.push("  }");
		out.push("  return out;");
		out.push("}");
		out.push("");
		out.push("struct __hxhx_dynamic_value {");
		out.push("  std::string text;");
		out.push("  __hxhx_dynamic_value(std::string text = std::string()) : text(text) {}");
		out.push("  operator std::string() const { return text; }");
		out.push("};");
		out.push("");
		out.push("static std::string __hxhx_stringify(const __hxhx_dynamic_value& value) {");
		out.push("  return value.text;");
		out.push("}");
		out.push("");
		out.push("struct __hxhx_exception_pos_infos {");
		out.push("  std::string className;");
		out.push("  std::string methodName;");
		out.push("  __hxhx_exception_pos_infos(std::string className = std::string(), std::string methodName = std::string()) : className(className), methodName(methodName) {}");
		out.push("};");
		out.push("");
		out.push("struct __hxhx_exception_value {");
		out.push("  std::string message;");
		out.push("  __hxhx_dynamic_value value;");
		out.push("  std::vector<std::string> stack;");
		out.push("  __hxhx_exception_pos_infos posInfos;");
		out.push("  std::string argument;");
		out.push("  __hxhx_exception_value(std::string message = std::string()) : message(message), value(message), stack(), posInfos(), argument() {}");
		out.push("  operator std::string() const { return message; }");
		out.push("  std::string toString() const { return message; }");
		out.push("};");
		out.push("");
		out.push("static std::string __hxhx_stringify(const __hxhx_exception_value& value) {");
		out.push("  return value.message;");
		out.push("}");
		out.push("");
		out.push("struct __hxhx_throw_bottom {");
		out.push("  template<typename T>");
		out.push("  operator T() const { throw std::runtime_error(\"unreachable throw expression\"); }");
		out.push("};");
		out.push("");
		out.push("template<typename T>");
		out.push("static __hxhx_throw_bottom __hxhx_throw(const T& value) {");
		out.push("  throw std::runtime_error(__hxhx_stringify(value));");
		out.push("}");
		out.push("");
		out.push("static __hxhx_throw_bottom __hxhx_throw(const char* value) {");
		out.push("  throw std::runtime_error(__hxhx_stringify(value));");
		out.push("}");
		out.push("");
		out.push("template<typename TResult, typename T>");
		out.push("static TResult __hxhx_throw_as(const T& value) {");
		out.push("  throw std::runtime_error(__hxhx_stringify(value));");
		out.push("}");
		out.push("");
		out.push("template<typename TResult>");
		out.push("static TResult __hxhx_throw_as(const char* value) {");
		out.push("  throw std::runtime_error(__hxhx_stringify(value));");
		out.push("}");
		out.push("");
		out.push("template<typename TResult, typename... Args>");
		out.push("static TResult __hxhx_call_macro_api(const std::string&, int, Args&&...) {");
		out.push("  if constexpr (std::is_void_v<TResult>) { return; } else { return TResult{}; }");
		out.push("}");
		out.push("");
		out.push("template<typename TResult>");
		out.push("static TResult __hxhx_call_macro_api(const std::string& name) {");
		out.push("  return __hxhx_call_macro_api<TResult>(name, 0);");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("T& __hxhx_status_ref(T& status) {");
		out.push("  return status;");
		out.push("}");
		out.push("");
		out.push("template<typename T>");
		out.push("T& __hxhx_status_ref(std::shared_ptr<T>& status) {");
		out.push("  if (status == nullptr) status = std::make_shared<T>();");
		out.push("  return *status;");
		out.push("}");
		out.push("");
		out.push("template<typename A, typename B>");
		out.push("static bool __hxhx_same_as(const A& expected, const B& value, double approx) {");
		out.push("  if constexpr (std::is_arithmetic_v<A> && std::is_arithmetic_v<B>) {");
		out.push("    return std::fabs(static_cast<double>(expected) - static_cast<double>(value)) <= approx;");
		out.push("  } else {");
		out.push("    return __hxhx_stringify(expected) == __hxhx_stringify(value);");
		out.push("  }");
		out.push("}");
		out.push("");
		out.push("template<typename A, typename B>");
		out.push("static bool __hxhx_same_as(const std::vector<A>& expected, const std::vector<B>& value, double approx) {");
		out.push("  if (expected.size() != value.size()) return false;");
		out.push("  for (std::size_t i = 0; i < expected.size(); ++i) {");
		out.push("    if (!__hxhx_same_as(expected[i], value[i], approx)) return false;");
		out.push("  }");
		out.push("  return true;");
		out.push("}");
		out.push("");
		out.push("template<typename T, typename F>");
		out.push("auto __hxhx_null_coalesce(const T& value, F fallback) {");
		out.push("  return value;");
		out.push("}");
		out.push("");
		out.push("template<typename T, typename F>");
		out.push("auto __hxhx_null_coalesce(T* value, F fallback) {");
		out.push("  return value != nullptr ? value : fallback();");
		out.push("}");
		out.push("");
		out.push("template<typename F>");
		out.push("auto __hxhx_null_coalesce(std::nullptr_t, F fallback) {");
		out.push("  return fallback();");
		out.push("}");
		out.push("");
		out.push("static std::string __hxhx_read_file(const std::string& path) {");
		out.push("  std::ifstream input(path);");
		out.push("  if (!input) throw std::runtime_error(std::string(\"Unable to read file: \") + path);");
		out.push("  std::ostringstream buffer;");
		out.push("  buffer << input.rdbuf();");
		out.push("  return buffer.str();");
		out.push("}");
		out.push("");
		out.push("static int __hxhx_json_min_field_from_file(const std::string& path) {");
		out.push("  std::string content = __hxhx_read_file(path);");
		out.push("  std::size_t key = content.find(\"\\\"min\\\"\");");
		out.push("  if (key == std::string::npos) throw std::runtime_error(\"JSON field min not found\");");
		out.push("  std::size_t colon = content.find(':', key);");
		out.push("  if (colon == std::string::npos) throw std::runtime_error(\"JSON field min has no value\");");
		out.push("  std::size_t i = colon + 1;");
		out.push("  while (i < content.size() && std::isspace(static_cast<unsigned char>(content[i]))) ++i;");
		out.push("  bool negative = i < content.size() && content[i] == '-';");
		out.push("  if (negative) ++i;");
		out.push("  bool any = false;");
		out.push("  int value = 0;");
		out.push("  while (i < content.size() && std::isdigit(static_cast<unsigned char>(content[i]))) {");
		out.push("    any = true;");
		out.push("    value = value * 10 + (content[i] - '0');");
		out.push("    ++i;");
		out.push("  }");
		out.push("  if (!any) throw std::runtime_error(\"JSON field min is not an integer\");");
		out.push("  return negative ? -value : value;");
		out.push("}");
		out.push("");
		traceCppPhase("render_before_collect_class_lookup");
		final classLookup = collectClassLookup(program);
		traceCppPhase("render_after_collect_class_lookup");
		traceCppPhase("render_before_forward_declarations");
		final forwardDeclarations = renderForwardDeclarations(program, main.cls, classLookup);
		traceCppPhase("render_after_forward_declarations count=" + forwardDeclarations.length);
		for (decl in forwardDeclarations) {
			for (line in decl)
				out.push(line);
			out.push("");
		}
		traceCppPhase("render_before_pre_anon_support_classes");
		final preAnonSupportClasses = renderPreAnonSupportClasses(program, main.cls, classLookup);
		traceCppPhase("render_after_pre_anon_support_classes count=" + preAnonSupportClasses.length);
		for (decl in preAnonSupportClasses) {
			for (line in decl)
				out.push(line);
			out.push("");
		}
		traceCppPhase("render_before_collect_reachable_helper_classes");
		final reachableHelperClasses = collectReachableHelperClasses(program, main.cls, classLookup);
		traceCppPhase("render_after_collect_reachable_helper_classes count=" + reachableHelperClasses.length);
		traceCppPhase("render_before_anon_structs");
		traceCppPhase("render_before_collect_anon_structs");
		final collectedAnonStructs = collectAnonStructs(program, classLookup, [main.cls].concat(reachableHelperClasses));
		traceCppPhase("render_after_collect_anon_structs count=" + collectedAnonStructs.length);
		traceCppPhase("render_before_render_anon_structs");
		final anonStructs = renderAnonStructs(collectedAnonStructs);
		traceCppPhase("render_after_anon_structs count=" + anonStructs.length);
		if (anonStructs.length > 0) {
			out.push("struct __hxhx_anon;");
			out.push("");
		}
		for (decl in anonStructs) {
			for (line in decl)
				out.push(line);
			out.push("");
		}
		traceCppPhase("render_before_helper_classes");
		final helperClasses = renderHelperClasses(program, main.cls, classLookup, reachableHelperClasses);
		traceCppPhase("render_after_helper_classes count=" + helperClasses.length);
		for (decl in helperClasses) {
			for (line in decl)
				out.push(line);
			out.push("");
		}
		traceCppPhase("render_before_main_static_functions");
		final mainStaticFunctions = renderMainStaticFunctions(main.cls, classLookup);
		traceCppPhase("render_after_main_static_functions count=" + mainStaticFunctions.length);
		for (decl in mainStaticFunctions) {
			for (line in decl)
				out.push(line);
			out.push("");
		}
		out.push("int main(int argc, char** argv) {");
		out.push("  (void)argc;");
		out.push("  (void)argv;");
		traceCppPhase("render_before_main_body");
		final mainScope = renderScope(main.cls, classLookup, "int");
		prepareFunctionScope(mainScope, main.fn);
		for (line in renderStmts(HxFunctionDecl.getBody(main.fn), "  ", mainScope))
			out.push(line);
		traceCppPhase("render_after_main_body");
		out.push("  return 0;");
		out.push("}");
		traceCppPhase("render_done");
		return out.join("\n") + "\n";
	}

	/**
		Collects anonymous-object aggregate shapes before C++ source emission.

		Why
		- C++ needs a concrete type before code can declare `auto info = ...` and
		  later read `info.field`.
		- A dynamic anonymous-object runtime would be too broad for this Full1
		  burn-down seam, so the MVP emits one small aggregate struct per field
		  signature.

		What/How
		- Walks the parsed program for `EAnon` literals, including nested values.
		- Emits nested anonymous structs before their parents so field types are
		  declared in dependency order.
		- Infers only the tiny type subset the Cpp MVP already knows how to print;
		  unsupported dynamic behavior should remain a later explicit seam.
	**/
	static function collectAnonStructs(program:GenIrProgram, classLookup:CppClassLookup, ?classesToScan:Array<HxClassDecl>):Array<CppAnonStruct> {
		final out = new Array<CppAnonStruct>();
		final seen = new haxe.ds.StringMap<Bool>();
		var typeHintTraceCount = 0;
		var typeHintTraceSuppressed = false;
		traceCppPhase("anon_collect_enter typed_modules="
			+ program.getTypedModules().length
			+ " scan_classes="
			+ (classesToScan == null ? "all" : Std.string(classesToScan.length)));
		function traceAnonTypeHint(hint:String):Void {
			if (!traceCppDeepEnabled())
				return;
			if (typeHintTraceCount < 1000) {
				typeHintTraceCount++;
				traceCppDeepPhase("anon_collect_type_hint hint=" + traceCppSnippet(hint));
			} else if (!typeHintTraceSuppressed) {
				typeHintTraceSuppressed = true;
				traceCppDeepPhase("anon_collect_type_hint_suppressed limit=1000");
			}
		}
		function addStruct(struct:CppAnonStruct):Void {
			if (struct != null && !seen.exists(struct.name)) {
				seen.set(struct.name, true);
				out.push(struct);
			}
		}
		function addTypeHint(typeHint:String, ?scope:CppRenderScope, allowMarkedTypedefAnon:Bool = false):Void {
			final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
			if (hint.length == 0)
				return;
			if (hint.indexOf("<") >= 0) {
				final genericArgs = genericTypeHintArgs(hint);
				if (genericArgs.length > 0) {
					for (arg in genericArgs)
						addTypeHint(arg, scope, allowMarkedTypedefAnon);
					return;
				}
			}
			if (hint.indexOf("{") < 0) {
				if (allowMarkedTypedefAnon)
					addStruct(structuralTypedefAnonStructForTypeHint(hint, scope));
				return;
			}
			traceAnonTypeHint(hint);
			if (isArrayLikeTypeHint(hint) || isIterableTypeHint(hint) || CppTypeModel.isIteratorTypeHint(hint)) {
				addTypeHint(genericTypeHintArg(hint), scope);
				return;
			}
			if (isFunctionTypeHint(hint)) {
				for (part in splitTopLevelFunctionType(hint))
					addTypeHint(functionTypePartHint(part), scope);
				return;
			}
			if (isStructuralTypeHint(hint)) {
				final fields = CppTypeModel.structuralTypeHintFields(hint);
				for (field in fields)
					addTypeHint(field.typeHint, scope);
				addStruct(structuralTypeHintStruct(hint, scope, classLookup));
				return;
			}
		}
		function addExpr(expr:HxExpr, ?scope:CppRenderScope):Void {
			switch (expr) {
				case EAnon(fieldNames, fieldValues):
					for (value in fieldValues)
						addExpr(value, scope);
					addStruct(anonStruct(fieldNames, fieldValues, scope));
				case ECall(EField(receiver, "divMod"), _) if (isInt64StaticReceiver(receiver)):
					addStruct(int64DivModStruct());
				case EField(receiver, _):
					addExpr(receiver, scope);
				case ECall(callee, args):
					addExpr(callee, scope);
					for (arg in args)
						addExpr(arg, scope);
				case EArrayDecl(values):
					for (value in values)
						addExpr(value, scope);
				case EArrayAccess(array, index):
					addExpr(array, scope);
					addExpr(index, scope);
				case EBinop(_, left, right):
					addExpr(left, scope);
					addExpr(right, scope);
				case EUnop(_, inner):
					addExpr(inner, scope);
				case ETernary(cond, thenExpr, elseExpr):
					addExpr(cond, scope);
					addExpr(thenExpr, scope);
					addExpr(elseExpr, scope);
				case ENew(typePath, args):
					addTypeHint(typePath, scope, true);
					for (arg in args)
						addExpr(arg, scope);
				case ECast(inner, _) | EUntyped(inner):
					addExpr(inner, scope);
				case ESwitch(scrutinee, _, exprs):
					addExpr(scrutinee, scope);
					for (expr in exprs)
						addExpr(expr, scope);
				case EArrayComprehension(_, iterable, guardExpr, yieldExpr):
					addExpr(iterable, scope);
					if (guardExpr != null)
						addExpr(guardExpr, scope);
					addExpr(yieldExpr, scope);
				case ELambda(_, body):
					addExpr(body, scope);
				case EMacroExpr(inner, _):
					addExpr(inner, scope);
				case _:
			}
		}
		function anonCollectLocalTypeHint(typeHint:String, init:Null<HxExpr>, ?scope:CppRenderScope):String {
			if (scope == null)
				return "";
			final explicit = StringTools.trim(typeHint == null ? "" : typeHint);
			if (explicit.length > 0)
				return cppLocalTypeHint(explicit, init, scope);
			if (init == null)
				return "";
			return switch (init) {
				case EAnon(fieldNames, fieldValues):
					anonStruct(fieldNames, fieldValues, scope).name;
				case ECall(EField(receiver, "divMod"), _) if (isInt64StaticReceiver(receiver)):
					int64DivModStruct().name;
				case ENew(typePath, _):
					final structural = structuralTypedefAnonStructTypeNameForTypeHint(typePath, scope);
					structural == null ? cppTypeHint(typePath, scope) : structural;
				case _:
					"";
			};
		}
		function shouldWalkFunctionBody(packagePath:String, cls:HxClassDecl, fn:HxFunctionDecl):Bool {
			if (hasFunctionMetadata(fn, "macro"))
				return false;
			if (isCompileTimeMacroApiClass(packagePath, cls))
				return false;
			return true;
		}
		function typeHintMayContributeAnonStruct(typeHint:String):Bool {
			final hint = StringTools.trim(typeHint == null ? "" : typeHint);
			return hint.indexOf("{") >= 0;
		}
		var exprMayContributeAnonStruct:HxExpr->Null<CppRenderScope>->Bool = null;
		var exprsMayContributeAnonStruct:Array<HxExpr>->Null<CppRenderScope>->Bool = null;
		var stmtMayContributeAnonStruct:HxStmt->Null<CppRenderScope>->Bool = null;
		var stmtsMayContributeAnonStruct:Array<HxStmt>->Null<CppRenderScope>->Bool = null;
		exprMayContributeAnonStruct = function(expr:HxExpr, scope:Null<CppRenderScope>):Bool {
			return switch (expr) {
				case EAnon(_, _):
					true;
				case ECall(EField(receiver, "divMod"), _) if (isInt64StaticReceiver(receiver)):
					true;
				case ENew(typePath, args): structuralTypedefAnonStructTypeNameForTypeHint(typePath,
						scope) != null || typeHintMayContributeAnonStruct(typePath) || exprsMayContributeAnonStruct(args, scope);
				case EField(receiver, _):
					exprMayContributeAnonStruct(receiver, scope);
				case ECall(callee, args): exprMayContributeAnonStruct(callee, scope) || exprsMayContributeAnonStruct(args, scope);
				case EArrayDecl(values):
					exprsMayContributeAnonStruct(values, scope);
				case EArrayAccess(array, index): exprMayContributeAnonStruct(array, scope) || exprMayContributeAnonStruct(index, scope);
				case EBinop(_, left, right): exprMayContributeAnonStruct(left, scope) || exprMayContributeAnonStruct(right, scope);
				case EUnop(_, inner):
					exprMayContributeAnonStruct(inner, scope);
				case ETernary(cond, thenExpr, elseExpr): exprMayContributeAnonStruct(cond,
						scope) || exprMayContributeAnonStruct(thenExpr, scope) || exprMayContributeAnonStruct(elseExpr, scope);
				case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
					exprMayContributeAnonStruct(inner, scope);
				case ESwitch(scrutinee, _, exprs): exprMayContributeAnonStruct(scrutinee, scope) || exprsMayContributeAnonStruct(exprs, scope);
				case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprMayContributeAnonStruct(iterable,
						scope) || (guardExpr != null
						&& exprMayContributeAnonStruct(guardExpr, scope)) || exprMayContributeAnonStruct(yieldExpr, scope);
				case ELambda(_, body):
					exprMayContributeAnonStruct(body, scope);
				case _:
					false;
			}
		}
		exprsMayContributeAnonStruct = function(exprs:Array<HxExpr>, scope:Null<CppRenderScope>):Bool {
			for (expr in exprs)
				if (exprMayContributeAnonStruct(expr, scope))
					return true;
			return false;
		}
		stmtMayContributeAnonStruct = function(stmt:HxStmt, scope:Null<CppRenderScope>):Bool {
			return switch (stmt) {
				case SBlock(stmts, _):
					stmtsMayContributeAnonStruct(stmts, scope);
				case SVar(_, typeHint, init, _): typeHintMayContributeAnonStruct(typeHint) || (init != null
						&& exprMayContributeAnonStruct(init, scope));
				case SIf(cond, thenBranch, elseBranch, _): exprMayContributeAnonStruct(cond,
						scope) || stmtMayContributeAnonStruct(thenBranch, scope) || (elseBranch != null
						&& stmtMayContributeAnonStruct(elseBranch, scope));
				case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
					exprMayContributeAnonStruct(expr, scope);
				case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprMayContributeAnonStruct(iterable,
						scope) || stmtMayContributeAnonStruct(body, scope);
				case SWhile(cond, body, _): exprMayContributeAnonStruct(cond, scope) || stmtMayContributeAnonStruct(body, scope);
				case SDoWhile(body, cond, _): stmtMayContributeAnonStruct(body, scope) || exprMayContributeAnonStruct(cond, scope);
				case SSwitch(scrutinee, _, bodies, _): exprMayContributeAnonStruct(scrutinee, scope) || stmtsMayContributeAnonStruct(bodies, scope);
				case STry(tryBody, catches, _):
					if (stmtMayContributeAnonStruct(tryBody, scope)) true; else {
						var found = false;
						for (c in catches)
							if (typeHintMayContributeAnonStruct(c.typeHint) || stmtMayContributeAnonStruct(c.body, scope))
								found = true;
						found;
					}
				case SReturnVoid(_) | SBreak(_) | SContinue(_):
					false;
			}
		}
		stmtsMayContributeAnonStruct = function(stmts:Array<HxStmt>, scope:Null<CppRenderScope>):Bool {
			for (stmt in stmts)
				if (stmtMayContributeAnonStruct(stmt, scope))
					return true;
			return false;
		}
		function addStmt(stmt:HxStmt, ?scope:CppRenderScope):Void {
			switch (stmt) {
				case SBlock(stmts, _):
					for (s in stmts)
						addStmt(s, scope);
				case SVar(name, typeHint, init, _):
					addTypeHint(typeHint, scope);
					if (init != null)
						addExpr(init, scope);
					final localType = anonCollectLocalTypeHint(typeHint, init, scope);
					if (localType.length > 0)
						scope.localTypes.set(sanitizeIdentifier(name), localType);
				case SIf(cond, thenBranch, elseBranch, _):
					addExpr(cond, scope);
					addStmt(thenBranch, scope);
					if (elseBranch != null)
						addStmt(elseBranch, scope);
				case SExpr(expr, _) | SReturn(expr, _):
					addExpr(expr, scope);
				case SForIn(_, iterable, body, _):
					addExpr(iterable, scope);
					addStmt(body, scope);
				case SForKeyValue(_, _, iterable, body, _):
					addExpr(iterable, scope);
					addStmt(body, scope);
				case SWhile(cond, body, _):
					addExpr(cond, scope);
					addStmt(body, scope);
				case SDoWhile(body, cond, _):
					addStmt(body, scope);
					addExpr(cond, scope);
				case SSwitch(scrutinee, _, bodies, _):
					addExpr(scrutinee, scope);
					for (body in bodies)
						addStmt(body, scope);
				case STry(tryBody, catches, _):
					addStmt(tryBody, scope);
					for (c in catches)
						addStmt(c.body, scope);
				case SThrow(expr, _):
					addExpr(expr, scope);
				case SReturnVoid(_) | SBreak(_) | SContinue(_):
			}
		}
		final collectedClasses = new haxe.ds.StringMap<Bool>();
		var collectedClassCount = 0;
		var collectedFunctionCount = 0;
		var walkedFunctionBodyCount = 0;
		var skippedFunctionBodyCount = 0;
		function collectClass(cls:HxClassDecl, packagePath:String):Void {
			final className = renderedClassName(cls, classLookup);
			if (collectedClasses.exists(className))
				return;
			collectedClasses.set(className, true);
			collectedClassCount++;
			if (collectedClassCount % 25 == 0)
				traceCppPhase("anon_collect_progress classes=" + collectedClassCount + " functions=" + collectedFunctionCount + " class=" + className
					+ " structs=" + out.length);
			traceCppDeepPhase("anon_collect_class_begin name=" + className);
			final fieldScope = renderScope(cls, classLookup, "void");
			for (field in HxClassDecl.getFields(cls)) {
				final fieldName = sanitizeIdentifier(HxFieldDecl.getName(field));
				traceCppDeepPhase("anon_collect_field_begin class=" + className + " name=" + fieldName);
				addTypeHint(HxFieldDecl.getTypeHint(field), fieldScope);
				final init = HxFieldDecl.getInit(field);
				if (init != null)
					addExpr(init, fieldScope);
				traceCppDeepPhase("anon_collect_field_end class=" + className + " name=" + fieldName);
			}
			for (fn in HxClassDecl.getFunctions(cls)) {
				final fnName = sanitizeIdentifier(HxFunctionDecl.getName(fn));
				collectedFunctionCount++;
				if (collectedFunctionCount % 250 == 0)
					traceCppPhase("anon_collect_progress classes=" + collectedClassCount + " functions=" + collectedFunctionCount + " class=" + className
						+ " fn=" + fnName + " structs=" + out.length);
				traceCppDeepPhase("anon_collect_fn_begin class=" + className + " name=" + fnName);
				final scope = renderScope(cls, classLookup, "auto");
				prepareAnonCollectFunctionScope(scope, fn);
				addTypeHint(HxFunctionDecl.getReturnTypeHint(fn), scope);
				final knownReturn = knownStdlibMethodReturnCppType(className, HxFunctionDecl.getName(fn), HxFunctionDecl.getReturnTypeHint(fn), scope,
					classLookup);
				if (isCppAnonStructType(knownReturn) && scope.anonStructs.exists(knownReturn))
					addStruct(scope.anonStructs.get(knownReturn));
				for (arg in HxFunctionDecl.getArgs(fn))
					addTypeHint(HxFunctionArg.getTypeHint(arg), scope);
				if (shouldWalkFunctionBody(packagePath, cls, fn)) {
					if (stmtsMayContributeAnonStruct(HxFunctionDecl.getBody(fn), scope)) {
						walkedFunctionBodyCount++;
						for (stmt in HxFunctionDecl.getBody(fn))
							addStmt(stmt, scope);
					} else {
						skippedFunctionBodyCount++;
					}
				}
				traceCppDeepPhase("anon_collect_fn_end class=" + className + " name=" + fnName);
			}
			traceCppDeepPhase("anon_collect_class_end name=" + className);
		}
		if (classesToScan != null) {
			for (cls in classesToScan)
				collectClass(cls, packagePathForRenderedClass(cls, classLookup));
		} else {
			for (typed in program.getTypedModules()) {
				final decl = typed.getParsed().getDecl();
				final packagePath = HxModuleDecl.getPackagePath(decl);
				for (cls in HxModuleDecl.getClasses(decl))
					collectClass(cls, packagePath);
			}
		}
		traceCppPhase("anon_collect_done count="
			+ out.length
			+ " walked_bodies="
			+ walkedFunctionBodyCount
			+ " skipped_bodies="
			+ skippedFunctionBodyCount);
		return out;
	}

	/**
		Prepare only the local scope facts required while discovering anonymous
		struct shapes.

		Full `prepareFunctionScope` performs render-time type-flow inference over
		the entire function body. `collectAnonStructs` already walks each body for
		anonymous literals and type hints, so running the full render prep here
		duplicates expensive expression traversal. The collection scope also uses
		a neutral return type so it does not trigger `cppFunctionReturnType`
		inference before doing that walk.
	**/
	static function prepareAnonCollectFunctionScope(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		applyFunctionTypeParams(scope, fn);
		registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn));
	}

	static function renderMainStaticFunctions(cls:HxClassDecl, classLookup:CppClassLookup):Array<Array<String>> {
		final out = new Array<Array<String>>();
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (!HxFunctionDecl.getIsStatic(fn) || HxFunctionDecl.getName(fn) == "main")
				continue;
			out.push(renderStaticFunction(fn, cls, classLookup));
		}
		return out;
	}

	static function renderStaticFunction(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionScope(scope, fn);
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		if (methodTypeParams.length > 0)
			out.push(genericTemplatePrefix(methodTypeParams));
		out.push("static " + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "(" + renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {");
		for (line in renderFunctionBody(HxFunctionDecl.getBody(fn), "  ", scope))
			out.push(line);
		out.push("}");
		return out;
	}

	static function renderAnonStructs(structs:Array<CppAnonStruct>):Array<Array<String>> {
		final out = new Array<Array<String>>();
		for (struct in structs) {
			final lines = ["struct " + struct.name + " {"];
			for (i in 0...struct.fieldNames.length)
				lines.push("  " + struct.fieldTypes[i] + " " + sanitizeIdentifier(struct.fieldNames[i]) + ";");
			if (struct.fieldNames.length > 0) {
				lines.push("  " + struct.name + "() = default;");
				final ctorArgs = new Array<String>();
				final ctorInits = new Array<String>();
				final fieldChecks = new Array<String>();
				final otherInits = new Array<String>();
				for (i in 0...struct.fieldNames.length) {
					final fieldName = sanitizeIdentifier(struct.fieldNames[i]);
					final argName = "__hxhx_" + fieldName;
					ctorArgs.push(struct.fieldTypes[i] + " " + argName);
					ctorInits.push(fieldName + "(" + argName + ")");
					fieldChecks.push("decltype(std::declval<const Other&>()." + fieldName + ")");
					otherInits.push(fieldName + "(other." + fieldName + ")");
				}
				lines.push("  " + struct.name + "(" + ctorArgs.join(", ") + ") : " + ctorInits.join(", ") + " {}");
				if (struct.name != "__hxhx_anon")
					lines.push("  "
						+ struct.name
						+ "(const __hxhx_anon&) : "
						+ [for (field in struct.fieldNames) sanitizeIdentifier(field) + "()"].join(", ") + " {}");
				lines.push("  template<typename Other, typename = std::enable_if_t<!std::is_same_v<std::decay_t<Other>, "
					+ struct.name
					+ ">>, typename = std::void_t<"
					+ fieldChecks.join(", ")
					+ ">>");
				lines.push("  " + struct.name + "(const Other& other) : " + otherInits.join(", ") + " {}");
			}
			lines.push("};");
			out.push(lines);
		}
		return out;
	}

	static function anonStruct(fieldNames:Array<String>, fieldValues:Array<HxExpr>, ?scope:CppRenderScope):CppAnonStruct {
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		final names = new Array<String>();
		final types = new Array<String>();
		final assertStatusShape = isAssertStatusFieldSet(fieldNames);
		for (i in 0...count) {
			names.push(fieldNames[i]);
			types.push(cppAnonFieldType(fieldNames[i], fieldValues[i], assertStatusShape, scope));
		}
		final struct = {name: anonStructName(names, types), fieldNames: names, fieldTypes: types};
		if (scope != null)
			scope.anonStructs.set(struct.name, struct);
		return struct;
	}

	static function anonStructName(fieldNames:Array<String>, fieldTypes:Array<String>):String {
		final parts = ["__hxhx_anon"];
		for (i in 0...fieldNames.length)
			parts.push(sanitizeIdentifier(fieldNames[i]) + "_" + sanitizeTypePath(fieldTypes[i]));
		return parts.join("_");
	}

	static function structuralTypeHintStruct(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<CppAnonStruct> {
		final fields = CppTypeModel.structuralTypeHintFields(typeHint);
		if (fields.length == 0)
			return null;
		final names = new Array<String>();
		final types = new Array<String>();
		for (field in fields) {
			names.push(field.name);
			final fieldType = structuralFieldCppType(field.typeHint, scope, classLookup);
			types.push(isScopeTypeParam(fieldType, scope) || isBareCppTypeParamName(fieldType) ? "std::string" : fieldType);
		}
		final struct = {name: anonStructName(names, types), fieldNames: names, fieldTypes: types};
		if (scope != null)
			scope.anonStructs.set(struct.name, struct);
		return struct;
	}

	static function isBareCppTypeParamName(typeName:String):Bool {
		final clean = sanitizeTypePath(StringTools.trim(typeName == null ? "" : typeName));
		if (clean.length != 1)
			return false;
		final c = clean.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}

	static function cppAnonFieldType(fieldName:String, expr:HxExpr, assertStatusShape:Bool, ?scope:CppRenderScope):String {
		final cleanField = sanitizeIdentifier(fieldName == null ? "" : fieldName);
		if (assertStatusShape && isAssertStatusStringField(cleanField))
			return "std::string";
		if (assertStatusShape && cleanField == "recursive")
			return "bool";
		if (cleanField == "__hx_params")
			return "std::vector<std::string>";
		final scoped = exprCppType(expr, scope);
		final optionalInner = cppOptionalInnerType(scoped);
		if (optionalInner.length > 0)
			return isScopeTypeParam(optionalInner, scope) || isBareCppTypeParamName(optionalInner) ? "std::string" : optionalInner;
		if (isScopeTypeParam(scoped, scope) || isBareCppTypeParamName(scoped))
			return "std::string";
		if (scoped.length > 0)
			return scoped;
		final inferred = inferExprCppType(expr, scope);
		if (isBareCppTypeParamName(inferred))
			return "std::string";
		if (inferred.length > 0)
			return inferred;
		return switch (expr) {
			case EString(_) | EEnumValue(_) | EMacroExpr(_, _) | EMacroType(_):
				"std::string";
			case EIdent(_):
				"std::string";
			case EArrayAccess(_, _):
				"int";
			case EFloat(_):
				"double";
			case EBool(_):
				"bool";
			case ETernary(_, thenExpr, elseExpr) if (isCppBoolExpr(thenExpr, scope) && isCppBoolExpr(elseExpr, scope)):
				"bool";
			case EUnop("post++", _) | EUnop("post--", _):
				"int";
			case EArrayDecl(elements):
				"std::vector<" + arrayElementType(elements, scope) + ">";
			case EAnon(fieldNames, fieldValues):
				final struct = anonStruct(fieldNames, fieldValues, scope);
				struct.name;
			case ECall(EField(receiver, "divMod"), _) if (isInt64StaticReceiver(receiver)):
				int64DivModStruct().name;
			case _:
				"int";
		};
	}

	static function isScopeTypeParam(typeName:String, ?scope:CppRenderScope):Bool {
		final clean = sanitizeTypePath(StringTools.trim(typeName == null ? "" : typeName));
		if (clean.length == 0 || scope == null || scope.typeParams == null)
			return false;
		for (param in scope.typeParams)
			if (clean == sanitizeTypePath(StringTools.trim(param)))
				return true;
		return false;
	}

	static function scopedGenericTypeParamName(typeHint:String, ?scope:CppRenderScope):String {
		final param = genericTypeParamName(typeHint);
		return param.length > 0 && isScopeTypeParam(param, scope) ? param : "";
	}

	static function isAssertStatusStringField(fieldName:String):Bool {
		return fieldName == "expectedValue" || fieldName == "actualValue" || fieldName == "error" || fieldName == "path";
	}

	static function isAssertStatusFieldSet(fieldNames:Array<String>):Bool {
		final seen = new haxe.ds.StringMap<Bool>();
		for (fieldName in fieldNames)
			seen.set(sanitizeIdentifier(fieldName == null ? "" : fieldName), true);
		return seen.exists("expectedValue") && seen.exists("actualValue") && seen.exists("error") && seen.exists("path") && seen.exists("recursive");
	}

	static function renderForwardDeclarations(program:GenIrProgram, mainClass:HxClassDecl, classLookup:CppClassLookup):Array<Array<String>> {
		final out = new Array<Array<String>>();
		final emitted = new haxe.ds.StringMap<Bool>();
		final mainName = HxClassDecl.getName(mainClass);
		final mainRenderedName = renderedClassName(mainClass, classLookup);
		function emitType(rawName:String, ?typeParams:Array<String>):Void {
			final name = sanitizeTypePath(rawName);
			if (name == sanitizeTypePath(mainName) || name == mainRenderedName || emitted.exists(name))
				return;
			if (name == "IMap")
				emitType("KeyValueIterator");
			emitted.set(name, true);
			final missingInterface = shouldRenderMissingDeclarationBody(name, classLookup) ? renderMissingInterfaceDeclaration(name) : null;
			if (missingInterface != null)
				out.push(missingInterface);
			else if (typeParams != null && typeParams.length > 0)
				out.push([genericTemplatePrefix(typeParams), "struct " + name + ";"]);
			else {
				final missingParams = missingGenericForwardParams(name);
				if (missingParams.length > 0)
					out.push([genericTemplatePrefix(missingParams), "struct " + name + ";"]);
				else
					out.push(["struct " + name + ";"]);
			}
		}
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final rawName = HxClassDecl.getName(cls);
				final renderedName = renderedClassName(cls, classLookup);
				if (rawName == mainName || renderedName == mainRenderedName || emitted.exists(renderedName) || isCppCoreExternClass(rawName))
					continue;
				emitType(renderedName, forwardDeclarationTypeParams(cls));
			}
		}
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final typeParams = genericClassTypeParams(cls);
				function addMissing(name:String):Void {
					final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
					for (param in typeParams)
						if (clean == sanitizeTypePath(param))
							return;
					if (shouldForwardDeclareMissingType(clean, classLookup))
						emitType(clean);
				}
				for (iface in implementedInterfaceNames(cls, classLookup))
					addMissing(iface);
				for (field in HxClassDecl.getFields(cls))
					addTypeHintDependencies(HxFieldDecl.getTypeHint(field), addMissing);
				for (fn in HxClassDecl.getFunctions(cls)) {
					final fnScope = renderScope(cls, classLookup, "void");
					applyFunctionTypeParams(fnScope, fn);
					final fnTypeParams = typeParams.concat(genericFunctionTypeParams(fn));
					function addFnMissing(name:String):Void {
						final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
						for (param in fnTypeParams)
							if (clean == sanitizeTypePath(param))
								return;
						if (shouldForwardDeclareMissingType(clean, classLookup))
							emitType(clean);
					}
					addTypeHintDependencies(HxFunctionDecl.getReturnTypeHint(fn), addFnMissing, fnScope);
					for (arg in HxFunctionDecl.getArgs(fn))
						addTypeHintDependencies(HxFunctionArg.getTypeHint(arg), addFnMissing, fnScope);
					addStmtClassDependencies(HxFunctionDecl.getBody(fn), addFnMissing, fnScope);
				}
			}
		}
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				if (shouldEmitGenericClassFactory(cls, mainName))
					out.push(renderGenericClassFactoryDeclaration(cls, classLookup));
			}
		}
		return out;
	}

	static function shouldEmitGenericClassFactory(cls:HxClassDecl, mainName:String):Bool {
		final rawName = HxClassDecl.getName(cls);
		if (rawName == mainName || HxClassDecl.getIsInterface(cls) || isCppCoreExternClass(rawName) || isBytesDataTypeName(rawName))
			return false;
		if (isPosInfosSupportClass(cls) || isStdVectorHelperClass(cls) || isArrayBackedAbstractClass(cls) || isPrimitiveBackedAbstractClass(cls)
			|| isStdArrayHelperClass(cls))
			return false;
		return genericClassTemplateParams(cls).length > 0;
	}

	static function forwardDeclarationTypeParams(cls:HxClassDecl):Array<String> {
		if (isStdArrayHelperClass(cls) || isStdVectorHelperClass(cls) || isArrayBackedAbstractClass(cls) || isPrimitiveBackedAbstractClass(cls))
			return [];
		return genericClassTemplateParams(cls);
	}

	/**
		Emits small target-owned declarations for stdlib interfaces that can be
		referenced by upstream-derived helper code before their defining module is
		present in the current Cpp MVP program.

		This is declaration surface only: concrete map behavior still belongs in
		real stdlib/runtime support, not in generated fake backend classes.
	**/
	static function renderMissingInterfaceDeclaration(name:String):Null<Array<String>> {
		return CppRuntimeSupport.missingDeclarationLines(sanitizeTypePath(typeBaseName(name == null ? "" : name)));
	}

	static function shouldRenderMissingDeclarationBody(name:String, classLookup:CppClassLookup):Bool {
		final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
		if ((clean == "StringMap" || clean == "Date") && classLookup.names.exists(clean))
			return false;
		return true;
	}

	static function missingGenericForwardParams(name:String):Array<String> {
		return switch (sanitizeTypePath(typeBaseName(name == null ? "" : name))) {
			case "IMap" | "TreeNode" | "BalancedTree" | "EnumValueMap":
				["K", "V"];
			case "StringMap":
				["V"];
			case "Tree":
				["T"];
			case _:
				[];
		};
	}

	static function shouldForwardDeclareMissingType(name:String, classLookup:CppClassLookup):Bool {
		final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
		if (clean.length == 0 || clean == "_" || classLookup.names.exists(clean) || isCppCoreExternClass(clean))
			return false;
		if (primitiveTypeHintCppType(clean) != null || knownPrimitiveBackedAbstractCppType(clean) != null)
			return false;
		return switch (clean) {
			case "Any" | "Array" | "Bool" | "Dynamic" | "Float" | "Function" | "Int" | "Iterable" | "Iterator" | "Null" | "String" | "Void":
				false;
			case _:
				true;
		}
	}

	static function collectClassLookup(program:GenIrProgram):CppClassLookup {
		final names = new haxe.ds.StringMap<Bool>();
		final byName = new haxe.ds.StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final shortNameCounts = new haxe.ds.StringMap<Int>();
		final packageByRenderedName = new haxe.ds.StringMap<String>();
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final shortName = sanitizeTypePath(HxClassDecl.getName(cls));
				shortNameCounts.set(shortName, shortNameCounts.exists(shortName) ? shortNameCounts.get(shortName) + 1 : 1);
			}
		}
		final renderedNames = new Array<{cls:HxClassDecl, name:String}>();
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			final moduleName = expectedModuleNameFromFile(typed.getParsed().getFilePath());
			final packagePath = HxModuleDecl.getPackagePath(decl);
			for (cls in HxModuleDecl.getClasses(decl)) {
				all.push(cls);
				final rendered = renderedClassNameForModule(HxClassDecl.getName(cls), moduleName, shortNameCounts);
				renderedNames.push({cls: cls, name: rendered});
				packageByRenderedName.set(rendered, packagePath == null ? "" : packagePath);
				addClassLookupAliases(HxClassDecl.getName(cls), cls, names, byName);
				if (rendered != sanitizeTypePath(HxClassDecl.getName(cls)))
					addClassLookupAliases(rendered, cls, names, byName);
			}
		}
		return {
			names: names,
			byName: byName,
			all: all,
			renderedNames: renderedNames,
			packageByRenderedName: packageByRenderedName
		};
	}

	static function addClassLookupAliases(rawName:String, cls:HxClassDecl, names:haxe.ds.StringMap<Bool>, byName:haxe.ds.StringMap<HxClassDecl>):Void {
		final fullName = sanitizeTypePath(rawName);
		names.set(fullName, true);
		byName.set(fullName, cls);
		final baseName = sanitizeTypePath(typeBaseName(rawName == null ? "" : rawName));
		if (baseName.length > 0 && baseName != fullName) {
			names.set(baseName, true);
			if (!byName.exists(baseName))
				byName.set(baseName, cls);
		}
	}

	static function expectedModuleNameFromFile(filePath:Null<String>):String {
		if (filePath == null || filePath.length == 0)
			return "";
		final name = Path.withoutExtension(Path.withoutDirectory(filePath));
		return name == null ? "" : name;
	}

	static function renderedClassNameForModule(rawName:String, moduleName:String, shortNameCounts:haxe.ds.StringMap<Int>):String {
		final baseName = sanitizeTypePath(rawName);
		final count = shortNameCounts.exists(baseName) ? shortNameCounts.get(baseName) : 0;
		final module = sanitizeTypePath(moduleName == null ? "" : moduleName);
		if (count > 1 && module.length > 0 && module != "Unknown" && module != baseName)
			return sanitizeTypePath(module + "." + baseName);
		return baseName;
	}

	static function renderedClassName(cls:HxClassDecl, ?classLookup:CppClassLookup):String {
		if (cls == null)
			return "";
		if (classLookup != null && classLookup.renderedNames != null)
			for (entry in classLookup.renderedNames)
				if (entry.cls == cls)
					return entry.name;
		return sanitizeTypePath(HxClassDecl.getName(cls));
	}

	static function packagePathForRenderedClass(cls:HxClassDecl, ?classLookup:CppClassLookup):String {
		if (cls == null || classLookup == null || classLookup.packageByRenderedName == null)
			return "";
		final packagePath = classLookup.packageByRenderedName.get(renderedClassName(cls, classLookup));
		return packagePath == null ? "" : packagePath;
	}

	static function isCompileTimeMacroApiClass(packagePath:String, cls:HxClassDecl):Bool {
		return packagePath == "haxe.macro";
	}

	static function lookupForScope(?scope:CppRenderScope, ?classLookup:CppClassLookup):CppClassLookup {
		if (classLookup != null)
			return classLookup;
		if (scope != null && scope.classLookup != null)
			return scope.classLookup;
		return scope == null ? null : {names: scope.classNames, byName: scope.classByName, all: scope.allClasses};
	}

	static function renderHelperClasses(program:GenIrProgram, mainClass:HxClassDecl, classLookup:CppClassLookup,
			?reachableHelpers:Array<HxClassDecl>):Array<Array<String>> {
		final out = new Array<Array<String>>();
		final helpers = reachableHelpers == null ? collectReachableHelperClasses(program, mainClass, classLookup) : reachableHelpers;
		traceCppPhase("render_helper_classes_before_order count=" + helpers.length);
		final orderedHelpers = orderHelperClasses(helpers, classLookup);
		traceCppPhase("render_helper_classes_after_order count=" + orderedHelpers.length);
		traceHelperRenderKindCounts("render_helper_classes_classification", orderedHelpers, classLookup);
		traceHelperRenderKindDetails("render_helper_classes_classification", orderedHelpers, classLookup);
		for (cls in orderedHelpers) {
			final helperName = renderedClassName(cls, classLookup);
			final timingEnabled = traceCppTimingsEnabled();
			final startTime = timingEnabled ? Sys.time() : 0.0;
			traceCppPhase("render_helper_class_begin name=" + helperName);
			final rendered = renderHelperClass(cls, classLookup);
			out.push(rendered);
			traceCppPhase("render_helper_class_end name=" + helperName);
			if (timingEnabled) {
				final elapsed = Sys.time() - startTime;
				traceCppTimingPhase("render_helper_class_timing name=" + helperName + " seconds=" + Std.string(elapsed) + " lines=" + rendered.length);
			}
		}
		return out;
	}

	static function traceHelperRenderKindCounts(label:String, helpers:Array<HxClassDecl>, classLookup:CppClassLookup):Void {
		if (!traceCppEnabled())
			return;
		final counts = helperRenderKindCounts(helpers, classLookup);
		traceCppPhase(label + " total=" + helpers.length + " full_body=" + counts.fullBody + " declaration_only=" + counts.declarationOnly
			+ " runtime_module=" + counts.runtimeModule + " unsupported_diagnostic=" + counts.unsupportedDiagnostic);
	}

	static function traceHelperRenderKindDetails(label:String, helpers:Array<HxClassDecl>, classLookup:CppClassLookup):Void {
		if (!traceCppHelperClassificationDetailsEnabled())
			return;
		var index = 0;
		for (cls in helpers) {
			traceCppHelperClassificationDetailPhase(helperRenderKindDetailLine(label, index, cls, classLookup));
			index++;
		}
	}

	static function helperRenderKindCounts(helpers:Array<HxClassDecl>, classLookup:CppClassLookup):CppHelperRenderKindCounts {
		var fullBody = 0;
		var declarationOnly = 0;
		var runtimeModule = 0;
		var unsupportedDiagnostic = 0;
		for (cls in helpers)
			switch (helperClassRenderKind(cls, classLookup)) {
				case FullBody:
					fullBody = fullBody + 1;
				case DeclarationOnly:
					declarationOnly = declarationOnly + 1;
				case RuntimeModule:
					runtimeModule = runtimeModule + 1;
				case UnsupportedDiagnostic:
					unsupportedDiagnostic = unsupportedDiagnostic + 1;
			}
		return {
			fullBody: fullBody,
			declarationOnly: declarationOnly,
			runtimeModule: runtimeModule,
			unsupportedDiagnostic: unsupportedDiagnostic
		};
	}

	static function helperRenderKindDetailLine(label:String, index:Int, cls:HxClassDecl, classLookup:CppClassLookup):String {
		final kind = helperClassRenderKind(cls, classLookup);
		if (cls == null)
			return label + "_detail index=" + index + " kind=" + helperRenderKindLabel(kind) + " name=<null>";
		final renderedName = renderedClassName(cls, classLookup);
		final rawName = HxClassDecl.getName(cls);
		final packagePath = packagePathForRenderedClass(cls, classLookup);
		var line = label + "_detail index=" + index + " kind=" + helperRenderKindLabel(kind) + " name=" + renderedName;
		if (rawName != renderedName)
			line += " raw=" + rawName;
		if (packagePath.length > 0)
			line += " package=" + packagePath;
		return line;
	}

	static function helperRenderKindLabel(kind:CppHelperRenderKind):String {
		return switch (kind) {
			case FullBody:
				"full_body";
			case DeclarationOnly:
				"declaration_only";
			case RuntimeModule:
				"runtime_module";
			case UnsupportedDiagnostic:
				"unsupported_diagnostic";
		};
	}

	static function helperClassRenderKind(cls:HxClassDecl, classLookup:CppClassLookup):CppHelperRenderKind {
		if (cls == null)
			return UnsupportedDiagnostic;
		final rawName = HxClassDecl.getName(cls);
		if (isCppCoreExternClass(rawName) || isBytesDataTypeName(rawName))
			return DeclarationOnly;
		final className = renderedClassName(cls, classLookup);
		if (isNativeStackTraceSupportClass(cls))
			return DeclarationOnly;
		if (HxClassDecl.getFields(cls).length == 0
			&& HxClassDecl.getFunctions(cls).length == 0
			&& renderMissingInterfaceDeclaration(className) != null)
			return DeclarationOnly;
		if (HxClassDecl.getIsInterface(cls))
			return DeclarationOnly;
		if (helperClassUsesTargetRuntimeModule(cls, classLookup, className))
			return RuntimeModule;
		return FullBody;
	}

	static function helperClassUsesTargetRuntimeModule(cls:HxClassDecl, classLookup:CppClassLookup, className:String):Bool {
		return isAnySupportClass(cls)
			|| isGenericMapSupportClass(cls)
			|| isPosInfosSupportClass(cls)
			|| isRestSupportClass(cls)
			|| isStdVectorHelperClass(cls)
			|| isStdVectorHelperName(className)
			|| isTemplateWrapSupportClass(cls)
			|| isHashMapBackedAbstractClass(cls)
			|| isStringMapBackedAbstractClass(cls)
			|| isArrayBackedAbstractClass(cls)
			|| isPrimitiveBackedAbstractClass(cls)
			|| isStdArrayHelperClass(cls)
			|| isCppReportSupportClass(cls)
			|| isUtestAssertSupportClass(cls, classLookup)
			|| isUnitTestBaseSupportClass(cls)
			|| isTemplateSupportClass(cls);
	}

	static function collectReachableHelperClasses(program:GenIrProgram, mainClass:HxClassDecl, classLookup:CppClassLookup):Array<HxClassDecl> {
		final candidates = new Array<HxClassDecl>();
		final candidateByName = new haxe.ds.StringMap<HxClassDecl>();
		final emitted = new haxe.ds.StringMap<Bool>();
		final mainName = HxClassDecl.getName(mainClass);
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final rawName = HxClassDecl.getName(cls);
				final helperName = renderedClassName(cls, classLookup);
				if (cls == mainClass || rawName == mainName || emitted.exists(helperName) || isCppCoreExternClass(rawName))
					continue;
				if (isTemplateWrapSupportClass(cls))
					continue;
				emitted.set(helperName, true);
				candidates.push(cls);
				candidateByName.set(helperName, cls);
			}
		}
		if (!mainClassHasReachabilityRoots(mainClass) && program.getTypedModules().length <= 3) {
			traceCppPhase("render_helper_classes_reachable candidates="
				+ candidates.length
				+ " reachable="
				+ candidates.length
				+ " mode=small_empty_main");
			return candidates;
		}

		final reachable = new haxe.ds.StringMap<Bool>();
		final ordered = new Array<HxClassDecl>();
		var markClass:HxClassDecl->Void = null;
		var markName:String->Void = null;
		markClass = function(cls:HxClassDecl):Void {
			if (cls == null)
				return;
			final helperName = renderedClassName(cls, classLookup);
			if (!candidateByName.exists(helperName) || reachable.exists(helperName))
				return;
			reachable.set(helperName, true);
			ordered.push(cls);
			for (dep in helperClassDependencies(cls, classLookup))
				markName(dep);
		};
		markName = function(name:String):Void {
			final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
			if (clean.length == 0)
				return;
			final direct = candidateByName.get(clean);
			if (direct != null) {
				markClass(direct);
				return;
			}
			final cls = classLookup.byName.get(clean);
			if (cls != null)
				markClass(cls);
		};

		for (typed in program.getTypedModules()) {
			final classes = HxModuleDecl.getClasses(typed.getParsed().getDecl());
			var containsMain = false;
			for (cls in classes)
				if (cls == mainClass)
					containsMain = true;
			if (containsMain)
				for (cls in classes)
					markClass(cls);
		}
		for (dep in helperClassDependencies(mainClass, classLookup))
			markName(dep);
		traceCppPhase("render_helper_classes_reachable candidates=" + candidates.length + " reachable=" + ordered.length);
		return ordered;
	}

	static function mainClassHasReachabilityRoots(mainClass:HxClassDecl):Bool {
		for (fn in HxClassDecl.getFunctions(mainClass))
			if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main" && HxFunctionDecl.getBody(fn).length > 0)
				return true;
		return false;
	}

	static function renderPreAnonSupportClasses(program:GenIrProgram, mainClass:HxClassDecl, classLookup:CppClassLookup):Array<Array<String>> {
		final out = new Array<Array<String>>();
		final emitted = new haxe.ds.StringMap<Bool>();
		final mainName = HxClassDecl.getName(mainClass);
		for (typed in program.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final rawName = HxClassDecl.getName(cls);
				final helperName = renderedClassName(cls, classLookup);
				if (rawName == mainName || emitted.exists(helperName) || !isTemplateWrapSupportClass(cls))
					continue;
				emitted.set(helperName, true);
				out.push(renderTemplateWrapSupportClass(cls));
			}
		}
		return out;
	}

	static function orderHelperClasses(classes:Array<HxClassDecl>, classLookup:CppClassLookup):Array<HxClassDecl> {
		final byName = new haxe.ds.StringMap<HxClassDecl>();
		for (cls in classes)
			byName.set(renderedClassName(cls, classLookup), cls);
		final ordered = new Array<HxClassDecl>();
		final state = new haxe.ds.StringMap<Int>();
		function visit(cls:HxClassDecl):Void {
			final name = renderedClassName(cls, classLookup);
			final current = state.get(name);
			if (current == 2)
				return;
			if (current == 1)
				return;
			state.set(name, 1);
			for (dep in helperClassDependencies(cls, classLookup)) {
				final depCls = byName.get(dep);
				if (depCls != null)
					visit(depCls);
			}
			state.set(name, 2);
			ordered.push(cls);
		}
		for (cls in classes)
			visit(cls);
		return ordered;
	}

	static function helperClassDependencies(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final deps = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();
		final self = renderedClassName(cls, classLookup);
		final typeParams = genericClassTypeParams(cls);
		final includeRenderedBodies = helperClassRenderKind(cls, classLookup) == FullBody;
		function add(name:String):Void {
			if (name == null || name == self || !classLookup.names.exists(name) || seen.exists(name))
				return;
			for (param in typeParams)
				if (name == sanitizeIdentifier(param))
					return;
			seen.set(name, true);
			deps.push(name);
		}
		add(baseTypeName(cls));
		for (iface in implementedInterfaceNames(cls, classLookup))
			add(iface);
		for (field in HxClassDecl.getFields(cls)) {
			addTypeHintDependencies(HxFieldDecl.getTypeHint(field), add);
			final init = HxFieldDecl.getInit(field);
			if (includeRenderedBodies && init != null)
				addExprClassDependencies(init, add);
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			final fnScope = renderScope(cls, classLookup, "void");
			applyFunctionTypeParams(fnScope, fn);
			final fnTypeParams = genericClassTypeParams(cls).concat(genericFunctionTypeParams(fn));
			function addFn(name:String):Void {
				final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
				for (param in fnTypeParams)
					if (clean == sanitizeTypePath(param))
						return;
				add(clean);
			}
			addTypeHintDependencies(HxFunctionDecl.getReturnTypeHint(fn), addFn, fnScope);
			for (arg in HxFunctionDecl.getArgs(fn))
				addTypeHintDependencies(HxFunctionArg.getTypeHint(arg), addFn, fnScope);
			if (includeRenderedBodies)
				addStmtClassDependencies(HxFunctionDecl.getBody(fn), addFn, fnScope);
		}
		if (isUnitTestBaseSupportClass(cls)) {
			// renderUnitTestBaseSupportClass emits target-owned calls through these helpers.
			add("Assert");
			add("Type");
		}
		return deps;
	}

	/**
		Collect helper classes that rendered inline C++ method bodies need fully defined.

		Forward declarations are enough for fields like `std::shared_ptr<T>`, but not
		for inline method bodies that instantiate `T` or call through a `T` reference.
		Those body-only dependencies must participate in helper ordering only for
		helpers whose parsed bodies are actually rendered.
	**/
	static function addStmtClassDependencies(stmts:Array<HxStmt>, add:String->Void, ?scope:CppRenderScope):Void {
		for (stmt in stmts)
			addOneStmtClassDependencies(stmt, add, scope);
	}

	static function addOneStmtClassDependencies(stmt:HxStmt, add:String->Void, ?scope:CppRenderScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				addStmtClassDependencies(stmts, add, scope);
			case SVar(_, typeHint, init, _):
				addTypeHintDependencies(typeHint, add, scope);
				if (init != null)
					addExprClassDependencies(init, add);
			case SIf(cond, thenBranch, elseBranch, _):
				addExprClassDependencies(cond, add);
				addOneStmtClassDependencies(thenBranch, add, scope);
				if (elseBranch != null)
					addOneStmtClassDependencies(elseBranch, add, scope);
			case SForIn(_, iterable, body, _):
				addExprClassDependencies(iterable, add);
				addOneStmtClassDependencies(body, add, scope);
			case SForKeyValue(_, _, iterable, body, _):
				addExprClassDependencies(iterable, add);
				addOneStmtClassDependencies(body, add, scope);
			case SWhile(cond, body, _):
				addExprClassDependencies(cond, add);
				addOneStmtClassDependencies(body, add, scope);
			case SDoWhile(body, cond, _):
				addOneStmtClassDependencies(body, add, scope);
				addExprClassDependencies(cond, add);
			case SSwitch(scrutinee, _, bodies, _):
				addExprClassDependencies(scrutinee, add);
				for (body in bodies)
					addOneStmtClassDependencies(body, add, scope);
			case STry(tryBody, catches, _):
				addOneStmtClassDependencies(tryBody, add, scope);
				for (c in catches) {
					addTypeHintDependencies(c.typeHint, add, scope);
					addOneStmtClassDependencies(c.body, add, scope);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				addExprClassDependencies(expr, add);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function addExprClassDependencies(expr:HxExpr, add:String->Void):Void {
		switch (expr) {
			case ENew(typePath, args):
				addTypeHintDependencies(typePath, add);
				for (arg in args)
					addExprClassDependencies(arg, add);
			case EField(receiver, _):
				addExprClassDependencies(receiver, add);
			case ECall(EField(receiver, method), args):
				if (isInt64StaticReceiver(receiver) && int64StaticCallNeedsHelper(method))
					add("Int64Helper");
				if (!isStringToolsIntrinsicCall(receiver, method))
					addStaticReceiverClassDependency(receiver, add);
				addExprClassDependencies(receiver, add);
				for (arg in args)
					addExprClassDependencies(arg, add);
			case ECall(callee, args):
				addExprClassDependencies(callee, add);
				for (arg in args)
					addExprClassDependencies(arg, add);
			case EArrayDecl(values):
				for (value in values)
					addExprClassDependencies(value, add);
			case EArrayAccess(array, index):
				addExprClassDependencies(array, add);
				addExprClassDependencies(index, add);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr):
				addExprClassDependencies(iterable, add);
				if (guardExpr != null)
					addExprClassDependencies(guardExpr, add);
				addExprClassDependencies(yieldExpr, add);
			case ERange(start, end):
				addExprClassDependencies(start, add);
				addExprClassDependencies(end, add);
			case EBinop(_, left, right):
				addExprClassDependencies(left, add);
				addExprClassDependencies(right, add);
			case EUnop(_, inner) | ELambda(_, inner) | EMacroExpr(inner, _) | EUntyped(inner):
				addExprClassDependencies(inner, add);
			case ETernary(cond, thenExpr, elseExpr):
				addExprClassDependencies(cond, add);
				addExprClassDependencies(thenExpr, add);
				addExprClassDependencies(elseExpr, add);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					addExprClassDependencies(value, add);
			case ESwitch(scrutinee, _, exprs):
				addExprClassDependencies(scrutinee, add);
				for (caseExpr in exprs)
					addExprClassDependencies(caseExpr, add);
			case ECast(inner, typeHint):
				addExprClassDependencies(inner, add);
				addTypeHintDependencies(typeHint, add);
			case _:
		}
	}

	static function addStaticReceiverClassDependency(receiver:HxExpr, add:String->Void):Void {
		final typePath = staticReceiverTypePath(receiver);
		if (typePath != null)
			add(sanitizeTypePath(typeBaseName(typePath)));
	}

	static function addTypeHintDependencies(typeHint:String, add:String->Void, ?scope:CppRenderScope):Void {
		final hint = unwrapNullTypeHint(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0)
			return;
		if (scopedGenericTypeParamName(hint, scope).length > 0)
			return;
		if (isArrayLikeTypeHint(hint)) {
			addTypeHintDependencies(genericTypeHintArg(hint), add, scope);
			return;
		}
		if (isIterableTypeHint(hint)) {
			addTypeHintDependencies(genericTypeHintArg(hint), add, scope);
			return;
		}
		if (isFunctionTypeHint(hint)) {
			for (part in splitTopLevelFunctionType(hint))
				addTypeHintDependencies(part, add, scope);
			return;
		}
		if (isStructuralTypeHint(hint)) {
			for (field in CppTypeModel.structuralTypeHintFields(hint))
				addTypeHintDependencies(field.typeHint, add, scope);
			return;
		}
		for (arg in genericTypeHintArgs(hint))
			addTypeHintDependencies(arg, add, scope);
		final base = sanitizeTypePath(typeBaseName(hint));
		add(base);
		final lookup = lookupForScope(scope);
		final cls = lookupClassForTypeHint(hint, scope, lookup);
		if (cls != null) {
			final rendered = renderedClassName(cls, lookup);
			if (rendered.length > 0 && rendered != base)
				add(rendered);
		}
		final compact = removeTypeHintWhitespace(hint);
		final open = compact.indexOf("<");
		final path = open < 0 ? compact : compact.substr(0, open);
		final qualified = sanitizeTypePath(path);
		if (path.indexOf(".") >= 0 && qualified != base)
			add(qualified);
	}

	static function renderHelperClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		if (isCppCoreExternClass(HxClassDecl.getName(cls)))
			return [];
		if (isBytesDataTypeName(HxClassDecl.getName(cls)))
			return [];
		if (isNativeStackTraceSupportClass(cls))
			return [];
		final className = renderedClassName(cls, classLookup);
		if (HxClassDecl.getFields(cls).length == 0
			&& HxClassDecl.getFunctions(cls).length == 0
			&& renderMissingInterfaceDeclaration(className) != null)
			return [];
		if (HxClassDecl.getIsInterface(cls))
			return renderInterfaceClass(cls, classLookup);
		if (isAnySupportClass(cls))
			return CppRuntimeSupport.anySupportLines();
		if (isGenericMapSupportClass(cls))
			return renderGenericMapSupportClass(cls);
		if (isPosInfosSupportClass(cls))
			return renderPosInfosClass();
		if (isRestSupportClass(cls))
			return renderRestSupportClass(cls);
		if (isStdVectorHelperClass(cls) || isStdVectorHelperName(className))
			return renderStdVectorSupportClass(cls, classLookup);
		if (isTemplateWrapSupportClass(cls))
			return renderTemplateWrapSupportClass(cls);
		if (isHashMapBackedAbstractClass(cls))
			return renderHashMapBackedAbstractClass(cls);
		if (isStringMapBackedAbstractClass(cls))
			return renderStringMapBackedAbstractClass(cls);
		if (isArrayBackedAbstractClass(cls))
			return renderArrayBackedAbstractClass(cls, classLookup);
		if (isPrimitiveBackedAbstractClass(cls))
			return renderPrimitiveBackedAbstractClass(cls, classLookup);
		if (isStdArrayHelperClass(cls))
			return renderStdArrayHelperClass(cls, classLookup);
		if (isCppReportSupportClass(cls))
			return renderCppReportSupportClass(cls, classLookup);
		if (isUtestAssertSupportClass(cls, classLookup))
			return renderUtestAssertSupportClass(cls, classLookup);
		if (isUnitTestBaseSupportClass(cls))
			return renderUnitTestBaseSupportClass(cls, classLookup);
		if (isTemplateSupportClass(cls))
			return renderTemplateSupportClass(cls, classLookup);
		final typeParams = genericClassTemplateParams(cls);
		final baseType = inheritedCppBaseTypeName(cls, classLookup);
		final baseTypes = inheritedCppBaseTypes(cls, classLookup);
		final out = typeParams.length > 0 ? [genericTemplatePrefix(typeParams)] : [];
		out.push("struct " + className + (baseTypes.length == 0 ? "" : " : " + baseTypes.join(", ")) + " {");
		final scope = renderScope(cls, classLookup, "void");
		for (field in HxClassDecl.getFields(cls)) {
			final fieldName = HxFieldDecl.getName(field);
			traceCppMemberPhase(className, "render_helper_field", fieldName, "begin");
			final init = HxFieldDecl.getInit(field);
			final typeName = knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), init, scope);
			if (HxFieldDecl.getIsStatic(field)) {
				final rhs = init == null ? cppDefaultValue(typeName, scope) : renderLocalInitExpr(init, typeName, typeName, scope);
				out.push("  inline static " + typeName + " " + sanitizeIdentifier(fieldName) + " = " + rhs + ";");
				traceCppMemberPhase(className, "render_helper_field", fieldName, "end");
				continue;
			}
			final genericField = isGenericTypeParamHint(HxFieldDecl.getTypeHint(field), cls);
			if (init == null && genericField) {
				out.push("  " + typeName + " " + sanitizeIdentifier(fieldName) + ";");
			} else {
				final rhs = init == null ? cppDefaultValue(typeName, scope) : renderLocalInitExpr(init, typeName, typeName, scope);
				out.push("  " + typeName + " " + sanitizeIdentifier(fieldName) + " = " + rhs + ";");
			}
			traceCppMemberPhase(className, "render_helper_field", fieldName, "end");
		}
		final ctor = findConstructor(cls);
		if (ctor == null) {
			for (line in renderImplicitConstructors(className, baseType, scope))
				out.push(line);
		} else {
			traceCppMemberPhase(className, "render_helper_ctor", HxFunctionDecl.getName(ctor), "begin");
			prepareFunctionScope(scope, ctor);
			traceCppMemberPhase(className, "render_helper_ctor", HxFunctionDecl.getName(ctor), "after_prepare");
			out.push("  "
				+ className
				+ "("
				+ renderFunctionArgs(HxFunctionDecl.getArgs(ctor), scope)
				+ ")"
				+ constructorInitializerList(ctor, scope)
				+ " {");
			traceCppMemberPhase(className, "render_helper_ctor", HxFunctionDecl.getName(ctor), "after_signature");
			for (line in renderStmts(constructorBodyWithoutInitializerStmts(ctor, scope), "    ", scope))
				out.push(line);
			out.push("  }");
			traceCppMemberPhase(className, "render_helper_ctor", HxFunctionDecl.getName(ctor), "end");
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "new")
				continue;
			final methodName = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			final timingEnabled = traceCppTimingsEnabled();
			final startTime = timingEnabled ? Sys.time() : 0.0;
			final methodLines = renderHelperMethod(fn, cls, classLookup);
			for (line in methodLines)
				out.push(line);
			if (timingEnabled) {
				final elapsed = Sys.time() - startTime;
				traceCppTimingPhase("render_helper_method_timing owner=" + className + " name=" + methodName + " seconds=" + Std.string(elapsed) + " lines="
					+ methodLines.length);
			}
		}
		out.push("};");
		for (line in renderGenericClassFactory(className, typeParams, ctor, scope))
			out.push(line);
		return out;
	}

	static function renderInterfaceClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = renderedClassName(cls, classLookup);
		if (HxClassDecl.getFunctions(cls).length == 0 && renderMissingInterfaceDeclaration(className) != null)
			return [];
		final typeParams = genericClassTemplateParams(cls);
		final scope = renderScope(cls, classLookup, "void");
		final out = typeParams.length > 0 ? [genericTemplatePrefix(typeParams)] : [];
		final baseTypes = inheritedCppBaseTypes(cls, classLookup);
		out.push("struct " + className + (baseTypes.length == 0 ? "" : " : " + baseTypes.join(", ")) + " {");
		out.push("  virtual ~" + className + "() = default;");
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getIsStatic(fn))
				continue;
			final returnType = cppFunctionReturnType(fn, cls, classLookup);
			scope.returnType = returnType;
			prepareFunctionSignatureScope(scope, fn);
			out.push("  virtual " + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "("
				+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") = 0;");
		}
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field))
				continue;
			final fieldName = sanitizeIdentifier(HxFieldDecl.getName(field));
			final fieldType = cppTypeHint(HxFieldDecl.getTypeHint(field), scope, classLookup);
			if (HxFieldDecl.getPropertyGet(field) == "get")
				out.push("  virtual " + fieldType + " get_" + fieldName + "() { return " + cppDefaultValue(fieldType, scope) + "; }");
			if (HxFieldDecl.getPropertySet(field) == "set")
				out.push("  virtual " + fieldType + " set_" + fieldName + "(" + fieldType + " value) { return value; }");
		}
		out.push("};");
		return out;
	}

	static function renderGenericClassFactory(className:String, typeParams:Array<String>, ctor:Null<HxFunctionDecl>, scope:CppRenderScope):Array<String> {
		if (typeParams.length == 0)
			return [];
		final args = ctor == null ? [] : HxFunctionDecl.getArgs(ctor);
		final argNames = [for (arg in args) sanitizeIdentifier(HxFunctionArg.getName(arg))];
		return [genericTemplatePrefix(typeParams),
			"std::shared_ptr<"
			+ className
			+ "<"
			+ typeParams.join(", ")
			+ ">> __hxhx_make_shared_"
			+ className
			+ "("
			+ renderFunctionArgs(args, scope, false)
			+ ") {",
			"  return std::make_shared<"
			+ className
			+ "<"
			+ typeParams.join(", ")
			+ ">>("
			+ argNames.join(", ")
			+ ");",
			"}"
		];
	}

	static function renderGenericClassFactoryDeclaration(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = renderedClassName(cls, classLookup);
		final typeParams = genericClassTemplateParams(cls);
		final ctor = findConstructor(cls);
		if (typeParams.length == 0)
			return [];
		final scope = renderScope(cls, classLookup, "void");
		if (ctor != null)
			prepareFunctionScope(scope, ctor);
		final args = ctor == null ? [] : HxFunctionDecl.getArgs(ctor);
		return [genericTemplatePrefix(typeParams),
			"std::shared_ptr<"
			+ className
			+ "<"
			+ typeParams.join(", ")
			+ ">> __hxhx_make_shared_"
			+ className
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ");"];
	}

	static function renderImplicitConstructors(className:String, baseType:Null<String>, scope:CppRenderScope):Array<String> {
		final typedefCtor = renderStructuralTypedefImplicitConstructors(className, scope);
		if (typedefCtor != null)
			return typedefCtor;
		final abstractCtor = renderClassBackedAbstractImplicitConstructors(className, scope);
		if (abstractCtor != null)
			return abstractCtor;
		if (baseType == null)
			return ["  " + className + "() {}"];
		final baseCls = scope == null ? null : scope.classByName.get(baseType);
		if (baseCls == null)
			return ["  " + className + "() : " + baseType + "() {}"];
		final baseCtor = findConstructor(baseCls);
		if (baseCtor == null)
			return ["  " + className + "() : " + baseType + "() {}"];
		final baseScope = renderScope(baseCls, {names: scope.classNames, byName: scope.classByName}, "void");
		prepareFunctionScope(baseScope, baseCtor);
		final args = HxFunctionDecl.getArgs(baseCtor);
		final argNames = [for (arg in args) sanitizeIdentifier(HxFunctionArg.getName(arg))];
		return [
			"  " + className + "(" + renderFunctionArgs(args, baseScope) + ") : " + baseType + "(" + argNames.join(", ") + ") {}"
		];
	}

	static function renderStructuralTypedefImplicitConstructors(className:String, scope:CppRenderScope):Null<Array<String>> {
		final cls = structuralTypedefClassForCppType(className, scope);
		if (cls == null)
			return null;
		final fields = [
			for (field in HxClassDecl.getFields(cls))
				if (!HxFieldDecl.getIsStatic(field)) field
		];
		final out = ["  " + className + "() = default;"];
		if (fields.length == 0)
			return out;
		final ctorArgs = new Array<String>();
		final ctorInits = new Array<String>();
		final fieldChecks = new Array<String>();
		final pointerChecks = new Array<String>();
		final otherInits = new Array<String>();
		final pointerInits = new Array<String>();
		for (field in fields) {
			final fieldName = sanitizeIdentifier(HxFieldDecl.getName(field));
			final fieldType = knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
			final argName = "__hxhx_" + fieldName;
			ctorArgs.push(fieldType + " " + argName);
			ctorInits.push(fieldName + "(" + argName + ")");
			fieldChecks.push("decltype(std::declval<const Other&>()." + fieldName + ")");
			pointerChecks.push("decltype(std::declval<const Other&>()->" + fieldName + ")");
			otherInits.push(fieldName + "(other." + fieldName + ")");
			pointerInits.push(fieldName + "(other->" + fieldName + ")");
		}
		out.push("  " + className + "(" + ctorArgs.join(", ") + ") : " + ctorInits.join(", ") + " {}");
		out.push("  "
			+ className
			+ "(const __hxhx_anon&) : "
			+ [for (field in fields) sanitizeIdentifier(HxFieldDecl.getName(field)) + "()"].join(", ") + " {}");
		out.push("  template<typename Other, typename = std::enable_if_t<!std::is_same_v<std::decay_t<Other>, "
			+ className
			+ ">>, typename = std::void_t<"
			+ fieldChecks.join(", ")
			+ ">>");
		out.push("  " + className + "(const Other& other) : " + otherInits.join(", ") + " {}");
		out.push("  template<typename Other, typename = std::enable_if_t<!std::is_same_v<std::decay_t<Other>, "
			+ className
			+ ">>, typename = std::void_t<"
			+ pointerChecks.join(", ")
			+ ">, typename = void>");
		out.push("  " + className + "(const Other& other) : " + pointerInits.join(", ") + " {}");
		return out;
	}

	static function renderClassBackedAbstractImplicitConstructors(className:String, scope:CppRenderScope):Null<Array<String>> {
		if (scope == null || scope.owner == null)
			return null;
		final cls = scope.classByName.get(className);
		if (cls == null)
			return null;
		final underlying = abstractUnderlyingTypeHint(cls);
		if (underlying == null || primitiveAbstractUnderlyingCppType(cls) != null || genericTypeHintArgs(underlying).length > 0)
			return null;
		final underlyingName = sanitizeTypePath(typeBaseName(underlying));
		if (!scope.classByName.exists(underlyingName))
			return null;
		final underlyingCtor = findConstructor(scope.classByName.get(underlyingName));
		if (underlyingCtor == null)
			return null;
		final underlyingScope = renderScope(scope.classByName.get(underlyingName), {names: scope.classNames, byName: scope.classByName}, "void");
		prepareFunctionScope(underlyingScope, underlyingCtor);
		final args = HxFunctionDecl.getArgs(underlyingCtor);
		final initializers = [
			for (arg in args) {
				final name = sanitizeIdentifier(HxFunctionArg.getName(arg));
				if (hasInstanceField(cls, name)) name + "(" + name + ")" else null;
			}
		].filter(v -> v != null);
		if (initializers.length == 0)
			return null;
		return ["  " + className + "() {}",
			"  "
			+ className
			+ "("
			+ renderFunctionArgs(args, underlyingScope)
			+ ") : "
			+ initializers.join(", ")
			+ " {}"];
	}

	static function renderStdArrayHelperClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		if (genericClassTemplateParams(cls).length > 0)
			return [];
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final out = ["struct " + className + " {"];
		out.push("  std::vector<std::string> __values;");
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field))
				continue;
			final scope = renderScope(cls, classLookup, "void");
			final init = HxFieldDecl.getInit(field);
			final typeName = knownStdlibFieldCppType(className, HxFieldDecl.getName(field), HxFieldDecl.getTypeHint(field), init, scope);
			final rhs = init == null ? cppDefaultValue(typeName, scope) : renderExpr(init, scope);
			out.push("  " + typeName + " " + sanitizeIdentifier(HxFieldDecl.getName(field)) + " = " + rhs + ";");
		}
		out.push("  " + className + "() {}");
		out.push("  " + className + "(std::vector<std::string> values) : __values(values) {");
		if (hasInstanceField(cls, "length"))
			out.push("    length = static_cast<int>(__values.size());");
		out.push("  }");
		out.push("  std::size_t size() const { return __values.size(); }");
		out.push("  std::string& operator[](int index) { return __values[index]; }");
		out.push("  const std::string& operator[](int index) const { return __values[index]; }");
		out.push("  auto begin() { return __values.begin(); }");
		out.push("  auto end() { return __values.end(); }");
		out.push("  auto begin() const { return __values.begin(); }");
		out.push("  auto end() const { return __values.end(); }");
		out.push("  std::string join(std::string sep) const { return __hxhx_join(__values, sep); }");
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "new" || HxFunctionDecl.getName(fn) == "join")
				continue;
			for (line in renderHelperMethod(fn, cls, classLookup))
				out.push(line);
		}
		out.push("};");
		return out;
	}

	static function isTemplateSupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) == "Template";
	}

	static function renderTemplateSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final scope = renderScope(cls, classLookup, "void");
		final out = ["struct " + className + " {"];
		for (field in HxClassDecl.getFields(cls)) {
			final fieldName = HxFieldDecl.getName(field);
			final typeName = knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
			final rhs = templateFieldInitExpr(fieldName, typeName, HxFieldDecl.getInit(field), scope);
			final prefix = HxFieldDecl.getIsStatic(field) ? "  inline static " : "  ";
			out.push(prefix + typeName + " " + sanitizeIdentifier(fieldName) + " = " + rhs + ";");
		}
		final ctor = findConstructor(cls);
		if (ctor == null) {
			out.push("  " + className + "() {}");
		} else {
			prepareFunctionScope(scope, ctor);
			out.push("  " + className + "(" + renderFunctionArgs(HxFunctionDecl.getArgs(ctor), scope) + ") {");
			for (line in renderTemplateUnusedArgs(HxFunctionDecl.getArgs(ctor)))
				out.push(line);
			out.push("  }");
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "new")
				continue;
			for (line in renderTemplateNeutralMethod(fn, cls, classLookup))
				out.push(line);
		}
		out.push("};");
		return out;
	}

	static function isUtestAssertSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Bool {
		if (cls == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != "Assert")
			return false;
		return packagePathForRenderedClass(cls, classLookup) == "utest" || hasUtestAssertSupportShape(cls);
	}

	static function hasUtestAssertSupportShape(cls:HxClassDecl):Bool {
		var hasResultsField = false;
		for (field in HxClassDecl.getFields(cls)) {
			final fieldName = sanitizeIdentifier(HxFieldDecl.getName(field));
			final fieldHint = removeTypeHintWhitespace(HxFieldDecl.getTypeHint(field));
			if (HxFieldDecl.getIsStatic(field) && fieldName == "results" && fieldHint.indexOf("List<") >= 0 && fieldHint.indexOf("Assertation") >= 0) {
				hasResultsField = true;
				break;
			}
		}
		if (!hasResultsField)
			return false;
		final required = new haxe.ds.StringMap<Bool>();
		for (name in ["q", "same", "sameAs", "createAsync"])
			required.set(name, false);
		for (fn in HxClassDecl.getFunctions(cls)) {
			final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			if (required.exists(method))
				required.set(method, true);
		}
		for (name in ["q", "same", "sameAs", "createAsync"])
			if (!required.get(name))
				return false;
		return true;
	}

	static function renderUtestAssertSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = renderedClassName(cls, classLookup);
		traceCppPhase("render_utest_assert_support name=" + className);
		final scope = renderScope(cls, classLookup, "void");
		final out = ["struct " + className + " {"];
		for (field in HxClassDecl.getFields(cls)) {
			final fieldName = HxFieldDecl.getName(field);
			final typeName = knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
			final rhs = HxFieldDecl.getInit(field) == null ? cppDefaultValue(typeName,
				scope) : renderLocalInitExpr(HxFieldDecl.getInit(field), typeName, typeName, scope);
			out.push((HxFieldDecl.getIsStatic(field) ? "  inline static " : "  ")
				+ typeName
				+ " "
				+ sanitizeIdentifier(fieldName)
				+ " = "
				+ rhs
				+ ";");
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			if (method == "new")
				continue;
			final isPolymorphicAssertHelper = isAssertPolymorphicStringifyHelper(fn, cls)
				|| isAssertPolymorphicSameHelper(fn, cls)
				|| isAssertPolymorphicSameAsHelper(fn, cls);
			if (isPolymorphicAssertHelper) {
				for (line in renderHelperMethod(fn, cls, classLookup))
					out.push(line);
				continue;
			}
			if (HxFunctionDecl.getVisibility(fn) != Public)
				continue;
			if (method == "createAsync" || method == "createEvent") {
				for (line in renderUtestAssertCallableStub(fn, cls, classLookup))
					out.push(line);
				continue;
			}
			for (line in renderUtestAssertNeutralMethod(fn, cls, classLookup))
				out.push(line);
		}
		out.push("};");
		return out;
	}

	static function isUnitTestBaseSupportClass(cls:HxClassDecl):Bool {
		if (cls == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != "Test")
			return false;
		final required = new haxe.ds.StringMap<Bool>();
		for (name in [
			"eq",
			"feq",
			"aeq",
			"t",
			"f",
			"assert",
			"exc",
			"unspec",
			"allow",
			"noAssert",
			"hf",
			"nhf",
			"hsf",
			"nhsf"
		])
			required.set(name, false);
		for (fn in HxClassDecl.getFunctions(cls)) {
			final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			if (required.exists(method))
				required.set(method, true);
		}
		for (name in [
			"eq",
			"feq",
			"aeq",
			"t",
			"f",
			"assert",
			"exc",
			"unspec",
			"allow",
			"noAssert",
			"hf",
			"nhf",
			"hsf",
			"nhsf"
		])
			if (!required.get(name))
				return false;
		return true;
	}

	static function renderUnitTestBaseSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = renderedClassName(cls, classLookup);
		traceCppPhase("render_unit_test_base_support name=" + className);
		final baseTypes = inheritedCppBaseTypes(cls, classLookup);
		final out = [
			"struct " + className + (baseTypes.length == 0 ? "" : " : " + baseTypes.join(", ")) + " {"
		];
		out.push("  " + className + "() {}");
		for (fn in HxClassDecl.getFunctions(cls)) {
			final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			if (method == "new")
				continue;
			switch (method) {
				case "eq":
					for (line in renderHelperMethod(fn, cls, classLookup))
						out.push(line);
				case "t" | "f":
					for (line in renderUnitTestValueAssertMethod(fn))
						out.push(line);
				case "allow":
					for (line in renderUnitTestAllowMethod(fn))
						out.push(line);
				case "exc" | "unspec":
					for (line in renderUnitTestFunctionMethod(fn))
						out.push(line);
				case _:
					final lines = renderUtestAssertNeutralMethod(fn, cls, classLookup);
					for (line in lines)
						out.push(line);
					final returnType = supportMethodSignatureReturnType(fn, cls, classLookup);
					final scope = renderScope(cls, classLookup, returnType);
					prepareFunctionSignatureScope(scope, fn);
					for (line in renderDceReflectionHelperStringOverload(fn, scope, returnType))
						out.push(line);
			}
		}
		out.push("};");
		return out;
	}

	static function renderUnitTestValueAssertMethod(fn:HxFunctionDecl):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final valueName = args.length > 0 ? sanitizeIdentifier(HxFunctionArg.getName(args[0])) : "v";
		final posName = args.length > 1 ? sanitizeIdentifier(HxFunctionArg.getName(args[1])) : "pos";
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return ["  template<typename TValue>",
			"  void "
			+ method
			+ "(const TValue& "
			+ valueName
			+ ", std::optional<PosInfos> "
			+ posName
			+ " = std::nullopt) {",
			"    (void)" + valueName + ";",
			"    (void)" + posName + ";",
			"  }"
		];
	}

	static function renderUnitTestAllowMethod(fn:HxFunctionDecl):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final valueName = args.length > 0 ? sanitizeIdentifier(HxFunctionArg.getName(args[0])) : "v";
		final valuesName = args.length > 1 ? sanitizeIdentifier(HxFunctionArg.getName(args[1])) : "values";
		final posName = args.length > 2 ? sanitizeIdentifier(HxFunctionArg.getName(args[2])) : "pos";
		return ["  template<typename TValue>",
			"  void allow(const TValue& "
			+ valueName
			+ ", std::vector<TValue> "
			+ valuesName
			+ ", std::optional<PosInfos> "
			+ posName
			+ " = std::nullopt) {",
			"    (void)" + valueName + ";",
			"    (void)" + valuesName + ";",
			"    (void)" + posName + ";",
			"  }"
		];
	}

	static function renderUnitTestFunctionMethod(fn:HxFunctionDecl):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final functionName = args.length > 0 ? sanitizeIdentifier(HxFunctionArg.getName(args[0])) : "f";
		final posName = args.length > 1 ? sanitizeIdentifier(HxFunctionArg.getName(args[1])) : "pos";
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return ["  void "
			+ method
			+ "(std::function<void()> "
			+ functionName
			+ ", std::optional<PosInfos> "
			+ posName
			+ " = std::nullopt) {",
			"    (void)" + functionName + ";",
			"    (void)" + posName + ";",
			"  }"
		];
	}

	static function renderUtestAssertNeutralMethod(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = supportMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		applyFunctionTypeParams(scope, fn);
		registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn));
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		if (methodTypeParams.length > 0)
			out.push("  " + genericTemplatePrefix(methodTypeParams));
		out.push("  " + (HxFunctionDecl.getIsStatic(fn) ? "static " : "") + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") {");
		for (line in renderTemplateUnusedArgs(HxFunctionDecl.getArgs(fn)))
			out.push(line);
		if (returnType != "void")
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		out.push("  }");
		return out;
	}

	static function renderUtestAssertCallableStub(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = "auto";
		final scope = renderScope(owner, classLookup, returnType);
		applyFunctionTypeParams(scope, fn);
		registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn));
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		if (methodTypeParams.length > 0)
			out.push("  " + genericTemplatePrefix(methodTypeParams));
		out.push("  static " + returnType + " " + method + "(" + renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") {");
		for (line in renderTemplateUnusedArgs(HxFunctionDecl.getArgs(fn)))
			out.push(line);
		if (method == "createEvent") {
			out.push("    return [](auto e) { (void)e; };");
		} else {
			out.push("    return []() {};");
		}
		out.push("  }");
		return out;
	}

	static function supportMethodSignatureReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		final raw = StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn) == null ? "" : HxFunctionDecl.getReturnTypeHint(fn));
		if (raw.length == 0)
			return "void";
		final scope = renderScope(owner, classLookup, "auto");
		applyFunctionTypeParams(scope, fn);
		if (functionReturnTypeParamShouldUseAuto(raw, fn))
			return functionReturnsOnlyNull(fn) ? "std::nullptr_t" : "auto";
		final abstractReturn = abstractUnderlyingReturnCppType(raw, owner, scope, classLookup);
		return abstractReturn.length > 0 ? abstractReturn : cppReturnTypeHint(raw, scope, classLookup);
	}

	static function templateFieldInitExpr(fieldName:String, typeName:String, init:Null<HxExpr>, scope:CppRenderScope):String {
		return switch (sanitizeIdentifier(fieldName == null ? "" : fieldName)) {
			case "globals":
				"std::string()";
			case "hxKeepArrayIterator":
				"{}";
			case "context" | "macros":
				"std::string()";
			case _:
				init == null ? cppDefaultValue(typeName, scope) : renderLocalInitExpr(init, typeName, typeName, scope);
		};
	}

	static function renderTemplateNeutralMethod(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		if (methodTypeParams.length > 0)
			out.push("  " + genericTemplatePrefix(methodTypeParams));
		out.push("  " + (HxFunctionDecl.getIsStatic(fn) ? "static " : "") + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") {");
		for (line in renderTemplateUnusedArgs(HxFunctionDecl.getArgs(fn)))
			out.push(line);
		if (returnType != "void")
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		out.push("  }");
		return out;
	}

	static function renderTemplateUnusedArgs(args:Array<HxFunctionArg>):Array<String> {
		return [
			for (arg in args)
				"    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";"
		];
	}

	static function isTemplateWrapSupportClass(cls:HxClassDecl):Bool {
		if (cls == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != "TemplateWrap")
			return false;
		final underlying = abstractUnderlyingTypeHint(cls);
		return sanitizeTypePath(typeBaseName(underlying == null ? "" : underlying)) == "Template";
	}

	static function isStringMapBackedAbstractClass(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		final underlying = abstractUnderlyingTypeHint(cls);
		return sanitizeTypePath(typeBaseName(underlying == null ? "" : underlying)) == "StringMap";
	}

	static function isHashMapBackedAbstractClass(cls:HxClassDecl):Bool {
		if (cls == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != "HashMap")
			return false;
		final underlying = abstractUnderlyingTypeHint(cls);
		return sanitizeTypePath(typeBaseName(underlying == null ? "" : underlying)) == "HashMapData";
	}

	static function renderHashMapBackedAbstractClass(cls:HxClassDecl):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final typeParams = genericClassTemplateParams(cls);
		final keyType = typeParams.length > 0 ? sanitizeIdentifier(typeParams[0]) : "std::string";
		final valueType = typeParams.length > 1 ? sanitizeIdentifier(typeParams[1]) : "std::string";
		final out = typeParams.length > 0 ? [genericTemplatePrefix(typeParams)] : [];
		out.push("struct " + className + " {");
		out.push("  std::vector<std::pair<" + keyType + ", " + valueType + ">> values;");
		out.push("  " + className + "() {}");
		out.push("  int hashCode() { return 0; }");
		out.push("  void set(" + keyType + " key, " + valueType + " value) {");
		out.push("    (*this)[key] = value;");
		out.push("  }");
		out.push("  " + valueType + " get(" + keyType + " key) {");
		out.push("    for (auto& entry : values) if (__hxhx_key_eq(entry.first, key)) return entry.second;");
		out.push("    return " + valueType + "{};");
		out.push("  }");
		out.push("  " + valueType + "& operator[](" + keyType + " key) {");
		out.push("    for (auto& entry : values) if (__hxhx_key_eq(entry.first, key)) return entry.second;");
		out.push("    values.push_back(std::make_pair(key, " + valueType + "{}));");
		out.push("    return values.back().second;");
		out.push("  }");
		out.push("  const " + valueType + "& operator[](" + keyType + " key) const {");
		out.push("    for (const auto& entry : values) if (__hxhx_key_eq(entry.first, key)) return entry.second;");
		out.push("    static const " + valueType + " empty = " + valueType + "{};");
		out.push("    return empty;");
		out.push("  }");
		out.push("  bool exists(" + keyType + " key) {");
		out.push("    for (const auto& entry : values) if (__hxhx_key_eq(entry.first, key)) return true;");
		out.push("    return false;");
		out.push("  }");
		out.push("  bool remove(" + keyType + " key) {");
		out.push("    for (auto it = values.begin(); it != values.end(); ++it) if (__hxhx_key_eq(it->first, key)) { values.erase(it); return true; }");
		out.push("    return false;");
		out.push("  }");
		out.push("  std::shared_ptr<__hxhx_iterator<" + keyType + ">> keys() {");
		out.push("    std::vector<" + keyType + "> out;");
		out.push("    for (const auto& entry : values) out.push_back(entry.first);");
		out.push("    return __hxhx_vector_iterator_of(out);");
		out.push("  }");
		out.push("  std::shared_ptr<__hxhx_iterator<" + valueType + ">> iterator() {");
		out.push("    std::vector<" + valueType + "> out;");
		out.push("    for (const auto& entry : values) out.push_back(entry.second);");
		out.push("    return __hxhx_vector_iterator_of(out);");
		out.push("  }");
		out.push("  std::string toString() { return __hxhx_map_literal_to_string(values); }");
		out.push("  void clear() { values.clear(); }");
		out.push("};");
		out.push(genericTemplatePrefix(typeParams));
		out.push("std::shared_ptr<" + className + "<" + typeParams.join(", ") + ">> __hxhx_make_shared_" + className + "() {");
		out.push("  return std::make_shared<" + className + "<" + typeParams.join(", ") + ">>();");
		out.push("}");
		return out;
	}

	static function renderStringMapBackedAbstractClass(cls:HxClassDecl):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final typeParams = genericClassTemplateParams(cls);
		final valueType = typeParams.length > 0 ? sanitizeIdentifier(typeParams[0]) : "std::string";
		final out = typeParams.length > 0 ? [genericTemplatePrefix(typeParams)] : [];
		out.push("struct " + className + " {");
		out.push("  std::shared_ptr<StringMap<" + valueType + ">> __value = __hxhx_make_shared_StringMap<" + valueType + ">();");
		out.push("  " + className + "() {}");
		out.push("  void set(std::string k, " + valueType + " v) {");
		out.push("    __value->set(k, v);");
		out.push("  }");
		out.push("  " + valueType + " get(std::string k) {");
		out.push("    return __value->get(k).value_or(" + valueType + "{});");
		out.push("  }");
		out.push("  std::string toString() {");
		out.push("    return __value->toString();");
		out.push("  }");
		out.push("  template<typename K>");
		out.push("  static std::shared_ptr<" + className + "<K>> fromArray(std::vector<K> arr) {");
		out.push("    auto out = std::make_shared<" + className + "<K>>();");
		out.push("    for (int i = 0; i < static_cast<int>(arr.size()); ++i) {");
		out.push("      out->set(std::string(\"_s\") + std::to_string(i), arr[i]);");
		out.push("    }");
		out.push("    return out;");
		out.push("  }");
		out.push("  static std::shared_ptr<" + className + "<std::string>> fromStringArray(std::vector<std::string> arr) {");
		out.push("    auto out = std::make_shared<" + className + "<std::string>>();");
		out.push("    for (int i = 0; i + 1 < static_cast<int>(arr.size()); i += 2) {");
		out.push("      out->set(arr[i], arr[i + 1]);");
		out.push("    }");
		out.push("    return out;");
		out.push("  }");
		out.push("};");
		return out;
	}

	static function renderTemplateWrapSupportClass(cls:HxClassDecl):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		return ["struct " + className + " {",
			"  std::shared_ptr<Template> __value = nullptr;",
			"  " + className + "() {}",
			"  " + className + "(std::string value) { (void)value; }",
			"  "
			+ className
			+ "(const char* value) : "
			+ className
			+ "(std::string(value == nullptr ? \"\" : value)) {}",
			"  " + className + "(std::shared_ptr<Template> value) : __value(value) {}",
			"  " + className + "& operator=(std::string value) {",
			"    (void)value;",
			"    return *this;",
			"  }",
			"  " + className + "& operator=(const char* value) {",
			"    return (*this = std::string(value == nullptr ? \"\" : value));",
			"  }",
			"  " + className + "& operator=(std::shared_ptr<Template> value) {",
			"    __value = value;",
			"    return *this;",
			"  }",
			"  operator std::shared_ptr<Template>() const { return __value; }",
			"  std::string execute(std::string context = std::string(), std::optional<std::string> macros = std::nullopt) const {",
			"    (void)context;",
			"    (void)macros;",
			"    return std::string();",
			"  }",
			"  template<typename Context>",
			"  std::string execute(Context context) const {",
			"    (void)context;",
			"    return execute(std::string());",
			"  }",
			"  template<typename Context, typename Macros>",
			"  std::string execute(Context context, Macros macros) const {",
			"    (void)context;",
			"    (void)macros;",
			"    return execute(std::string());",
			"  }",
			"  " + className + " get() const { return *this; }",
			"  static "
			+ className
			+ " fromString(std::string value) { return "
			+ className
			+ "(value); }",
			"  std::string toString() const { return execute(std::string()); }",
			"  operator std::string() const { return toString(); }",
			"};"
		];
	}

	static function renderPosInfosClass():Array<String> {
		return [
			"struct PosInfos {",
			"  std::string fileName = std::string();",
			"  int lineNumber = 0;",
			"  std::string className = std::string();",
			"  std::string methodName = std::string();",
			"  std::vector<std::string> customParams = {};",
			"  PosInfos() {}",
			"  PosInfos(std::string fileName, int lineNumber, std::string className, std::string methodName)",
			"    : fileName(fileName), lineNumber(lineNumber), className(className), methodName(methodName) {}",
			"};"
		];
	}

	static function isGenericMapSupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) == "Map";
	}

	static function renderGenericMapSupportClass(cls:HxClassDecl):Array<String> {
		var typeParams = genericClassTemplateParams(cls);
		if (typeParams.length < 2)
			typeParams = ["K", "V"];
		final keyType = typeParams[0];
		final valueType = typeParams[1];
		return [
			genericTemplatePrefix(typeParams),
			"struct Map {",
			"  std::map<" + keyType + ", " + valueType + "> values;",
			"  Map() {}",
			"  void set(" + keyType + " key, " + valueType + " value) {",
			"    values[key] = value;",
			"  }",
			"  " + valueType + " get(" + keyType + " key) {",
			"    auto found = values.find(key);",
			"    return found == values.end() ? " + valueType + "() : found->second;",
			"  }",
			"  " + valueType + "& operator[](" + keyType + " key) {",
			"    return values[key];",
			"  }",
			"  const " + valueType + "& operator[](" + keyType + " key) const {",
			"    return values.at(key);",
			"  }",
			"  bool exists(" + keyType + " key) {",
			"    return values.find(key) != values.end();",
			"  }",
			"  bool remove(" + keyType + " key) {",
			"    return values.erase(key) > 0;",
			"  }",
			"  std::shared_ptr<__hxhx_iterator<" + keyType + ">> keys() {",
			"    std::vector<" + keyType + "> out;",
			"    for (const auto& entry : values) out.push_back(entry.first);",
			"    return __hxhx_vector_iterator_of(out);",
			"  }",
			"  std::string toString() {",
			"    std::vector<std::pair<" + keyType + ", " + valueType + ">> out;",
			"    for (const auto& entry : values) out.push_back(std::make_pair(entry.first, entry.second));",
			"    return __hxhx_map_literal_to_string(out);",
			"  }",
			"};",
			genericTemplatePrefix(typeParams),
			"std::shared_ptr<Map<" + typeParams.join(", ") + ">> __hxhx_make_shared_Map() {",
			"  return std::make_shared<Map<" + typeParams.join(", ") + ">>();",
			"}"
		];
	}

	static function renderArrayBackedAbstractClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final valueType = arrayBackedAbstractValueCppType(cls, classLookup);
		final out = ["struct " + className + " {"];
		out.push("  " + valueType + " __values;");
		out.push("  " + className + "() {}");
		out.push("  " + className + "(" + valueType + " values) : __values(values) {}");
		out.push("  std::size_t size() const { return __values.size(); }");
		out.push("  auto operator[](int index) const { return __values[index]; }");
		out.push("  " + className + " slice(int start, int end) const {");
		out.push("    if (start < 0) start = 0;");
		out.push("    if (end < start) end = start;");
		out.push("    if (static_cast<std::size_t>(end) > __values.size()) end = static_cast<int>(__values.size());");
		out.push("    return " + className + "(" + valueType + "(__values.begin() + start, __values.begin() + end));");
		out.push("  }");
		out.push("  operator " + valueType + "() const { return __values; }");
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "new")
				continue;
			for (line in renderHelperMethod(fn, cls, classLookup))
				out.push(line);
		}
		out.push("};");
		return out;
	}

	static function renderStdVectorSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final valueType = arrayBackedAbstractValueCppType(cls, classLookup);
		final elementType = cppVectorElementType(valueType);
		return ["struct " + className + " {",
			"  " + valueType + " __values;",
			"  int length = 0;",
			"  " + className + "() {}",
			"  " + className + "(int length) : __values(length), length(length) {}",
			"  "
			+ className
			+ "("
			+ valueType
			+ " values) : __values(values), length(static_cast<int>(values.size())) {}",
			"  std::size_t size() const { return __values.size(); }",
			"  " + elementType + "& operator[](int index) { return __values[index]; }",
			"  const " + elementType + "& operator[](int index) const { return __values[index]; }",
			"  " + elementType + " unsafeGet(int index) const { return __values[index]; }",
			"  "
			+ elementType
			+ " unsafeSet(int index, "
			+ elementType
			+ " value) { __values[index] = value; return value; }",
			"  " + elementType + " get(int index) const { return unsafeGet(index); }",
			"  "
			+ elementType
			+ " set(int index, "
			+ elementType
			+ " value) { return unsafeSet(index, value); }",
			"  int get_length() const { return static_cast<int>(__values.size()); }",
			"  void fill(" + elementType + " value) { std::fill(__values.begin(), __values.end(), value); length = static_cast<int>(__values.size()); }",
			"  static void blit(const "
			+ className
			+ "& src, int srcPos, "
			+ className
			+ "& dest, int destPos, int len) {",
			"    for (int i = 0; i < len; i++) dest.__values[destPos + i] = src.__values[srcPos + i];",
			"    dest.length = static_cast<int>(dest.__values.size());",
			"  }",
			"  " + valueType + " toArray() const { return __values; }",
			"  " + valueType + " toData() const { return __values; }",
			"  static "
			+ className
			+ " fromData("
			+ valueType
			+ " data) { return "
			+ className
			+ "(data); }",
			"  static "
			+ className
			+ " fromArrayCopy("
			+ valueType
			+ " array) { return "
			+ className
			+ "(array); }",
			"  " + className + " copy() const { return " + className + "(__values); }",
			"  std::string join(std::string sep) const { return __hxhx_join(__values, sep); }",
			"  "
			+ className
			+ " map(std::function<"
			+ elementType
			+ "("
			+ elementType
			+ ")> f) const {",
			"    " + valueType + " out;",
			"    out.reserve(__values.size());",
			"    for (const auto& value : __values) out.push_back(f(value));",
			"    return " + className + "(out);",
			"  }",
			"  void sort(std::function<int(" + elementType + ", " + elementType + ")> f) {",
			"    std::sort(__values.begin(), __values.end(), [&](const auto& a, const auto& b) { return f(a, b) < 0; });",
			"  }",
			"  operator " + valueType + "() const { return __values; }",
			"};"
		];
	}

	static function renderRestSupportClass(cls:HxClassDecl):Array<String> {
		final typeParams = genericClassTemplateParams(cls);
		final itemType = typeParams.length > 0 ? typeParams[0] : "std::string";
		final template = typeParams.length > 0 ? [genericTemplatePrefix(typeParams)] : [];
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final vectorType = "std::vector<" + itemType + ">";
		return template.concat(["struct " + className + " {",
			"  " + vectorType + " __values;",
			"  int length = 0;",
			"  " + className + "() {}",
			"  "
			+ className
			+ "("
			+ vectorType
			+ " array) : __values(array), length(static_cast<int>(array.size())) {}",
			"  int get_length() const { return static_cast<int>(__values.size()); }",
			"  " + itemType + "& operator[](int index) { return __values[index]; }",
			"  const " + itemType + "& operator[](int index) const { return __values[index]; }",
			"  " + itemType + " get(int index) const { return __values[index]; }",
			"  " + vectorType + " copy() const { return __values; }",
			"  " + vectorType + " toArray() const { return __values; }",
			"  std::shared_ptr<RestIterator<" + itemType + ">> iterator() {",
			"    return __hxhx_make_shared_RestIterator<"
			+ itemType
			+ ">("
			+ CppRuntimeSupport.borrowedSharedPtrExpr("Rest<" + itemType + ">", "this")
			+ ");",
			"  }",
			"  std::shared_ptr<RestKeyValueIterator<" + itemType + ">> keyValueIterator() {",
			"    return __hxhx_make_shared_RestKeyValueIterator<"
			+ itemType
			+ ">("
			+ CppRuntimeSupport.borrowedSharedPtrExpr("Rest<" + itemType + ">", "this")
			+ ");",
			"  }",
			"  std::shared_ptr<Rest<" + itemType + ">> append(" + itemType + " item) const {",
			"    auto result = __values;",
			"    result.push_back(item);",
			"    return __hxhx_make_shared_Rest<" + itemType + ">(result);",
			"  }",
			"  std::shared_ptr<Rest<" + itemType + ">> prepend(" + itemType + " item) const {",
			"    auto result = __values;",
			"    result.insert(result.begin(), item);",
			"    return __hxhx_make_shared_Rest<" + itemType + ">(result);",
			"  }",
			"  std::string toString() const { return __hxhx_stringify(__values); }",
			"};",
			genericTemplatePrefix(typeParams),
			"std::shared_ptr<"
			+ className
			+ "<"
			+ typeParams.join(", ")
			+ ">> __hxhx_make_shared_"
			+ className
			+ "("
			+ vectorType
			+ " array) {",
			"  return std::make_shared<" + className + "<" + typeParams.join(", ") + ">>(array);",
			"}"
		]);
	}

	static function renderPrimitiveBackedAbstractClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final out = ["struct " + className + " {"];
		final scope = renderScope(cls, classLookup, "void");
		for (field in HxClassDecl.getFields(cls)) {
			if (!HxFieldDecl.getIsStatic(field))
				continue;
			final fieldName = sanitizeIdentifier(HxFieldDecl.getName(field));
			final typeName = knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
			final init = HxFieldDecl.getInit(field);
			final rhs = init == null ? cppDefaultValue(typeName, scope) : renderLocalInitExpr(init, typeName, typeName, scope);
			out.push("  inline static " + typeName + " " + fieldName + " = " + rhs + ";");
		}
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (!HxFunctionDecl.getIsStatic(fn) || HxFunctionDecl.getName(fn) == "new")
				continue;
			for (line in renderHelperMethod(fn, cls, classLookup))
				out.push(line);
		}
		out.push("};");
		return out;
	}

	static function knownStdlibFieldCppType(className:String, fieldName:String, typeHint:String, init:Null<HxExpr>, ?scope:CppRenderScope):String {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final field = sanitizeIdentifier(fieldName == null ? "" : fieldName);
		final explicit = StringTools.trim(typeHint == null ? "" : typeHint);
		final cacheKey = explicit.length > 0 ? fieldCppTypeCacheKey(className, field, explicit, scope) : "";
		if (cacheKey.length > 0) {
			final cached = fieldCppTypeCache.get(cacheKey);
			if (cached != null)
				return cached;
		}
		function cacheFieldType(typeName:String):String {
			if (cacheKey.length > 0)
				fieldCppTypeCache.set(cacheKey, typeName);
			return typeName;
		}
		if (owner == "EntryPoint" && field == "pending")
			return cacheFieldType("std::vector<std::function<void()>>");
		if (owner == "EntryPoint" && field == "sleepLock")
			return cacheFieldType("std::shared_ptr<Lock>");
		if (owner == "EntryPoint" && field == "mutex")
			return cacheFieldType("std::shared_ptr<Mutex>");
		if (owner == "EntryPoint" && field == "threadCount")
			return cacheFieldType("int");
		if (owner == "MainLoop" && field == "pending")
			return cacheFieldType("std::shared_ptr<MainEvent>");
		if (owner == "MainEvent" && (field == "prev" || field == "next"))
			return cacheFieldType("std::shared_ptr<MainEvent>");
		if (owner == "MainEvent" && field == "nextRun")
			return cacheFieldType("double");
		if (owner == "MainEvent" && field == "priority")
			return cacheFieldType("int");
		if (owner == "MainEvent" && field == "isMain")
			return cacheFieldType("bool");
		if (owner == "MainEvent" && field == "f")
			return cacheFieldType("std::function<void()>");
		if (owner == "Http" && (field == "onData" || field == "onError"))
			return cacheFieldType("std::function<void(std::string)>");
		if (owner == "Http" && field == "onBytes")
			return cacheFieldType("std::function<void(__hxhx_http_bytes)>");
		if (isStringIteratorHelper(owner) && (field == "offset" || field == "byteOffset" || field == "charOffset"))
			return cacheFieldType("int");
		if (owner == "Template") {
			return cacheFieldType(switch (field) {
				case "splitter" | "expr_splitter" | "expr_trim" | "expr_int" | "expr_float":
					"std::shared_ptr<EReg>";
				case "globals" | "context" | "macros":
					"std::string";
				case "hxKeepArrayIterator":
					"std::vector<std::string>";
				case _:
					cppTypeHint(typeHint, scope);
			});
		}
		if (field == "winMetaCharacters" && (owner == "SysTools" || owner == "StringTools"))
			return cacheFieldType("std::vector<int>");
		if (field == "__hx_enum_ctors" || isEnumMetadataAnonInit(init)) {
			final inferred = init == null ? "" : inferExprCppType(init, scope);
			if (inferred.length > 0)
				return inferred;
		}
		if (explicit.length > 0)
			return cacheFieldType(cppTypeHint(explicit, scope));
		final inferred = init == null ? "" : inferExprCppType(init, scope);
		return inferred.length > 0 ? inferred : cppTypeHint(typeHint, scope);
	}

	static function fieldCppTypeCacheKey(className:String, field:String, explicit:String, ?scope:CppRenderScope):String {
		return sanitizeTypePath(className == null ? "" : className)
			+ "."
			+ sanitizeIdentifier(field == null ? "" : field)
			+ "|hint="
			+ removeTypeHintWhitespace(explicit)
			+ "|hint_shape="
			+ typeHintScopeShapeCacheKey(explicit, scope)
			+ "|type_params="
			+ stringMapStableKey(scope == null ? null : scope.typeParamCppNames);
	}

	static function typeHintScopeShapeCacheKey(typeHint:String, ?scope:CppRenderScope):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0 || scope == null)
			return "";
		final lookup = lookupForScope(scope);
		final cls = CppTypeModel.lookupClassForTypeHint(hint, scope, lookup);
		if (cls == null)
			return "";
		final fields = [
			for (field in HxClassDecl.getFields(cls))
				(HxFieldDecl.getIsStatic(field) ? "static:" : "field:")
				+ sanitizeIdentifier(HxFieldDecl.getName(field))
				+ ":"
				+ removeTypeHintWhitespace(HxFieldDecl.getTypeHint(field))];
		return renderedClassName(cls, lookup) + "|meta=" + HxClassDecl.getMetadata(cls).join(",") + "|fields=" + fields.join(",");
	}

	static function isEnumMetadataAnonInit(init:Null<HxExpr>):Bool {
		return switch (init) {
			case EAnon(fieldNames, _):
				fieldNames.length >= 4
				&& fieldNames[0] == "__hx_enum"
				&& fieldNames[1] == "__hx_ctor"
				&& fieldNames[2] == "__hx_index"
				&& fieldNames[3] == "__hx_params";
			case _:
				false;
		};
	}

	static function knownStdlibMethodReturnCppType(className:String, methodName:String, typeHint:String, ?scope:CppRenderScope,
			?classLookup:CppClassLookup):String {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		final preludeReturn = cppPreludeMethodReturnType(owner, method);
		if (preludeReturn.length > 0)
			return preludeReturn;
		if (isStringIteratorHelper(owner)) {
			if ((owner == "StringIteratorUnicode" && method == "unicodeIterator")
				|| (owner == "StringKeyValueIteratorUnicode" && method == "unicodeKeyValueIterator"))
				return cppTypeHint(owner, scope, classLookup);
			if (method == "hasNext")
				return "bool";
			if (method == "next")
				return owner == "StringIterator" || owner == "StringIteratorUnicode" ? "int" : "auto";
		}
		if (owner == "BalancedTree") {
			final treeNode = cppTypeHint("TreeNode<K,V>", scope, classLookup);
			return switch (method) {
				case "setLoop" | "removeLoop" | "merge" | "minBinding" | "removeMinBinding" | "balance":
					treeNode;
				case "compare":
					"int";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Template") {
			return switch (method) {
				case "parse" | "parseBlock":
					cppTypeHint("TemplateExpr", scope, classLookup);
				case "parseTokens":
					cppTypeHint("List<Token>", scope, classLookup);
				case "parseExpr":
					cppTypeHint("Void->Dynamic", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Bytes")
			return switch (method) {
				case "fill":
					"void";
				case "toHex":
					"std::string";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			};
		if (isTypeResolverHelper(owner)) {
			return switch (method) {
				case "resolveClass":
					"std::shared_ptr<Class>";
				case "resolveEnum":
					"std::shared_ptr<Enum>";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "BaseCode") {
			return switch (method) {
				case "encodeBytes" | "decodeBytes":
					cppTypeHint("Bytes", scope, classLookup);
				case "encodeString" | "decodeString" | "encode" | "decode":
					"std::string";
				case "initTable":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Base64") {
			return switch (method) {
				case "encode" | "urlEncode":
					"std::string";
				case "decode" | "urlDecode":
					cppTypeHint("Bytes", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Resource") {
			return switch (method) {
				case "listNames":
					cppTypeHint("Array<String>", scope, classLookup);
				case "getString":
					"std::string";
				case "getBytes":
					cppTypeHint("Bytes", scope, classLookup);
				case "__init__":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "JsonParser") {
			return switch (method) {
				case "parse" | "doParse" | "parseRec" | "parseNumber":
					"std::any";
				case "parseString":
					"std::string";
				case "nextChar":
					"int";
				case "invalidChar" | "invalidNumber":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "JsonPrinter") {
			return switch (method) {
				case "print":
					"std::string";
				case "newl" | "write" | "addChar" | "add" | "classString" | "objString" | "fieldsString" | "quote" | "quoteUtf8":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Xml") {
			return switch (method) {
				case "parse" | "createElement" | "createPCData" | "createCData" | "createComment" | "createDocType" | "createProcessingInstruction" |
					"createDocument" | "firstChild" | "firstElement":
					cppTypeHint("Xml", scope, classLookup);
				case "get_nodeName" | "set_nodeName" | "get_nodeValue" | "set_nodeValue" | "get" | "toString":
					"std::string";
				case "set" | "remove" | "addChild" | "insertChild" | "ensureElementType":
					"void";
				case "exists" | "removeChild":
					"bool";
				case "attributes":
					cppTypeHint("Iterator<String>", scope, classLookup);
				case "iterator" | "elements" | "elementsNamed":
					cppTypeHint("Iterator<Xml>", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Md5") {
			return switch (method) {
				case "encode" | "hex":
					"std::string";
				case "make":
					cppTypeHint("Bytes", scope, classLookup);
				case "bytes2blks" | "str2blks" | "doEncode":
					"std::vector<int>";
				case "bitOR" | "bitXOR" | "bitAND" | "addme" | "rol" | "cmn" | "ff" | "gg" | "hh" | "ii":
					"int";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "EReg" && method == "matchedPos")
			return cppTypeHint("{pos:Int,len:Int}", scope, classLookup);
		if (owner == "Exception" && (method == "caught" || method == "thrown"))
			return "std::shared_ptr<Exception>";
		return StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? cppReturnTypeHint(typeHint, scope, classLookup) : "";
	}

	static function cppPreludeMethodReturnType(className:String, methodName:String):String {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		if (owner == "Timer" && method == "stamp")
			return "double";
		if (owner == "Timer" && method == "delay")
			return "std::shared_ptr<Timer>";
		if (owner == "Timer" && method == "stop")
			return "void";
		if (owner == "Http" && (method == "setPostData" || method == "setPostBytes" || method == "request"))
			return "void";
		if (owner == "Lock" && (method == "acquire" || method == "release"))
			return "void";
		if (owner == "Lock" && method == "wait")
			return "bool";
		if (owner == "Mutex" && (method == "acquire" || method == "release"))
			return "void";
		if (owner == "Mutex" && method == "tryAcquire")
			return "bool";
		if (owner == "MainLoop" && method == "add")
			return "std::shared_ptr<MainEvent>";
		if (owner == "MainLoop" && method == "hasEvents")
			return "bool";
		if (owner == "MainLoop" && method == "tick")
			return "double";
		if (owner == "MainLoop" && method == "sortEvents")
			return "void";
		if (owner == "MainEvent" && (method == "delay" || method == "stop" || method == "wakeup"))
			return "void";
		if (owner == "EntryPoint" && (method == "wakeup" || method == "runInMainThread" || method == "addThread"))
			return "void";
		if (owner == "EntryPoint" && method == "processEvents")
			return "double";
		return "";
	}

	static function cppPreludeMethodParamTypes(className:String, methodName:String):Array<String> {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		if (owner == "Timer" && method == "delay")
			return ["std::function<void()>", "double"];
		if (owner == "MainLoop" && method == "add")
			return ["std::function<void()>", "int"];
		if (owner == "EntryPoint" && (method == "runInMainThread" || method == "addThread"))
			return ["std::function<void()>"];
		if (owner == "Http" && method == "setPostData")
			return ["std::string"];
		return [];
	}

	static function knownStdlibMethodParamCppTypes(className:String, methodName:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Array<String> {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		return switch (owner) {
			case "Bytes":
				switch (method) {
					case "alloc":
						["int"];
					case "ofString" | "ofHex":
						["std::string"];
					case "ofData":
						["std::vector<int>"];
					case "fastGet":
						["std::vector<int>", "int"];
					case _:
						[];
				}
			case "Base64":
				final bytesType = cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encode" | "urlEncode":
						[bytesType, "bool"];
					case "decode" | "urlDecode":
						["std::string", "bool"];
					case _:
						[];
				}
			case "BaseCode":
				final bytesType = cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encodeBytes" | "decodeBytes":
						[bytesType];
					case "encodeString" | "decodeString":
						["std::string"];
					case "encode" | "decode":
						["std::string", "std::string"];
					case _:
						[];
				}
			case "Resource":
				switch (method) {
					case "getString" | "getBytes":
						["std::string"];
					case _:
						[];
				}
			case "JsonParser":
				switch (method) {
					case "parse":
						["std::string"];
					case "parseNumber" | "invalidNumber":
						["int"];
					case _:
						[];
				}
			case "JsonPrinter":
				final jsonPrinterReplacerType = "std::function<std::any(std::any, std::any)>";
				switch (method) {
					case "print":
						["std::any", jsonPrinterReplacerType, "std::optional<std::string>"];
					case "write":
						["std::any", "std::any"];
					case "addChar":
						["int"];
					case "add" | "quote" | "quoteUtf8":
						["std::string"];
					case "classString" | "objString":
						["std::any"];
					case "fieldsString":
						["std::any", "std::vector<std::string>"];
					case _:
						[];
				}
			case "Xml":
				final xmlType = cppTypeHint("Xml", scope, classLookup);
				switch (method) {
					case "parse" | "createElement" | "createPCData" | "createCData" | "createComment" | "createDocType" | "createProcessingInstruction" |
						"set_nodeName" | "set_nodeValue" | "get" | "remove" | "exists" | "elementsNamed":
						["std::string"];
					case "set":
						["std::string", "std::string"];
					case "addChild" | "removeChild":
						[xmlType];
					case "insertChild":
						[xmlType, "int"];
					case _:
						[];
				}
			case "Md5":
				final bytesType = cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encode":
						["std::string"];
					case "make":
						[bytesType];
					case _:
						[];
				}
			case "TypeResolver" | "DefaultResolver":
				switch (method) {
					case "resolveClass" | "resolveEnum":
						["std::string"];
					case _:
						[];
				}
			case _:
				[];
		}
	}

	static function knownStdlibConstructorParamCppTypes(className:String):Array<String> {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		return switch (owner) {
			case "JsonParser":
				["std::string"];
			case "JsonPrinter":
				["std::function<std::any(std::any, std::any)>", "std::string"];
			case _:
				[];
		}
	}

	static function applyKnownStdlibFunctionArgOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || scope.owner == null || fn == null)
			return;
		final ownerName = HxClassDecl.getName(scope.owner);
		final methodName = HxFunctionDecl.getName(fn);
		final knownTypes = sanitizeIdentifier(methodName) == "new" ? knownStdlibConstructorParamCppTypes(ownerName) : knownStdlibMethodParamCppTypes(ownerName,
			methodName, scope, scope.classLookup);
		if (knownTypes.length == 0)
			return;
		final args = HxFunctionDecl.getArgs(fn);
		for (i in 0...args.length) {
			if (i >= knownTypes.length)
				break;
			final typeName = knownTypes[i];
			if (typeName != null && typeName.length > 0)
				scope.argTypeOverrides.set(sanitizeIdentifier(HxFunctionArg.getName(args[i])), typeName);
		}
	}

	static function isStringIteratorHelper(className:String):Bool {
		return className == "StringIterator"
			|| className == "StringIteratorUnicode"
			|| className == "StringKeyValueIterator"
			|| className == "StringKeyValueIteratorUnicode";
	}

	static function isTypeResolverHelper(className:String):Bool {
		final owner = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		return owner == "TypeResolver" || owner == "DefaultResolver";
	}

	static function renderScope(cls:HxClassDecl, classLookup:CppClassLookup, returnType:String):CppRenderScope {
		final typeParams = genericClassTemplateParams(cls);
		final typeParamCppNames = new haxe.ds.StringMap<String>();
		for (param in typeParams) {
			final clean = sanitizeIdentifier(param);
			if (clean.length > 0)
				typeParamCppNames.set(clean, clean);
		}
		return {
			owner: cls,
			classNames: classLookup.names,
			classByName: classLookup.byName,
			allClasses: classLookup.all == null ? [] : classLookup.all,
			classLookup: classLookup,
			typeParams: typeParams,
			typeParamCppNames: typeParamCppNames,
			localTypes: new haxe.ds.StringMap<String>(),
			localTypeHints: new haxe.ds.StringMap<String>(),
			localNames: new haxe.ds.StringMap<String>(),
			localNameCounts: new haxe.ds.StringMap<Int>(),
			argTypeOverrides: new haxe.ds.StringMap<String>(),
			localTypeOverrides: new haxe.ds.StringMap<String>(),
			anonStructs: new haxe.ds.StringMap<CppAnonStruct>(),
			returnType: returnType,
			returnOnlyTypeParamAuto: false
		};
	}

	static function registerFunctionArgs(scope:CppRenderScope, args:Array<HxFunctionArg>):Void {
		if (scope == null || args == null)
			return;
		for (arg in args) {
			final name = sanitizeIdentifier(HxFunctionArg.getName(arg));
			scope.localTypes.set(name, cppFunctionArgType(arg, scope));
			recordLocalTypeHint(scope, name, HxFunctionArg.getTypeHint(arg));
			scope.localNames.set(name, name);
			scope.localNameCounts.set(name, 1);
		}
	}

	static function applyFunctionScopePrep(scope:CppRenderScope, prep:CppFunctionScopePrep):Void {
		if (scope == null || prep == null)
			return;
		for (name in prep.argTypeOverrides.keys())
			scope.argTypeOverrides.set(name, prep.argTypeOverrides.get(name));
		for (name in prep.localTypeOverrides.keys())
			scope.localTypeOverrides.set(name, prep.localTypeOverrides.get(name));
	}

	static function applyCachedFunctionArgRegistration(scope:CppRenderScope, prep:CppFunctionScopePrep):Void {
		if (scope == null || prep == null)
			return;
		for (name in prep.argLocalTypes.keys())
			scope.localTypes.set(name, prep.argLocalTypes.get(name));
		for (name in prep.argLocalTypeHints.keys())
			scope.localTypeHints.set(name, prep.argLocalTypeHints.get(name));
		for (name in prep.argLocalNames.keys())
			scope.localNames.set(name, prep.argLocalNames.get(name));
		for (name in prep.argLocalNameCounts.keys())
			scope.localNameCounts.set(name, prep.argLocalNameCounts.get(name));
	}

	static function snapshotFunctionScopePrep(scope:CppRenderScope, args:Array<HxFunctionArg>):CppFunctionScopePrep {
		final argLocalTypes = new haxe.ds.StringMap<String>();
		final argLocalTypeHints = new haxe.ds.StringMap<String>();
		final argLocalNames = new haxe.ds.StringMap<String>();
		final argLocalNameCounts = new haxe.ds.StringMap<Int>();
		if (scope != null && args != null) {
			for (arg in args) {
				final name = sanitizeIdentifier(HxFunctionArg.getName(arg));
				if (scope.localTypes.exists(name))
					argLocalTypes.set(name, scope.localTypes.get(name));
				if (scope.localTypeHints.exists(name))
					argLocalTypeHints.set(name, scope.localTypeHints.get(name));
				if (scope.localNames.exists(name))
					argLocalNames.set(name, scope.localNames.get(name));
				if (scope.localNameCounts.exists(name))
					argLocalNameCounts.set(name, scope.localNameCounts.get(name));
			}
		}
		return {
			argTypeOverrides: copyStringMap(scope.argTypeOverrides),
			localTypeOverrides: copyStringMap(scope.localTypeOverrides),
			argLocalTypes: argLocalTypes,
			argLocalTypeHints: argLocalTypeHints,
			argLocalNames: argLocalNames,
			argLocalNameCounts: argLocalNameCounts
		};
	}

	static function prepareFunctionScope(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		final prepOwnerName = scope.owner == null ? "" : HxClassDecl.getName(scope.owner);
		final prepMethodName = HxFunctionDecl.getName(fn);
		final prepTimingEnabled = traceCppMethodStmtTimingsEnabled(prepOwnerName, prepMethodName);
		final prepStartTime = prepTimingEnabled ? Sys.time() : 0.0;
		function tracePrepPhase(phase:String, elapsed:Float):Void {
			traceCppTimingPhase("render_helper_method_prepare_timing owner=" + sanitizeTypePath(typeBaseName(prepOwnerName)) + " name="
				+ sanitizeIdentifier(prepMethodName) + " phase=" + phase + " seconds=" + Std.string(elapsed));
		}
		function tracePrepCounts(phase:String):Void {
			traceCppTimingPhase("render_helper_method_prepare_counts owner=" + sanitizeTypePath(typeBaseName(prepOwnerName)) + " name="
				+ sanitizeIdentifier(prepMethodName) + " phase=" + phase + " arg_overrides=" + Std.string(countStringMap(scope.argTypeOverrides))
				+ " local_overrides=" + Std.string(countStringMap(scope.localTypeOverrides)) + " local_types=" + Std.string(countStringMap(scope.localTypes))
				+ " arg_override_values=" + summarizeStringValueMap(scope.argTypeOverrides) + " local_override_values="
				+ summarizeStringValueMap(scope.localTypeOverrides));
		}
		function runPrepPhase(phase:String, body:Void->Void):Void {
			if (!prepTimingEnabled) {
				body();
				return;
			}
			final startTime = Sys.time();
			body();
			tracePrepPhase(phase, Sys.time() - startTime);
			tracePrepCounts(phase);
		}
		runPrepPhase("return_auto", () -> {
			scope.returnOnlyTypeParamAuto = functionReturnTypeParamShouldUseAuto(HxFunctionDecl.getReturnTypeHint(fn), fn)
				&& !functionReturnsOnlyNull(fn);
		});
		runPrepPhase("type_params", () -> applyFunctionTypeParams(scope, fn));
		final key = functionSignatureKeyForScope(scope, fn);
		final cached = functionScopePrepCache.get(key);
		if (cached != null) {
			runPrepPhase("cache_apply", () -> applyFunctionScopePrep(scope, cached));
			runPrepPhase("register_args", () -> applyCachedFunctionArgRegistration(scope, cached));
			if (prepTimingEnabled)
				tracePrepPhase("total_cache_hit", Sys.time() - prepStartTime);
			return;
		}
		if (functionScopePrepStack.exists(key)) {
			runPrepPhase("register_args", () -> registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn)));
			if (prepTimingEnabled)
				tracePrepPhase("total_recursive", Sys.time() - prepStartTime);
			return;
		}
		functionScopePrepStack.set(key, true);
		try {
			runPrepPhase("known_arg_types", () -> applyKnownStdlibFunctionArgOverrides(scope, fn));
			runPrepPhase("infer_callable_args", () -> {
				if (!knownStdlibMethodUsesDeclaredCallableArgs(scope, fn))
					inferCallableArgTypeOverrides(scope, fn);
			});
			runPrepPhase("register_args", () -> registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn)));
			runPrepPhase("infer_string_map_locals", () -> {
				if (!knownMethodSkipsPrepLocalInference(scope, fn, "infer_string_map_locals"))
					inferStringMapLocalTypeOverrides(scope, fn);
			});
			runPrepPhase("infer_generic_factory_locals", () -> {
				if (!knownMethodSkipsPrepLocalInference(scope, fn, "infer_generic_factory_locals"))
					inferGenericFactoryLocalTypeOverrides(scope, fn);
			});
			runPrepPhase("infer_dynamic_locals", () -> {
				if (!knownMethodSkipsPrepLocalInference(scope, fn, "infer_dynamic_locals"))
					inferDynamicLocalTypeOverrides(scope, fn);
			});
			runPrepPhase("infer_helper_typed_as_locals", () -> {
				if (!knownMethodSkipsPrepLocalInference(scope, fn, "infer_helper_typed_as_locals"))
					inferHelperTypedAsLocalTypeOverrides(scope, fn);
			});
			runPrepPhase("infer_return_locals", () -> inferReturnLocalTypeOverrides(scope, fn));
		} catch (e:haxe.Exception) {
			functionScopePrepStack.remove(key);
			throw e;
		} catch (e:String) {
			functionScopePrepStack.remove(key);
			throw e;
		}
		runPrepPhase("cache_store", () -> functionScopePrepCache.set(key, snapshotFunctionScopePrep(scope, HxFunctionDecl.getArgs(fn))));
		functionScopePrepStack.remove(key);
		if (prepTimingEnabled)
			tracePrepPhase("total_cache_miss", Sys.time() - prepStartTime);
	}

	static function knownStdlibMethodUsesDeclaredCallableArgs(scope:CppRenderScope, fn:HxFunctionDecl):Bool {
		if (scope == null || scope.owner == null || fn == null)
			return false;
		final owner = sanitizeTypePath(typeBaseName(HxClassDecl.getName(scope.owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (owner) {
			case "JsonParser":
				switch (method) {
					case "parse" | "new" | "doParse" | "parseRec" | "parseString" | "parseNumber" | "nextChar" | "invalidChar" | "invalidNumber":
						true;
					case _:
						false;
				}
			case "JsonPrinter":
				switch (method) {
					case "print" | "new" | "newl" | "write" | "addChar" | "add" | "classString" | "objString" | "fieldsString" | "quote" | "quoteUtf8":
						true;
					case _:
						false;
				}
			case "Xml":
				switch (method) {
					case "parse" | "get_nodeName" | "set_nodeName" | "get_nodeValue" | "set_nodeValue" | "createElement" | "createPCData" | "createCData" |
						"createComment" | "createDocType" | "createProcessingInstruction" | "createDocument" | "get" | "set" | "remove" | "exists" |
						"attributes" | "iterator" | "elements" | "elementsNamed" | "firstChild" | "firstElement" | "addChild" | "removeChild" |
						"insertChild" | "toString" | "ensureElementType":
						true;
					case _:
						false;
				}
			case "TypeResolver" | "DefaultResolver":
				switch (method) {
					case "resolveClass" | "resolveEnum":
						true;
					case _:
						false;
				}
			case _:
				false;
		}
	}

	static function knownMethodSkipsPrepLocalInference(scope:CppRenderScope, fn:HxFunctionDecl, phase:String):Bool {
		if (scope == null || scope.owner == null || fn == null)
			return false;
		final owner = sanitizeTypePath(typeBaseName(HxClassDecl.getName(scope.owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (owner) {
			case "Unserializer": method == "unserialize" && (phase == "infer_string_map_locals" || phase == "infer_generic_factory_locals");
			case "TestType": method == "testInlineCast" && (phase == "infer_string_map_locals"
					|| phase == "infer_generic_factory_locals"
					|| phase == "infer_dynamic_locals"
					|| phase == "infer_helper_typed_as_locals");
			case _:
				false;
		};
	}

	static function prepareFunctionSignatureScope(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		applyFunctionTypeParams(scope, fn);
		registerFunctionArgs(scope, HxFunctionDecl.getArgs(fn));
	}

	static function baseTypeName(cls:HxClassDecl):Null<String> {
		final extendsPath = HxClassDecl.getExtendsPath(cls);
		if (extendsPath == null || extendsPath.length == 0)
			return null;
		return sanitizeTypePath(typeBaseName(extendsPath));
	}

	static function inheritedCppBaseTypeName(cls:HxClassDecl, classLookup:CppClassLookup):Null<String> {
		final extendsPath = HxClassDecl.getExtendsPath(cls);
		if (extendsPath == null || extendsPath.length == 0)
			return null;
		final scope = renderScope(cls, classLookup, "void");
		final baseCls = lookupClassForTypeHint(extendsPath, scope, classLookup);
		if (baseCls != null && genericTypeHintArgs(extendsPath).length == 0) {
			final rendered = renderedClassName(baseCls, classLookup);
			if (rendered != sanitizeTypePath(HxClassDecl.getName(baseCls)))
				return rendered;
		}
		return cppClassTemplateTypeName(extendsPath, scope, classLookup);
	}

	static function inheritedCppBaseTypes(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final bases = new Array<String>();
		final baseType = inheritedCppBaseTypeName(cls, classLookup);
		if (baseType != null && baseType.length > 0)
			bases.push("public " + baseType);
		final scope = renderScope(cls, classLookup, "void");
		final seen = new haxe.ds.StringMap<Bool>();
		function addBase(iface:String, ifaceCls:Null<HxClassDecl>):Void {
			if (iface.length == 0 || seen.exists(iface) || !shouldInheritCppInterface(iface, ifaceCls, classLookup))
				return;
			seen.set(iface, true);
			bases.push("public " + iface);
		}
		for (path in HxClassDecl.getImplementsPaths(cls)) {
			final ifaceCls = lookupClassForTypeHint(path, scope, classLookup);
			final iface = ifaceCls == null ? genericClassLikeTypeName(path, scope, classLookup) : cppClassTemplateTypeName(path, scope, classLookup);
			addBase(iface, ifaceCls);
		}
		for (iface in syntheticStructuralInterfaceNames(cls, classLookup))
			addBase(iface, lookupClassForTypeHint(iface, scope, classLookup));
		return bases;
	}

	static function shouldInheritCppInterface(name:String, ?ifaceCls:HxClassDecl, ?classLookup:CppClassLookup):Bool {
		if (isTargetOwnedCppInterface(name, ifaceCls, classLookup))
			return false;
		return true;
	}

	static function isTargetOwnedCppInterface(name:String, ?ifaceCls:HxClassDecl, ?classLookup:CppClassLookup):Bool {
		final path = sanitizeTypePath(typeHintPathPart(name == null ? "" : name));
		final base = sanitizeTypePath(typeBaseName(typeHintPathPart(name == null ? "" : name)));
		if (base == "IReport" || base == "IMap" || path == "Constraints_IMap" || path == "haxe_Constraints_IMap")
			return true;
		if (ifaceCls == null)
			return false;
		final rendered = renderedClassName(ifaceCls, classLookup);
		final rawName = sanitizeTypePath(HxClassDecl.getName(ifaceCls));
		final rawBase = sanitizeTypePath(typeBaseName(HxClassDecl.getName(ifaceCls)));
		return rendered == "haxe_Constraints_IMap" || rendered == "Constraints_IMap" || rawName == "haxe_Constraints_IMap" || rawName == "Constraints_IMap"
			|| rawBase == "IMap";
	}

	static function implementedInterfaceNames(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final out = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();
		final scope = renderScope(cls, classLookup, "void");
		function add(name:String):Void {
			final ifaceCls = lookupClassForTypeHint(name, scope, classLookup);
			final clean = ifaceCls == null ? genericClassLikeTypeName(name, scope, classLookup) : cppClassTemplateTypeName(name, scope, classLookup);
			if (clean.length == 0 || seen.exists(clean))
				return;
			seen.set(clean, true);
			out.push(clean);
		}
		for (path in HxClassDecl.getImplementsPaths(cls))
			add(path);
		for (name in syntheticStructuralInterfaceNames(cls, classLookup))
			add(name);
		return out;
	}

	static function cppClassTemplateTypeName(typeHint:String, scope:CppRenderScope, classLookup:CppClassLookup):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final lookup = lookupForScope(scope, classLookup);
		final cls = lookupClassForTypeHint(hint, scope, lookup);
		final base = cls == null ? sanitizeTypePath(typeBaseName(hint)) : renderedClassName(cls, lookup);
		final args = genericTypeHintArgs(hint);
		if (args.length == 0) {
			final scoped = scopedRawGenericClassTypeName(hint, scope);
			return scoped == null ? base : scoped;
		}
		return base + "<" + [for (arg in args) cppTypeHint(arg, scope, lookup)].join(", ") + ">";
	}

	static function genericClassLikeTypeName(typeHint:String, scope:CppRenderScope, classLookup:CppClassLookup):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final base = sanitizeTypePath(typeBaseName(hint));
		final args = genericTypeHintArgs(hint);
		return args.length == 0 ? base : base + "<" + [for (arg in args) cppTypeHint(arg, scope, classLookup)].join(", ") + ">";
	}

	static function syntheticStructuralInterfaceNames(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final className = sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls)));
		return switch (className) {
			case "MapKeyValueIterator" | "HashMapKeyValueIterator" | "ListKeyValueIterator" | "ArrayKeyValueIterator" | "RestKeyValueIterator" |
				"StringKeyValueIterator" | "StringKeyValueIteratorUnicode" | "DynamicAccessKeyValueIterator":
				["KeyValueIterator"];
			case _:
				[];
		};
	}

	static function renderHelperMethod(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final ownerName = sanitizeTypePath(HxClassDecl.getName(owner));
		final methodName = HxFunctionDecl.getName(fn);
		function returnTraced(stage:String, lines:Array<String>):Array<String> {
			traceCppMemberPhase(ownerName, "render_helper_method", methodName, stage);
			traceCppMemberPhase(ownerName, "render_helper_method", methodName, "end");
			return lines;
		}
		traceCppMemberPhase(ownerName, "render_helper_method", methodName, "begin");
		if (isRttiMetaHelper(fn, owner))
			return returnTraced("special_rtti_meta", renderRttiMetaHelper(fn, owner, classLookup));
		if (isAssertPolymorphicStringifyHelper(fn, owner))
			return returnTraced("special_assert_stringify", renderAssertPolymorphicStringifyHelper(fn));
		if (isAssertPolymorphicSameHelper(fn, owner))
			return returnTraced("special_assert_same", renderAssertPolymorphicSameHelper(fn, owner, classLookup));
		if (isAssertPolymorphicSameAsHelper(fn, owner))
			return returnTraced("special_assert_same_as", renderAssertPolymorphicSameAsHelper(fn, owner, classLookup));
		if (isUtestEqHelper(fn, owner))
			return returnTraced("special_utest_eq", renderUtestEqHelper(fn));
		if (isLambdaHasHelper(fn, owner))
			return returnTraced("special_lambda_has", renderLambdaHasHelper());
		if (isSysToolsSupportHelper(fn, owner))
			return returnTraced("special_sys_tools", renderSysToolsSupportHelper(fn, owner, classLookup));
		if (isStringToolsSupportHelper(fn, owner))
			return returnTraced("special_string_tools", renderStringToolsSupportHelper(fn, owner, classLookup));
		if (isBaseCodeSupportHelper(fn, owner))
			return returnTraced("special_basecode", renderBaseCodeSupportHelper(fn, owner, classLookup));
		if (isBase64SupportHelper(fn, owner))
			return returnTraced("special_base64", renderBase64SupportHelper(fn, owner, classLookup));
		if (isResourceSupportHelper(fn, owner))
			return returnTraced("special_resource", renderResourceSupportHelper(fn, owner, classLookup));
		if (isBytesSupportHelper(fn, owner))
			return returnTraced("special_bytes", renderBytesSupportHelper(fn, owner, classLookup));
		if (isUnserializerObjectHelper(fn, owner))
			return returnTraced("special_unserializer_object", renderUnserializerObjectHelper(fn, owner, classLookup));
		if (isUnserializerEnumHelper(fn, owner))
			return returnTraced("special_unserializer_enum", renderUnserializerEnumHelper(fn, owner, classLookup));
		if (isMd5SupportHelper(fn, owner))
			return returnTraced("special_md5", renderMd5SupportHelper(fn, owner, classLookup));
		if (isSha1SupportHelper(fn, owner))
			return returnTraced("special_sha1", renderSha1SupportHelper(fn, owner, classLookup));
		if (isHelperMacrosShimHelper(fn, owner))
			return returnTraced("special_helper_macros", renderHelperMacrosShimHelper(fn, owner, classLookup));
		if (isMacroStringToolsShimHelper(fn, owner))
			return returnTraced("special_macro_string_tools", renderMacroStringToolsShimHelper(fn, owner, classLookup));
		if (isMacroCompilerApiShimHelper(fn, owner))
			return returnTraced("special_macro_compiler_api", renderMacroCompilerApiShimHelper(fn, owner, classLookup));
		if (isExceptionCaughtThrownHelper(fn, owner))
			return returnTraced("special_exception_caught_thrown", renderExceptionCaughtThrownHelper(fn, owner, classLookup));
		if (isPosExceptionToStringHelper(fn, owner))
			return returnTraced("special_pos_exception_to_string", renderPosExceptionToStringHelper(fn, owner, classLookup));
		if (isTestExceptionsStackItemDataHelper(fn, owner))
			return returnTraced("special_test_exceptions_stack_item_data", renderTestExceptionsStackItemDataHelper(fn, owner, classLookup));
		if (isUtestRunnerAddCasesHelper(fn, owner))
			return returnTraced("special_utest_runner_add_cases", renderUtestRunnerAddCasesHelper(fn, owner, classLookup));
		if (isUtestCallbackHelper(fn, owner))
			return returnTraced("special_utest_callback", renderUtestCallbackHelper(fn, owner, classLookup));
		if (isUtestResultAggregationHelper(fn, owner))
			return returnTraced("special_utest_result_aggregation", renderUtestResultAggregationHelper(fn, owner, classLookup));
		if (isCppLibReportHelper(fn, owner))
			return returnTraced("special_cpp_lib_report", renderCppLibReportHelper(fn, owner, classLookup));
		if (isPolymorphicIsOfTypeHelper(fn))
			return returnTraced("special_is_of_type", renderPolymorphicIsOfTypeHelper(fn, owner, classLookup));
		if (isTypeToolsFindFieldHelper(fn, owner))
			return returnTraced("special_typetools_find_field", renderTypeToolsFindFieldHelper(fn, owner, classLookup));
		if (isTypeToolsTraversalHelper(fn, owner))
			return returnTraced("special_typetools_traversal", renderTypeToolsTraversalHelper(fn, owner, classLookup));
		if (isExprToolsHelper(fn, owner))
			return returnTraced("special_exprtools", renderExprToolsHelper(fn, owner, classLookup));
		if (isPrinterComplexTypeHelper(fn, owner))
			return returnTraced("special_printer_complex_type", renderPrinterComplexTypeHelper(fn, owner, classLookup));
		if (isPrinterFieldHelper(fn, owner))
			return returnTraced("special_printer_field", renderPrinterFieldHelper(fn, owner, classLookup));
		if (isPrinterTypeParamFunctionHelper(fn, owner))
			return returnTraced("special_printer_type_param_function", renderPrinterTypeParamFunctionHelper(fn, owner, classLookup));
		if (isPrinterVarObjectExprHelper(fn, owner))
			return returnTraced("special_printer_var_object_expr", renderPrinterVarObjectExprHelper(fn, owner, classLookup));
		if (isPrinterTypeDefinitionHelper(fn, owner))
			return returnTraced("special_printer_type_definition", renderPrinterTypeDefinitionHelper(fn, owner, classLookup));
		if (isPrinterFieldDelimiterHelper(fn, owner))
			return returnTraced("special_printer_field_delimiter", renderPrinterFieldDelimiterHelper(fn, owner, classLookup));
		if (isPrinterExprPositionsHelper(fn, owner))
			return returnTraced("special_printer_expr_positions", renderPrinterExprPositionsHelper(fn, owner, classLookup));
		if (isTypeErasedValueHelper(fn, owner))
			return returnTraced("special_type_erased_value", renderTypeErasedValueHelper(fn, owner, classLookup));
		if (isPrimitiveStringRepeatHelper(fn, owner))
			return returnTraced("special_primitive_string_repeat", renderPrimitiveStringRepeatHelper(fn, owner, classLookup));
		final returnType = cppMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionScope(scope, fn);
		traceCppMemberPhase(ownerName, "render_helper_method", methodName, "after_prepare");
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		if (methodTypeParams.length > 0)
			out.push("  " + genericTemplatePrefix(methodTypeParams));
		out.push("  " + (HxFunctionDecl.getIsStatic(fn) ? "static " : "") + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") {");
		traceCppMemberPhase(ownerName, "render_helper_method", methodName, "after_signature");
		final body = if (traceCppMethodStmtTimingsEnabled(ownerName,
			methodName)) renderTimedHelperFunctionBody(ownerName, methodName, HxFunctionDecl.getBody(fn), "    ",
				scope); else if (traceCppDeepEnabled()) renderTracedHelperFunctionBody(ownerName, methodName, HxFunctionDecl.getBody(fn), "    ",
			scope); else renderHelperFunctionBody(HxFunctionDecl.getBody(fn), "    ", scope);
		for (line in body)
			out.push(line);
		out.push("  }");
		for (line in renderDceReflectionHelperStringOverload(fn, scope, returnType))
			out.push(line);
		traceCppMemberPhase(ownerName, "render_helper_method", methodName, "end");
		return out;
	}

	/**
		Emit the narrow fallback overload for DCE reflection helpers.

		The primary C++ seam is call-site lowering: class literals passed to
		`hf`/`nhf` Class parameters render as `Type::resolveClass("Path")`.
		Some inherited DCE helper surfaces can still reach generated C++ through
		string-shaped carriers after helper metadata is unavailable. Keep that
		recovery at the helper boundary, resolve the string back to a Class
		meta-value once, and do not generalize this to arbitrary reflection calls.
	**/
	static function renderDceReflectionHelperStringOverload(fn:HxFunctionDecl, scope:CppRenderScope, returnType:String):Array<String> {
		final methodName = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		if ((methodName != "hf" && methodName != "nhf") || HxFunctionDecl.getIsStatic(fn) || returnType != "void")
			return [];
		final args = HxFunctionDecl.getArgs(fn);
		if (args.length < 2 || args.length > 3)
			return [];
		if (cppFunctionArgType(args[0], scope) != "std::shared_ptr<Class>" || cppFunctionArgType(args[1], scope) != "std::string")
			return [];
		final arg0Name = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final arg1Name = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final overloadArgs = ["std::string " + arg0Name, "std::string " + arg1Name];
		final forwardedArgs = ["Type::resolveClass(" + arg0Name + ")", arg1Name];
		if (args.length == 3) {
			final arg2Type = cppFunctionArgType(args[2], scope);
			if (arg2Type != "std::optional<PosInfos>" && arg2Type != "std::shared_ptr<PosInfos>")
				return [];
			final arg2Name = sanitizeIdentifier(HxFunctionArg.getName(args[2]));
			overloadArgs.push(arg2Type + " " + arg2Name + cppFunctionArgDefaultSuffix(args[2], arg2Type));
			forwardedArgs.push(arg2Name);
		}
		return ["  void " + methodName + "(" + overloadArgs.join(", ") + ") {",
			"    "
			+ methodName
			+ "("
			+ forwardedArgs.join(", ")
			+ ");",
			"  }"
		];
	}

	static function isPrimitiveStringRepeatHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "repeat")
			return false;
		if (primitiveAbstractUnderlyingCppType(owner) != "int")
			return false;
		final args = HxFunctionDecl.getArgs(fn);
		if (args.length != 2)
			return false;
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		return sanitizeTypePath(typeBaseName(HxFunctionArg.getTypeHint(args[0]))) == ownerName
			&& cppTypeHint(HxFunctionArg.getTypeHint(args[1]), null,
				{names: new haxe.ds.StringMap<Bool>(), byName: new haxe.ds.StringMap<HxClassDecl>()}) == "std::string"
			&& cppTypeHint(HxFunctionDecl.getReturnTypeHint(fn), null,
				{names: new haxe.ds.StringMap<Bool>(), byName: new haxe.ds.StringMap<HxClassDecl>()}) == "std::string";
	}

	static function renderPrimitiveStringRepeatHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		return ["  static "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {",
			"    std::string out;",
			"    for (int i = 0; i < "
			+ sanitizeIdentifier(HxFunctionArg.getName(args[0]))
			+ "; ++i) out += "
			+ sanitizeIdentifier(HxFunctionArg.getName(args[1]))
			+ ";",
			"    return out;",
			"  }"
		];
	}

	static function isRttiMetaHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Meta")
			return false;
		if (!hasRttiMetaAccessorSurface(owner))
			return false;
		if (!HxFunctionDecl.getIsStatic(fn) || HxFunctionDecl.getArgs(fn).length != 1)
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "getMeta" | "getFields" | "getStatics" | "getType":
				true;
			case _:
				false;
		};
	}

	static function hasRttiMetaAccessorSurface(owner:HxClassDecl):Bool {
		final found = new haxe.ds.StringMap<Bool>();
		for (candidate in HxClassDecl.getFunctions(owner)) {
			if (!HxFunctionDecl.getIsStatic(candidate) || HxFunctionDecl.getArgs(candidate).length != 1)
				continue;
			found.set(sanitizeIdentifier(HxFunctionDecl.getName(candidate)), true);
		}
		return found.exists("getMeta") && found.exists("getFields") && found.exists("getStatics") && found.exists("getType");
	}

	static function renderRttiMetaHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final target = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final call = switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "getMeta":
				"__hxhx_meta_get_as<" + returnType + ">(" + target + ")";
			case "getFields":
				"__hxhx_meta_section_as<" + returnType + ">(" + target + ", std::string(\"fields\"))";
			case "getStatics":
				"__hxhx_meta_section_as<" + returnType + ">(" + target + ", std::string(\"statics\"))";
			case "getType":
				"__hxhx_meta_section_as<" + returnType + ">(" + target + ", std::string(\"obj\"))";
			case _:
				cppDefaultValue(returnType, scope);
		};
		return ["  template<typename T>",
			"  static "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "(const T& "
			+ target
			+ ") {",
			"    return " + call + ";",
			"  }"
		];
	}

	static function isLambdaHasHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Lambda")
			return false;
		return HxFunctionDecl.getIsStatic(fn)
			&& sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "has"
			&& HxFunctionDecl.getArgs(fn).length == 2;
	}

	static function renderLambdaHasHelper():Array<String> {
		return [
			"  template<typename A>",
			"  static bool has(const std::vector<A>& it, typename std::vector<A>::value_type elt) {",
			"    for (const auto& x : it) {",
			"      if (x == elt) return true;",
			"    }",
			"    return false;",
			"  }"
		];
	}

	static function isStringToolsSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "StringTools")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "urlEncode" | "urlDecode" | "htmlEscape" | "htmlUnescape" | "contains" | "startsWith" | "endsWith" | "isSpace" | "ltrim" | "rtrim" | "trim" |
				"lpad" | "rpad" | "replace" | "hex" | "fastCodeAt" | "unsafeCodeAt" | "isEof" | "quoteUnixArg" | "quoteWinArg":
				true;
			case _:
				false;
		};
	}

	static function isSysToolsSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "SysTools")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "quoteUnixArg" | "quoteWinArg":
				true;
			case _:
				false;
		};
	}

	static function isBase64SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Base64")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "decode" | "urlEncode" | "urlDecode":
				true;
			case _:
				false;
		};
	}

	static function isBaseCodeSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null)
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "BaseCode")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encodeBytes" | "decodeBytes" | "encodeString" | "decodeString" | "encode" | "decode" | "initTable":
				true;
			case _:
				false;
		};
	}

	static function isResourceSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Resource")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "listNames" | "getString" | "getBytes" | "__init__":
				true;
			case _:
				false;
		};
	}

	static function isBytesSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null)
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Bytes")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "toHex";
	}

	static function isMd5SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null)
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Md5")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "make" | "bitOR" | "bitXOR" | "bitAND" | "addme" | "hex" | "bytes2blks" | "str2blks" | "rol" | "cmn" | "ff" | "gg" | "hh" | "ii" |
				"doEncode":
				true;
			case _:
				false;
		};
	}

	static function isSha1SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null)
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Sha1")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "make" | "doEncode" | "str2blks" | "bytes2blks" | "rol" | "ft" | "kt" | "hex":
				true;
			case _:
				false;
		};
	}

	static function renderSysToolsSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		final argument = nameAt(0, "argument");
		final escapeMetaCharacters = nameAt(1, "escapeMetaCharacters");
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		switch (method) {
			case "quoteUnixArg":
				out.push("    return __hxhx_quote_unix_arg(" + argument + ");");
			case "quoteWinArg":
				out.push("    return __hxhx_quote_win_arg(" + argument + ", " + escapeMetaCharacters + ");");
			case _:
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function renderBaseCodeSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = baseCodeSupportReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  "
			+ (HxFunctionDecl.getIsStatic(fn) ? "static " : "")
			+ returnType
			+ " "
			+ method
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {"];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		inline function bytesReturn(dataExpr:String):Void {
			out.push("    auto __hxhx_data = " + dataExpr + ";");
			out.push("    return std::make_shared<Bytes>(static_cast<int>(__hxhx_data.size()), __hxhx_data);");
		}
		switch (method) {
			case "encodeBytes":
				bytesReturn("__hxhx_basecode_encode_bytes(" + nameAt(0, "b") + "->b, base->b, nbits)");
			case "decodeBytes":
				bytesReturn("__hxhx_basecode_decode_bytes(" + nameAt(0, "b") + "->b, base->b, nbits)");
			case "encodeString":
				out.push("    return __hxhx_basecode_encode_string(" + nameAt(0, "s") + ", base->b, nbits);");
			case "decodeString":
				out.push("    return __hxhx_basecode_decode_string(" + nameAt(0, "s") + ", base->b, nbits);");
			case "encode" | "decode":
				final value = nameAt(0, "s");
				final alphabet = nameAt(1, "base");
				out.push("    std::vector<int> __hxhx_alphabet;");
				out.push("    __hxhx_bytes_of_string(__hxhx_alphabet, " + alphabet + ");");
				out.push("    const int __hxhx_nbits = __hxhx_basecode_nbits(__hxhx_alphabet);");
				out.push("    return __hxhx_basecode_" + method + "_string(" + value + ", __hxhx_alphabet, __hxhx_nbits);");
			case "initTable":
				out.push("    tbl = __hxhx_basecode_table(base->b);");
			case _:
				for (arg in args)
					out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function baseCodeSupportReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encodeBytes" | "decodeBytes":
				cppTypeHint("Bytes", renderScope(owner, classLookup, "auto"), classLookup);
			case "encodeString" | "decodeString" | "encode" | "decode":
				"std::string";
			case "initTable":
				"void";
			case _:
				supportMethodSignatureReturnType(fn, owner, classLookup);
		};
	}

	static function renderResourceSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = supportMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		switch (method) {
			case "listNames":
				out.push("    return __hxhx_resource_names();");
			case "getString":
				out.push("    return __hxhx_resource_string(" + nameAt(0, "name") + ").value_or(std::string());");
			case "getBytes":
				out.push("    auto __hxhx_data = __hxhx_resource_bytes(" + nameAt(0, "name") + ");");
				out.push("    if (!__hxhx_data.has_value()) return nullptr;");
				out.push("    return std::make_shared<Bytes>(static_cast<int>(__hxhx_data->size()), *__hxhx_data);");
			case "__init__":
				out.push("    return;");
			case _:
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function renderBytesSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = supportMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final out = ["  "
			+ (HxFunctionDecl.getIsStatic(fn) ? "static " : "")
			+ returnType
			+ " "
			+ method
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {"];
		switch (method) {
			case "toHex":
				out.push("    return __hxhx_bytes_to_hex(b);");
			case _:
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function isUnserializerObjectHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		return sanitizeTypePath(HxClassDecl.getName(owner)) == "Unserializer"
			&& !HxFunctionDecl.getIsStatic(fn)
			&& sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "unserializeObject"
			&& HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function isUnserializerEnumHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		return sanitizeTypePath(HxClassDecl.getName(owner)) == "Unserializer"
			&& !HxFunctionDecl.getIsStatic(fn)
			&& sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "unserializeEnum"
			&& HxFunctionDecl.getArgs(fn).length == 2;
	}

	static function renderUnserializerObjectHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = supportMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final objectArg = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		return [
			"  " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {",
			"    while (true) {",
			"      if (pos >= length) throw std::runtime_error(std::string(\"Invalid object\"));",
			"      if (get(pos) == static_cast<int>('g')) break;",
			"      std::any k = unserialize();",
			"      if (!__hxhx_is_type(k, std::string(\"String\"))) throw std::runtime_error(std::string(\"Invalid object key\"));",
			"      std::any v = unserialize();",
			"      __hxhx_reflect_set_field(" + objectArg + ", __hxhx_stringify(k), v);",
			"    }",
			"    pos++;",
			"  }"
		];
	}

	static function renderUnserializerEnumHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = supportMethodSignatureReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final enumArg = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final tagArg = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final out = new Array<String>();
		final methodTypeParams = emittedFunctionTypeParams(fn, returnType, scope);
		if (methodTypeParams.length > 0)
			out.push("  " + genericTemplatePrefix(methodTypeParams));
		out.push("  " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {");
		out.push("    if (get(pos++) != static_cast<int>(':')) throw std::runtime_error(std::string(\"Invalid enum format\"));");
		out.push("    int nargs = readDigits();");
		out.push("    if (nargs == 0) return Type::createEnum(" + enumArg + ", " + tagArg + ");");
		out.push("    std::vector<std::string> args;");
		out.push("    while (nargs-- > 0) args.push_back(__hxhx_stringify(unserialize()));");
		out.push("    return Type::createEnum(" + enumArg + ", " + tagArg + ", args);");
		out.push("  }");
		return out;
	}

	static function renderBase64SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = base64SupportReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		final value = nameAt(0, method == "encode" || method == "urlEncode" ? "bytes" : "str");
		final complement = nameAt(1, "complement");
		final alphabet = method == "urlEncode"
			|| method == "urlDecode" ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		switch (method) {
			case "encode" | "urlEncode":
				out.push("    return __hxhx_base64_encode_bytes(" + value + "->b, " + complement + ", std::string(\"" + alphabet + "\"));");
			case "decode" | "urlDecode":
				out.push("    auto __hxhx_data = __hxhx_base64_decode_bytes("
					+ value
					+ ", "
					+ complement
					+ ", std::string(\""
					+ alphabet
					+ "\"));");
				out.push("    return std::make_shared<Bytes>(static_cast<int>(__hxhx_data.size()), __hxhx_data);");
			case _:
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function base64SupportReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "urlEncode":
				"std::string";
			case "decode" | "urlDecode":
				cppTypeHint("Bytes", renderScope(owner, classLookup, "auto"), classLookup);
			case _:
				supportMethodSignatureReturnType(fn, owner, classLookup);
		};
	}

	static function renderMd5SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = md5SupportReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  "
			+ (HxFunctionDecl.getIsStatic(fn) ? "static " : "")
			+ returnType
			+ " "
			+ method
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {"];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		switch (method) {
			case "encode":
				out.push("    return __hxhx_md5_hex_string(" + nameAt(0, "s") + ");");
			case "make":
				out.push("    auto __hxhx_data = __hxhx_md5_digest_bytes(" + nameAt(0, "b") + "->b);");
				out.push("    return std::make_shared<Bytes>(static_cast<int>(__hxhx_data.size()), __hxhx_data);");
			case _:
				for (arg in args)
					out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function md5SupportReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "hex":
				"std::string";
			case "make":
				cppTypeHint("Bytes", renderScope(owner, classLookup, "auto"), classLookup);
			case "bytes2blks" | "str2blks" | "doEncode":
				"std::vector<int>";
			case "bitOR" | "bitXOR" | "bitAND" | "addme" | "rol" | "cmn" | "ff" | "gg" | "hh" | "ii":
				"int";
			case _:
				supportMethodSignatureReturnType(fn, owner, classLookup);
		};
	}

	static function renderSha1SupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = sha1SupportReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  "
			+ (HxFunctionDecl.getIsStatic(fn) ? "static " : "")
			+ returnType
			+ " "
			+ method
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {"];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		switch (method) {
			case "encode":
				out.push("    return __hxhx_sha1_hex_string(" + nameAt(0, "s") + ");");
			case "make":
				out.push("    auto __hxhx_data = __hxhx_sha1_digest_bytes(" + nameAt(0, "b") + "->b);");
				out.push("    return std::make_shared<Bytes>(static_cast<int>(__hxhx_data.size()), __hxhx_data);");
			case _:
				for (arg in args)
					out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function sha1SupportReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "encode" | "hex":
				"std::string";
			case "make":
				cppTypeHint("Bytes", renderScope(owner, classLookup, "auto"), classLookup);
			case "bytes2blks" | "str2blks" | "doEncode":
				"std::vector<int>";
			case "rol" | "ft" | "kt":
				"int";
			case _:
				supportMethodSignatureReturnType(fn, owner, classLookup);
		};
	}

	static function renderStringToolsSupportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = stringToolsSupportReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		inline function nameAt(index:Int, fallback:String):String {
			return args.length > index ? sanitizeIdentifier(HxFunctionArg.getName(args[index])) : fallback;
		}
		final s = nameAt(0, "s");
		final a1 = nameAt(1, "value");
		final a2 = nameAt(2, "replacement");
		switch (method) {
			case "urlEncode":
				out.push("    return __hxhx_url_encode(" + s + ");");
			case "urlDecode":
				out.push("    return __hxhx_url_decode(" + s + ");");
			case "htmlEscape":
				out.push("    const bool __hxhx_quotes = " + a1 + ".has_value() && " + a1 + ".value();");
				out.push("    std::string out;");
				out.push("    for (unsigned char c : " + s + ") {");
				out.push("      switch (c) {");
				out.push("        case '&': out += \"&amp;\"; break;");
				out.push("        case '<': out += \"&lt;\"; break;");
				out.push("        case '>': out += \"&gt;\"; break;");
				out.push("        case '\\\"': if (__hxhx_quotes) out += \"&quot;\"; else out.push_back(static_cast<char>(c)); break;");
				out.push("        case '\\'': if (__hxhx_quotes) out += \"&#039;\"; else out.push_back(static_cast<char>(c)); break;");
				out.push("        default: out.push_back(static_cast<char>(c)); break;");
				out.push("      }");
				out.push("    }");
				out.push("    return out;");
			case "htmlUnescape":
				out.push("    std::string out = " + s + ";");
				out.push("    out = __hxhx_replace(out, \"&gt;\", \">\");");
				out.push("    out = __hxhx_replace(out, \"&lt;\", \"<\");");
				out.push("    out = __hxhx_replace(out, \"&quot;\", \"\\\"\");");
				out.push("    out = __hxhx_replace(out, \"&#039;\", \"'\");");
				out.push("    out = __hxhx_replace(out, \"&amp;\", \"&\");");
				out.push("    return out;");
			case "contains":
				out.push("    return " + s + ".find(" + a1 + ") != std::string::npos;");
			case "startsWith":
				out.push("    return " + s + ".rfind(" + a1 + ", 0) == 0;");
			case "endsWith":
				out.push("    return __hxhx_ends_with(" + s + ", " + a1 + ");");
			case "isSpace":
				out.push("    if (" + s + ".empty() || " + a1 + " < 0 || static_cast<size_t>(" + a1 + ") >= " + s + ".size()) return false;");
				out.push("    unsigned char c = static_cast<unsigned char>(" + s + "[static_cast<size_t>(" + a1 + ")]);");
				out.push("    return (c > 8 && c < 14) || c == 32;");
			case "ltrim":
				out.push("    return __hxhx_ltrim(" + s + ");");
			case "rtrim":
				out.push("    return __hxhx_rtrim(" + s + ");");
			case "trim":
				out.push("    return __hxhx_trim(" + s + ");");
			case "lpad":
				out.push("    if (" + a1 + ".empty()) return " + s + ";");
				out.push("    std::string out;");
				out.push("    const int remaining = " + a2 + " - static_cast<int>(" + s + ".size());");
				out.push("    while (static_cast<int>(out.size()) < remaining) out += " + a1 + ";");
				out.push("    out += " + s + ";");
				out.push("    return out;");
			case "rpad":
				out.push("    if (" + a1 + ".empty()) return " + s + ";");
				out.push("    std::string out = " + s + ";");
				out.push("    while (static_cast<int>(out.size()) < " + a2 + ") out += " + a1 + ";");
				out.push("    return out;");
			case "replace":
				out.push("    return __hxhx_replace(" + s + ", " + a1 + ", " + a2 + ");");
			case "hex":
				out.push("    unsigned int value = static_cast<unsigned int>(" + s + ");");
				out.push("    std::stringstream ss;");
				out.push("    ss << std::uppercase << std::hex << value;");
				out.push("    std::string out = ss.str();");
				out.push("    if ("
					+ a1
					+ ".has_value()) while (out.size() < static_cast<size_t>("
					+ a1
					+ ".value())) out = std::string(\"0\") + out;");
				out.push("    return out;");
			case "fastCodeAt" | "unsafeCodeAt":
				out.push("    if (" + a1 + " < 0 || static_cast<size_t>(" + a1 + ") >= " + s + ".size()) return 0;");
				out.push("    return static_cast<unsigned char>(" + s + "[static_cast<size_t>(" + a1 + ")]);");
			case "isEof":
				out.push("    return " + s + " == 0;");
			case "quoteUnixArg":
				out.push("    return __hxhx_quote_unix_arg(" + s + ");");
			case "quoteWinArg":
				out.push("    return __hxhx_quote_win_arg(" + s + ", " + a1 + ");");
			case _:
				if (returnType != "void")
					out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function stringToolsSupportReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (method) {
			case "contains" | "startsWith" | "endsWith" | "isSpace" | "isEof":
				"bool";
			case "fastCodeAt" | "unsafeCodeAt":
				"int";
			case _:
				final hinted = supportMethodSignatureReturnType(fn, owner, classLookup);
				hinted == "void" ? "std::string" : hinted;
		};
	}

	static function isUtestRunnerAddCasesHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Runner")
			return false;
		if (HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "addCases")
			return false;
		return hasFunctionMetadata(fn, "macro");
	}

	static function hasFunctionMetadata(fn:HxFunctionDecl, marker:String):Bool {
		if (fn == null || marker == null)
			return false;
		for (meta in HxFunctionDecl.getMetadata(fn))
			if (StringTools.trim(meta) == marker)
				return true;
		return false;
	}

	static function renderUtestRunnerAddCasesHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		return ["  "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {",
			"    " + returnVoidStmt(scope),
			"  }"
		];
	}

	static function isMacroCompilerApiShimHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Compiler")
			return false;
		if (!HxFunctionDecl.getIsStatic(fn))
			return false;
		return macroCompilerApiShimName(sanitizeIdentifier(HxFunctionDecl.getName(fn))) != null;
	}

	static function isHelperMacrosShimHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "HelperMacros")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "getCompilationDate" | "typeString" | "typedAs" | "isNullable" | "typeError" | "typeErrorText" | "getMeta" | "getErrorMessage" |
				"parseAndPrint" | "pipeMarkupLiteral" | "pipeMarkupLiteralUnprocessed":
				true;
			case _:
				false;
		};
	}

	static function renderHelperMacrosShimHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = helperMacrosShimReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		if (method == "typedAs" && args.length == 2) {
			return [
				"  template<typename TActual, typename TExpected>",
				"  static std::string typedAs(const TActual& actual, const TExpected& expected) {",
				"    (void)actual;",
				"    (void)expected;",
				"    return std::string();",
				"  }"
			];
		}
		if ((method == "typeError" || method == "typeErrorText") && args.length == 1) {
			final argName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
			return [
				"  template<typename TValue>",
				"  static " + returnType + " " + method + "(const TValue& " + argName + ") {",
				"    (void)" + argName + ";",
				"    return " + helperMacrosShimDefaultValue(returnType, scope) + ";",
				"  }"
			];
		}
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (returnType != "void")
			out.push("    return " + helperMacrosShimDefaultValue(returnType, scope) + ";");
		out.push("  }");
		return out;
	}

	static function helperMacrosShimDefaultValue(returnType:String, scope:CppRenderScope):String {
		if (StringTools.startsWith(returnType, "__hxhx_anon_"))
			return returnType + "{}";
		return cppDefaultValue(returnType, scope);
	}

	static function helperMacrosShimReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "typeString" | "typedAs" | "getMeta" | "pipeMarkupLiteral" | "pipeMarkupLiteralUnprocessed":
				"std::string";
			case _:
				cppFunctionReturnType(fn, owner, classLookup);
		};
	}

	static function isMacroStringToolsShimHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "MacroStringTools")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "isFormatExpr" | "toFieldExpr":
				true;
			case _:
				false;
		};
	}

	static function renderMacroStringToolsShimHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  static "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {"];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (returnType != "void")
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		out.push("  }");
		return out;
	}

	static function renderMacroCompilerApiShimHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = macroCompilerApiShimReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		final args = HxFunctionDecl.getArgs(fn);
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		final apiName = macroCompilerApiShimName(method);
		if (apiName.length == 0) {
			out.push("    " + returnVoidStmt(scope));
		} else {
			final renderedArgs = [for (arg in args) sanitizeIdentifier(HxFunctionArg.getName(arg))];
			final call = "__hxhx_call_macro_api<"
				+ returnType
				+ ">(std::string("
				+ quoteString(apiName)
				+ "), "
				+ args.length
				+ (renderedArgs.length > 0 ? ", " + renderedArgs.join(", ") : "")
				+ ")";
			out.push("    " + (returnType == "void" ? call + ";" : "return " + call + ";"));
		}
		out.push("  }");
		return out;
	}

	static function macroCompilerApiShimName(method:String):Null<String> {
		return switch (method) {
			case "allowPackage":
				"allow_package";
			case "define":
				"define";
			case "addMetadata":
				"meta_patch";
			case "addClassPath":
				"add_class_path";
			case "getOutput":
				"get_output";
			case "setOutput":
				"set_output";
			case "getDisplayPos":
				"get_display_pos";
			case "getConfiguration":
				"get_configuration";
			case "addNativeLib":
				"add_native_lib";
			case "addNativeArg":
				"add_native_arg";
			case "include":
				"include";
			case "excludeBaseType":
				"";
			case "exclude":
				"exclude";
			case "excludeFile":
				"exclude_file";
			case "patchTypes":
				"patch_types";
			case "keep":
				"keep";
			case "nullSafety":
				"null_safety";
			case "addGlobalMetadata":
				"add_global_metadata_impl";
			case "registerMetadataDescriptionFile":
				"register_metadata_description_file";
			case "registerDefinesDescriptionFile":
				"register_defines_description_file";
			case "registerCustomMetadata":
				"register_metadata_impl";
			case "registerCustomDefine":
				"register_define_impl";
			case "setCustomJSGenerator":
				"set_custom_js_generator";
			case "load":
				"load";
			case "flushDiskCache":
				"flush_disk_cache";
			case "includeFile":
				"include_file";
			case _:
				null;
		};
	}

	static function macroCompilerApiShimReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		if (sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "getDisplayPos")
			return "std::any";
		return cppFunctionReturnType(fn, owner, classLookup);
	}

	static function isExceptionCaughtThrownHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Exception")
			return false;
		if (!HxFunctionDecl.getIsStatic(fn))
			return false;
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return method == "caught" || method == "thrown";
	}

	static function renderExceptionCaughtThrownHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final scope = renderScope(owner, classLookup, "std::shared_ptr<Exception>");
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final valueName = args.length > 0 ? sanitizeIdentifier(HxFunctionArg.getName(args[0])) : "value";
		return ["  static std::shared_ptr<Exception> "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {",
			"    return std::make_shared<Exception>(" + valueName + ");",
			"  }"
		];
	}

	static function isPosExceptionToStringHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "PosException")
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getExtendsPath(owner))) != "Exception")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "toString" && HxFunctionDecl.getArgs(fn).length == 0;
	}

	static function renderPosExceptionToStringHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final posInfosType = currentOwnerFieldCppType("posInfos", scope);
		final posInfosAccess = switch (posInfosType) {
			case "std::shared_ptr<PosInfos>":
				"posInfos->";
			case "std::optional<PosInfos>":
				"posInfos.value().";
			case _:
				"posInfos.";
		};
		final out = [
			"  " + returnType + " " + sanitizeIdentifier(HxFunctionDecl.getName(fn)) + "() {"
		];
		switch (posInfosType) {
			case "std::shared_ptr<PosInfos>":
				out.push("    if (posInfos == nullptr) return Exception::toString();");
			case "std::optional<PosInfos>":
				out.push("    if (!posInfos.has_value()) return Exception::toString();");
			case _:
		}
		out.push("    return Exception::toString() + std::string(\" in \") + "
			+ posInfosAccess
			+ "className + std::string(\".\") + "
			+ posInfosAccess
			+ "methodName + std::string(\" at \") + "
			+ posInfosAccess
			+ "fileName + std::string(\":\") + std::to_string("
			+ posInfosAccess
			+ "lineNumber);");
		out.push("  }");
		return out;
	}

	static function isTestExceptionsStackItemDataHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "TestExceptions")
			return false;
		return !HxFunctionDecl.getIsStatic(fn) && sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "stackItemData";
	}

	static function renderTestExceptionsStackItemDataHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		return ["  "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {",
			"    return " + cppDefaultValue(returnType, scope) + ";",
			"  }"
		];
	}

	static function isAssertPolymorphicStringifyHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Assert")
			return false;
		if (!HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "q")
			return false;
		final args = HxFunctionDecl.getArgs(fn);
		return args.length == 1;
	}

	static function renderAssertPolymorphicStringifyHelper(fn:HxFunctionDecl):Array<String> {
		final argName = sanitizeIdentifier(HxFunctionArg.getName(HxFunctionDecl.getArgs(fn)[0]));
		return [
			"  template<typename T>",
			"  static std::string q(const T& " + argName + ") {",
			"    return __hxhx_stringify(" + argName + ");",
			"  }"
		];
	}

	static function isAssertPolymorphicSameHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Assert")
			return false;
		if (!HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "same")
			return false;
		return HxFunctionDecl.getArgs(fn).length >= 2;
	}

	static function renderAssertPolymorphicSameHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final expectedName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final valueName = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final scope = renderScope(owner, classLookup, "bool");
		prepareFunctionSignatureScope(scope, fn);
		scope.localTypes.set(expectedName, "TExpected");
		scope.localTypes.set(valueName, "TValue");
		final renderedArgs = ["const TExpected& " + expectedName, "const TValue& " + valueName];
		for (i in 2...args.length)
			renderedArgs.push(renderFunctionArg(args[i], scope));
		final recursiveName = args.length > 2 ? sanitizeIdentifier(HxFunctionArg.getName(args[2])) : "__hxhx_recursive_opt";
		final msgName = args.length > 3 ? sanitizeIdentifier(HxFunctionArg.getName(args[3])) : "__hxhx_msg_opt";
		final approxName = args.length > 4 ? sanitizeIdentifier(HxFunctionArg.getName(args[4])) : "__hxhx_approx_opt";
		final posExpr = args.length > 5 ? sanitizeIdentifier(HxFunctionArg.getName(args[5])) : "nullptr";
		final out = [
			"  template<typename TExpected, typename TValue>",
			"  static bool same(" + renderedArgs.join(", ") + ") {"
		];
		if (args.length <= 2)
			out.push("    std::optional<bool> " + recursiveName + " = std::nullopt;");
		if (args.length <= 3)
			out.push("    std::optional<std::string> " + msgName + " = std::nullopt;");
		if (args.length <= 4)
			out.push("    std::optional<double> " + approxName + " = std::nullopt;");
		out.push("    if (!" + approxName + ".has_value()) " + approxName + " = 1e-05;");
		out.push("    struct __hxhx_same_status {");
		out.push("      bool recursive;");
		out.push("      std::string path;");
		out.push("      std::string error;");
		out.push("      std::string expectedValue;");
		out.push("      std::string actualValue;");
		out.push("    };");
		out.push("    auto __hxhx_status = __hxhx_same_status{");
		out.push("      " + recursiveName + ".has_value() ? " + recursiveName + ".value() : true,");
		out.push("      std::string(),");
		out.push("      std::string(),");
		out.push("      __hxhx_stringify(" + expectedName + "),");
		out.push("      __hxhx_stringify(" + valueName + ")");
		out.push("    };");
		out.push("    if (__hxhx_same_as(" + expectedName + ", " + valueName + ", " + approxName + ".value())) {");
		out.push("      return pass("
			+ msgName
			+ ".has_value() ? "
			+ msgName
			+ ".value() : std::string(\"pass expected\"), "
			+ posExpr
			+ ");");
		out.push("    }");
		out.push("    return fail((!" + msgName + ".has_value()) ? __hxhx_status.error : " + msgName + ".value(), " + posExpr + ");");
		out.push("  }");
		return out;
	}

	static function isAssertPolymorphicSameAsHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Assert")
			return false;
		if (!HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "sameAs")
			return false;
		return HxFunctionDecl.getArgs(fn).length >= 3;
	}

	static function renderAssertPolymorphicSameAsHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final expectedName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final valueName = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final statusName = sanitizeIdentifier(HxFunctionArg.getName(args[2]));
		final scope = renderScope(owner, classLookup, "bool");
		prepareFunctionSignatureScope(scope, fn);
		scope.localTypes.set(expectedName, "TExpected");
		scope.localTypes.set(valueName, "TValue");
		final hasApprox = args.length >= 4;
		final approxName = hasApprox ? sanitizeIdentifier(HxFunctionArg.getName(args[3])) : "__hxhx_approx";
		final renderedArgs = [
			"const TExpected& " + expectedName,
			"const TValue& " + valueName,
			"TStatus& " + statusName
		];
		if (hasApprox)
			renderedArgs.push(renderFunctionArg(args[3], scope));
		final statusRef = "__hxhx_status";
		final out = ["  template<typename TExpected, typename TValue, typename TStatus>",
			"  static bool sameAs(" + renderedArgs.join(", ") + ") {",
			"    auto& "
			+ statusRef
			+ " = __hxhx_status_ref("
			+ statusName
			+ ");",
			"    ("
			+ statusRef
			+ ".expectedValue) = __hxhx_stringify("
			+ expectedName
			+ ");",
			"    ("
			+ statusRef
			+ ".actualValue) = __hxhx_stringify("
			+ valueName
			+ ");",
			"    const double __hxhx_same_as_approx = " + (hasApprox ? approxName : "0.0") + ";",
			"    if (!__hxhx_same_as("
			+ expectedName
			+ ", "
			+ valueName
			+ ", __hxhx_same_as_approx)) {",
			"      ("
			+ statusRef
			+ ".error) = std::string(\"expected \") + __hxhx_stringify("
			+ expectedName
			+ ") + std::string(\" but it is \") + __hxhx_stringify("
			+ valueName
			+ ");",
			"      return false;",
			"    }",
			"    (" + statusRef + ".error) = std::string();",
			"    return true;",
			"  }"
		];
		return out;
	}

	static function isUtestEqHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (owner == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Test")
			return false;
		if (HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "eq")
			return false;
		return HxFunctionDecl.getArgs(fn).length >= 2;
	}

	static function renderUtestEqHelper(fn:HxFunctionDecl):Array<String> {
		final args = HxFunctionDecl.getArgs(fn);
		final expectedName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final valueName = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final posName = args.length > 2 ? sanitizeIdentifier(HxFunctionArg.getName(args[2])) : "pos";
		return ["  template<typename TExpected, typename TValue>",
			"  void eq(const TExpected& "
			+ expectedName
			+ ", const TValue& "
			+ valueName
			+ ", std::optional<PosInfos> "
			+ posName
			+ " = std::nullopt) {",
			"    Assert::same("
			+ expectedName
			+ ", "
			+ valueName
			+ ", std::nullopt, std::nullopt, std::nullopt, PosInfos("
			+ posName
			+ ".value()));",
			"  }"
		];
	}

	static function findConstructor(cls:HxClassDecl):Null<HxFunctionDecl> {
		for (fn in HxClassDecl.getFunctions(cls))
			if (!HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "new")
				return fn;
		return null;
	}

	static function genericClassTypeParams(cls:HxClassDecl):Array<String> {
		final params = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();
		function addParam(param:String):Void {
			final clean = sanitizeIdentifier(StringTools.trim(param == null ? "" : param));
			if (clean.length > 0 && !seen.exists(clean)) {
				seen.set(clean, true);
				params.push(clean);
			}
		}
		function addHint(typeHint:String):Void
			addGenericTypeParamsFromHint(typeHint, addParam);
		for (meta in HxClassDecl.getMetadata(cls)) {
			final prefix = "__hxhx_type_params=";
			if (StringTools.startsWith(meta, prefix)) {
				for (param in meta.substr(prefix.length).split(","))
					addParam(param);
			}
			final underlyingPrefix = "__hxhx_abstract_underlying=";
			if (StringTools.startsWith(meta, underlyingPrefix))
				addHint(meta.substr(underlyingPrefix.length));
		}
		for (field in HxClassDecl.getFields(cls))
			addHint(HxFieldDecl.getTypeHint(field));
		final ctor = findConstructor(cls);
		if (ctor != null)
			for (arg in HxFunctionDecl.getArgs(ctor))
				addHint(HxFunctionArg.getTypeHint(arg));
		if (HxClassDecl.getIsInterface(cls)) {
			for (fn in HxClassDecl.getFunctions(cls)) {
				for (arg in HxFunctionDecl.getArgs(fn))
					addHint(HxFunctionArg.getTypeHint(arg));
				addHint(HxFunctionDecl.getReturnTypeHint(fn));
			}
		}
		return params;
	}

	static function addGenericTypeParamsFromHint(typeHint:String, addParam:String->Void):Void {
		final raw = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (raw.length == 0)
			return;
		final direct = genericTypeParamName(raw);
		if (direct.length > 0) {
			addParam(direct);
			return;
		}
		if (isFunctionTypeHint(raw)) {
			for (part in splitTopLevelFunctionType(raw))
				addGenericTypeParamsFromHint(part, addParam);
			return;
		}
		if (isStructuralTypeHint(raw)) {
			for (field in CppTypeModel.structuralTypeHintFields(raw))
				addGenericTypeParamsFromHint(field.typeHint, addParam);
			return;
		}
		for (arg in genericTypeHintArgs(raw))
			addGenericTypeParamsFromHint(arg, addParam);
	}

	static function genericClassTemplateParams(cls:HxClassDecl):Array<String> {
		final params = genericClassTypeParams(cls);
		return params;
	}

	static function genericFunctionTypeParams(fn:HxFunctionDecl):Array<String> {
		final params = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();
		function add(raw:String):Void {
			final clean = sanitizeIdentifier(StringTools.trim(raw == null ? "" : raw));
			if (clean.length > 0 && !seen.exists(clean)) {
				seen.set(clean, true);
				params.push(clean);
			}
		}
		for (meta in HxFunctionDecl.getMetadata(fn)) {
			final prefix = "__hxhx_fn_type_params=";
			if (!StringTools.startsWith(meta, prefix))
				continue;
			for (param in meta.substr(prefix.length).split(","))
				add(param);
		}
		for (arg in HxFunctionDecl.getArgs(fn))
			collectDynamicGenericWildcardParamsFromHint(HxFunctionArg.getTypeHint(arg), add);
		return params;
	}

	static function collectDynamicGenericWildcardParamsFromHint(typeHint:String, add:String->Void):Void {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final args = genericTypeHintArgs(hint);
		if (args.length == 0)
			return;
		for (arg in args) {
			if (isDynamicLikeTypeHint(arg))
				add("TDynamic");
			else
				collectDynamicGenericWildcardParamsFromHint(arg, add);
		}
	}

	static function applyFunctionTypeParams(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		final params = genericFunctionTypeParams(fn);
		if (params.length == 0)
			return;
		final merged = scope.typeParams == null ? [] : scope.typeParams.copy();
		if (scope.typeParamCppNames == null)
			scope.typeParamCppNames = new haxe.ds.StringMap<String>();
		final seenRaw = new haxe.ds.StringMap<Bool>();
		final seenCpp = new haxe.ds.StringMap<Bool>();
		for (param in merged) {
			final clean = sanitizeIdentifier(param);
			if (clean.length == 0)
				continue;
			seenRaw.set(clean, true);
			final mapped = cppTypeParamName(clean, scope);
			if (mapped.length > 0)
				seenCpp.set(mapped, true);
		}
		for (param in params) {
			final clean = sanitizeIdentifier(param);
			if (clean.length == 0)
				continue;
			var cppName = clean;
			if (seenRaw.exists(clean) || seenCpp.exists(cppName))
				cppName = uniqueFunctionTypeParamCppName(clean, seenCpp);
			if (!seenRaw.exists(clean)) {
				seenRaw.set(clean, true);
				merged.push(clean);
			}
			seenCpp.set(cppName, true);
			scope.typeParamCppNames.set(clean, cppName);
		}
		scope.typeParams = merged;
	}

	static function emittedFunctionTypeParams(fn:HxFunctionDecl, returnType:String, scope:CppRenderScope):Array<String> {
		final out = new Array<String>();
		for (param in genericFunctionTypeParams(fn)) {
			final cppName = cppTypeParamName(param, scope);
			if (cppTypeTextMentionsParam(returnType, cppName)) {
				out.push(cppName);
				continue;
			}
			for (arg in HxFunctionDecl.getArgs(fn)) {
				if (cppTypeTextMentionsParam(cppFunctionArgType(arg, scope), cppName)) {
					out.push(cppName);
					break;
				}
			}
		}
		return out;
	}

	static function functionReturnTypeParamShouldUseAuto(rawReturn:String, fn:HxFunctionDecl):Bool {
		final param = genericTypeParamName(rawReturn);
		if (param.length == 0)
			return false;
		var declared = false;
		for (candidate in genericFunctionTypeParams(fn))
			if (sanitizeIdentifier(candidate) == sanitizeIdentifier(param))
				declared = true;
		if (!declared)
			return false;
		for (arg in HxFunctionDecl.getArgs(fn))
			if (typeHintMentionsGenericParam(HxFunctionArg.getTypeHint(arg), param))
				return false;
		return true;
	}

	static function typeHintMentionsGenericParam(typeHint:String, param:String):Bool {
		final cleanParam = sanitizeIdentifier(param);
		if (cleanParam.length == 0)
			return false;
		final direct = genericTypeParamName(typeHint);
		if (direct.length > 0)
			return sanitizeIdentifier(direct) == cleanParam;
		if (isFunctionTypeHint(typeHint)) {
			for (part in splitTopLevelFunctionType(typeHint))
				if (typeHintMentionsGenericParam(part, param))
					return true;
			return false;
		}
		if (isStructuralTypeHint(typeHint)) {
			for (field in CppTypeModel.structuralTypeHintFields(typeHint))
				if (typeHintMentionsGenericParam(field.typeHint, param))
					return true;
			return false;
		}
		for (arg in genericTypeHintArgs(typeHint))
			if (typeHintMentionsGenericParam(arg, param))
				return true;
		return false;
	}

	static function cppTypeParamName(param:String, ?scope:CppRenderScope):String {
		final clean = sanitizeIdentifier(StringTools.trim(param == null ? "" : param));
		if (clean.length == 0)
			return "";
		if (scope != null && scope.typeParamCppNames != null) {
			final mapped = scope.typeParamCppNames.get(clean);
			if (mapped != null && mapped.length > 0)
				return mapped;
		}
		return clean;
	}

	static function uniqueFunctionTypeParamCppName(param:String, seenCpp:haxe.ds.StringMap<Bool>):String {
		final base = sanitizeIdentifier(param) + "__fn";
		var candidate = base;
		var index = 2;
		while (seenCpp.exists(candidate)) {
			candidate = base + index;
			index++;
		}
		return candidate;
	}

	static function cppTypeTextMentionsParam(typeText:String, param:String):Bool {
		final text = typeText == null ? "" : typeText;
		final clean = sanitizeIdentifier(StringTools.trim(param == null ? "" : param));
		if (clean.length == 0)
			return false;
		var start = 0;
		while (start < text.length) {
			final index = text.indexOf(clean, start);
			if (index < 0)
				return false;
			final beforeOk = index == 0 || !isIdentifierCharAt(text, index - 1, true);
			final after = index + clean.length;
			final afterOk = after >= text.length || !isIdentifierCharAt(text, after, true);
			if (beforeOk && afterOk)
				return true;
			start = index + clean.length;
		}
		return false;
	}

	static function genericTemplatePrefix(typeParams:Array<String>):String {
		return "template<" + [for (param in typeParams) "typename " + sanitizeIdentifier(param)].join(", ") + ">";
	}

	static function genericTypeParamName(typeHint:String):String {
		final raw = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (raw.length != 1)
			return "";
		final code = raw.charCodeAt(0);
		return code >= "A".code && code <= "Z".code ? sanitizeIdentifier(raw) : "";
	}

	static function isGenericTypeParamHint(typeHint:String, cls:HxClassDecl):Bool {
		final param = genericTypeParamName(typeHint);
		if (param.length == 0)
			return false;
		for (known in genericClassTemplateParams(cls))
			if (known == param)
				return true;
		return false;
	}

	static function constructorInitializerList(ctor:HxFunctionDecl, scope:CppRenderScope):String {
		final parts = new Array<String>();
		final baseType = scope == null || scope.owner == null ? null : inheritedCppBaseTypeName(scope.owner, {
			names: scope.classNames,
			byName: scope.classByName
		});
		if (baseType != null)
			switch (constructorSuperCallArgs(HxFunctionDecl.getBody(ctor))) {
				case null:
				case args:
					parts.push(baseType + "(" + [for (arg in args) renderExpr(arg, scope)].join(", ") + ")");
			}
		for (init in constructorFieldInitializers(ctor, scope))
			parts.push(init.field + "(" + init.arg + ")");
		return parts.length == 0 ? "" : " : " + parts.join(", ");
	}

	static function constructorBodyWithoutSuperCall(ctor:HxFunctionDecl):Array<HxStmt> {
		final body = HxFunctionDecl.getBody(ctor);
		var skipped = false;
		final out = new Array<HxStmt>();
		for (stmt in body)
			switch (stmt) {
				case SExpr(ECall(ESuper, _), _) if (!skipped):
					skipped = true;
				case _:
					out.push(stmt);
			}
		return out;
	}

	static function constructorBodyWithoutInitializerStmts(ctor:HxFunctionDecl, scope:CppRenderScope):Array<HxStmt> {
		final out = new Array<HxStmt>();
		for (stmt in constructorBodyWithoutSuperCall(ctor))
			if (constructorFieldInitializer(stmt, ctor, scope) == null)
				out.push(stmt);
		return out;
	}

	static function constructorFieldInitializers(ctor:HxFunctionDecl, scope:CppRenderScope):Array<CppConstructorFieldInitializer> {
		final out = new Array<CppConstructorFieldInitializer>();
		for (stmt in constructorBodyWithoutSuperCall(ctor)) {
			final init = constructorFieldInitializer(stmt, ctor, scope);
			if (init != null)
				out.push(init);
		}
		return out;
	}

	static function constructorFieldInitializer(stmt:HxStmt, ctor:HxFunctionDecl, scope:CppRenderScope):Null<CppConstructorFieldInitializer> {
		return switch (stmt) {
			case SExpr(EBinop("=", EField(EThis, fieldName), EIdent(argName)), _)
				if (constructorHasField(scope, fieldName) && constructorHasArg(ctor, argName)):
				{field: sanitizeIdentifier(fieldName), arg: constructorFieldInitializerArg(fieldName, argName, ctor, scope)};
			case _:
				null;
		};
	}

	static function constructorFieldInitializerArg(fieldName:String, argName:String, ctor:HxFunctionDecl, scope:CppRenderScope):String {
		final renderedArg = sanitizeIdentifier(argName);
		final fieldType = constructorFieldCppType(scope, fieldName);
		final argType = constructorArgCppType(ctor, argName, scope);
		final optionalInner = cppOptionalInnerType(argType);
		if (fieldType != null && optionalInner.length > 0 && optionalInner == fieldType)
			return renderedArg + ".value_or(" + cppDefaultValue(fieldType, scope) + ")";
		return renderedArg;
	}

	static function constructorFieldCppType(scope:CppRenderScope, fieldName:String):Null<String> {
		if (scope == null || scope.owner == null)
			return null;
		final wanted = sanitizeIdentifier(fieldName);
		final className = sanitizeTypePath(HxClassDecl.getName(scope.owner));
		for (field in HxClassDecl.getFields(scope.owner))
			if (!HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return knownStdlibFieldCppType(className, HxFieldDecl.getName(field), HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
		return null;
	}

	static function constructorArgCppType(ctor:HxFunctionDecl, argName:String, scope:CppRenderScope):String {
		final wanted = sanitizeIdentifier(argName);
		for (arg in HxFunctionDecl.getArgs(ctor))
			if (sanitizeIdentifier(HxFunctionArg.getName(arg)) == wanted)
				return cppFunctionArgType(arg, scope);
		return "";
	}

	static function constructorHasField(scope:CppRenderScope, fieldName:String):Bool {
		if (scope == null || scope.owner == null)
			return false;
		final wanted = sanitizeIdentifier(fieldName);
		for (field in HxClassDecl.getFields(scope.owner))
			if (!HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return true;
		return false;
	}

	static function constructorHasArg(ctor:HxFunctionDecl, argName:String):Bool {
		final wanted = sanitizeIdentifier(argName);
		for (arg in HxFunctionDecl.getArgs(ctor))
			if (sanitizeIdentifier(HxFunctionArg.getName(arg)) == wanted)
				return true;
		return false;
	}

	static function constructorSuperCallArgs(stmts:Array<HxStmt>):Null<Array<HxExpr>> {
		if (stmts == null || stmts.length == 0)
			return null;
		for (stmt in stmts)
			switch (stmt) {
				case SExpr(ECall(ESuper, args), _):
					return args;
				case _:
			}
		return null;
	}

	static function renderFunctionArgs(args:Array<HxFunctionArg>, ?scope:CppRenderScope, includeDefaults:Bool = true):String {
		return [
			for (arg in args)
				renderFunctionArg(arg, scope, includeDefaults)
		].join(", ");
	}

	static function renderFunctionArg(arg:HxFunctionArg, ?scope:CppRenderScope, includeDefaults:Bool = true):String {
		final typeName = cppFunctionArgType(arg, scope);
		return typeName
			+ " "
			+ sanitizeIdentifier(HxFunctionArg.getName(arg))
			+ (includeDefaults ? cppFunctionArgDefaultSuffix(arg, typeName) : "");
	}

	static function cppFunctionArgType(arg:HxFunctionArg, ?scope:CppRenderScope):String {
		final argName = sanitizeIdentifier(HxFunctionArg.getName(arg));
		final overrideType = scope == null ? null : scope.argTypeOverrides.get(argName);
		final rawTypeHint = HxFunctionArg.getTypeHint(arg);
		final explicit = StringTools.trim(rawTypeHint == null ? "" : rawTypeHint);
		final canCache = explicit.length > 0 || (overrideType != null && overrideType.length > 0);
		final cacheKey = canCache ? functionArgDeclaredTypeCacheKey(arg, scope, argName, explicit, overrideType) : "";
		if (cacheKey.length > 0) {
			final cached = functionArgDeclaredTypeCache.get(cacheKey);
			if (cached != null)
				return cached;
		}
		final typeName = overrideType != null
			&& overrideType.length > 0 ? overrideType : cppFunctionArgBaseTypeFromExplicit(arg, scope, explicit);
		final rendered = HxFunctionArg.getIsOptional(arg)
			&& !HxFunctionArg.getIsRest(arg)
			&& !isCppReferenceType(typeName)
			&& !isCppOptionalType(typeName) ? "std::optional<" + typeName + ">" : typeName;
		if (cacheKey.length > 0)
			functionArgDeclaredTypeCache.set(cacheKey, rendered);
		return rendered;
	}

	static function cppFunctionArgBaseType(arg:HxFunctionArg, ?scope:CppRenderScope):String {
		final rawTypeHint = HxFunctionArg.getTypeHint(arg);
		final explicit = StringTools.trim(rawTypeHint == null ? "" : rawTypeHint);
		return cppFunctionArgBaseTypeFromExplicit(arg, scope, explicit);
	}

	static function cppFunctionArgBaseTypeFromExplicit(arg:HxFunctionArg, ?scope:CppRenderScope, explicit:String = ""):String {
		final inferred = explicit.length > 0 ? "" : cppFunctionArgDefaultType(arg, scope);
		if (explicit.length > 0) {
			final wildcard = dynamicGenericWildcardCppTypeHint(explicit, scope);
			return wildcard.length > 0 ? wildcard : cppTypeHint(explicit, scope);
		}
		return inferred.length > 0 ? inferred : cppTypeHint("", scope);
	}

	static function functionArgDeclaredTypeCacheKey(arg:HxFunctionArg, ?scope:CppRenderScope, argName:String = "", explicit:String = "",
			?overrideType:String):String {
		final ownerName = scope == null || scope.owner == null ? "" : renderedClassName(scope.owner, scope.classLookup);
		return ownerName
			+ "|arg="
			+ argName
			+ "|hint="
			+ removeTypeHintWhitespace(explicit)
			+ "|hint_shape="
			+ typeHintScopeShapeCacheKey(explicit, scope)
			+ "|override="
			+ (overrideType == null ? "" : overrideType)
			+ "|optional="
			+ (HxFunctionArg.getIsOptional(arg) ? "1" : "0")
			+ "|rest="
			+ (HxFunctionArg.getIsRest(arg) ? "1" : "0")
			+ "|type_params="
			+ stringMapStableKey(scope == null ? null : scope.typeParamCppNames);
	}

	static function inferCallableArgTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null)
			return;
		final args = HxFunctionDecl.getArgs(fn);
		final candidates = new haxe.ds.StringMap<Bool>();
		final ownerName = scope.owner == null ? "" : HxClassDecl.getName(scope.owner);
		final methodName = HxFunctionDecl.getName(fn);
		final timingEnabled = traceCppMethodStmtTimingsEnabled(ownerName, methodName);
		function traceCallableArgPhase(phase:String, elapsed:Float):Void {
			traceCppTimingPhase("render_helper_callable_arg_infer_timing owner=" + sanitizeTypePath(typeBaseName(ownerName)) + " name="
				+ sanitizeIdentifier(methodName) + " phase=" + phase + " seconds=" + Std.string(elapsed) + " candidates="
				+ Std.string(countStringMap(candidates)) + " arg_overrides=" + Std.string(countStringMap(scope.argTypeOverrides)) + " local_overrides="
				+ Std.string(countStringMap(scope.localTypeOverrides)) + " local_types=" + Std.string(countStringMap(scope.localTypes))
				+ " candidate_values=" + summarizeBoolValueMap(candidates) + " arg_override_values=" + summarizeStringValueMap(scope.argTypeOverrides)
				+ " local_override_values=" + summarizeStringValueMap(scope.localTypeOverrides));
		}
		function traceCallableArgStmt(index:Int, stmt:HxStmt, elapsed:Float):Void {
			traceCppTimingPhase("render_helper_callable_arg_stmt_timing owner=" + sanitizeTypePath(typeBaseName(ownerName)) + " name="
				+ sanitizeIdentifier(methodName) + " index=" + Std.string(index) + " kind=" + stmtKind(stmt) + " seconds=" + Std.string(elapsed)
				+ " candidates=" + Std.string(countStringMap(candidates)) + " arg_overrides=" + Std.string(countStringMap(scope.argTypeOverrides))
				+ " local_overrides=" + Std.string(countStringMap(scope.localTypeOverrides)) + " local_types=" + Std.string(countStringMap(scope.localTypes)));
		}
		function traceCallableArgStmtPhase(index:Int, stmt:HxStmt, phase:String, elapsed:Float):Void {
			traceCppTimingPhase("render_helper_callable_arg_stmt_phase_timing owner=" + sanitizeTypePath(typeBaseName(ownerName)) + " name="
				+ sanitizeIdentifier(methodName) + " index=" + Std.string(index) + " kind=" + stmtKind(stmt) + " phase=" + phase + " seconds="
				+ Std.string(elapsed) + " candidates=" + Std.string(countStringMap(candidates)) + " arg_overrides="
				+ Std.string(countStringMap(scope.argTypeOverrides)) + " local_overrides=" + Std.string(countStringMap(scope.localTypeOverrides))
				+ " local_types=" + Std.string(countStringMap(scope.localTypes)));
		}
		function runCallableArgPhase(phase:String, body:Void->Void):Void {
			if (!timingEnabled) {
				body();
				return;
			}
			final startTime = Sys.time();
			body();
			traceCallableArgPhase(phase, Sys.time() - startTime);
		}
		runCallableArgPhase("candidate_setup", () -> {
			for (arg in args) {
				final name = sanitizeIdentifier(HxFunctionArg.getName(arg));
				final rawType = cppFunctionArgBaseType(arg, scope);
				final explicitType = StringTools.trim(HxFunctionArg.getTypeHint(arg) == null ? "" : HxFunctionArg.getTypeHint(arg));
				scope.localTypes.set(name, rawType);
				if (rawType == "std::string" || explicitType.length == 0)
					candidates.set(name, true);
			}
		});
		if (!candidates.iterator().hasNext()) {
			runCallableArgPhase("reset_no_candidates", () -> scope.localTypes = new haxe.ds.StringMap<String>());
			return;
		}
		runCallableArgPhase("forwarded_constructor", () -> collectForwardedConstructorArgTypeOverrides(HxFunctionDecl.getBody(fn), scope, candidates));
		runCallableArgPhase("assigned_args", () -> {
			for (stmt in HxFunctionDecl.getBody(fn))
				collectAssignedArgTypeOverridesFromStmt(stmt, scope, candidates);
		});
		runCallableArgPhase("callable_args", () -> {
			var stmtIndex = 0;
			final priorTraceOwner = scope.traceOwnerName;
			final priorTraceMethod = scope.traceMethodName;
			final priorTraceStmtIndex = scope.traceStmtIndex;
			function restoreCallableArgTrace():Void {
				scope.traceOwnerName = priorTraceOwner;
				scope.traceMethodName = priorTraceMethod;
				scope.traceStmtIndex = priorTraceStmtIndex;
			}
			if (timingEnabled) {
				scope.traceOwnerName = sanitizeTypePath(typeBaseName(ownerName));
				scope.traceMethodName = sanitizeIdentifier(methodName);
			}
			try {
				for (stmt in HxFunctionDecl.getBody(fn)) {
					if (!timingEnabled) {
						collectCallableArgTypeOverridesFromStmt(stmt, scope, candidates, scope.returnType);
					} else {
						scope.traceStmtIndex = stmtIndex;
						final stmtStartTime = Sys.time();
						switch (stmt) {
							case SForIn(name, iterable, body, _):
								final iterableStartTime = Sys.time();
								collectCallableArgTypeOverridesFromExpr(iterable, scope, candidates, "");
								traceCallableArgStmtPhase(stmtIndex, stmt, "for_iterable", Sys.time() - iterableStartTime);
								var loopType = "";
								final elementTypeStartTime = Sys.time();
								loopType = iterableElementType(iterable, scope);
								traceCallableArgStmtPhase(stmtIndex, stmt, "for_element_type", Sys.time() - elementTypeStartTime);
								final bodyStartTime = Sys.time();
								withScopedLocal(scope, sanitizeIdentifier(name), loopType, () -> {
									collectCallableArgTypeOverridesFromStmt(body, scope, candidates, scope.returnType);
								});
								traceCallableArgStmtPhase(stmtIndex, stmt, "for_body", Sys.time() - bodyStartTime);
							case _:
								collectCallableArgTypeOverridesFromStmt(stmt, scope, candidates, scope.returnType);
						}
						traceCallableArgStmt(stmtIndex, stmt, Sys.time() - stmtStartTime);
					}
					stmtIndex++;
				}
			} catch (e:haxe.Exception) {
				restoreCallableArgTrace();
				throw e;
			}
			restoreCallableArgTrace();
		});
		runCallableArgPhase("reset", () -> scope.localTypes = new haxe.ds.StringMap<String>());
	}

	static function inferDynamicLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final candidates = new haxe.ds.StringMap<Bool>();
		for (stmt in HxFunctionDecl.getBody(fn))
			collectDynamicLocalTypeOverridesFromStmt(stmt, scope, candidates);
		scope.localTypes = savedLocalTypes;
	}

	static function inferStringMapLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		CppLocalTypeInference.inferStringMapLocalTypeOverrides(scope, fn, localTypeInferenceApi());
	}

	static function inferStringMapLocalTypeOverridesFromStmts(scope:CppRenderScope, stmts:Array<HxStmt>):Void {
		CppLocalTypeInference.inferStringMapLocalTypeOverridesFromStmts(scope, stmts, localTypeInferenceApi());
	}

	static function localTypeInferenceApi():CppLocalTypeInference.CppLocalTypeInferenceApi {
		return {
			copyStringMap: copyStringMap,
			copyIntMap: copyIntMap,
			sanitizeIdentifier: sanitizeIdentifier,
			sanitizeTypePath: sanitizeTypePath,
			typeBaseName: typeBaseName,
			isInferredMapClassName: isInferredMapClassName,
			exprCppType: exprCppType,
			inferExprCppType: inferExprCppType,
			isStringLike: function(expr) return isStringLike(expr),
			localCppName: localCppName,
			declareLocalName: declareLocalName,
			cppLocalTypeHint: cppLocalTypeHint,
			iterableElementType: iterableElementType,
			keyValueLoopTypes: keyValueLoopTypes,
			withScopedLocal: withScopedLocal
		};
	}

	static function restoreStringMap(target:haxe.ds.StringMap<String>, saved:haxe.ds.StringMap<String>):Void {
		final stale = [for (key in target.keys()) if (!saved.exists(key)) key];
		for (key in stale)
			target.remove(key);
		for (key in saved.keys())
			target.set(key, saved.get(key));
	}

	static function isInferredMapClassName(className:String):Bool {
		return switch (sanitizeTypePath(typeBaseName(className == null ? "" : className))) {
			case "StringMap" | "IntMap":
				true;
			case "Map":
				true;
			case _:
				false;
		};
	}

	static function inferGenericFactoryLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalNames = copyStringMap(scope.localNames);
		final savedLocalNameCounts = copyIntMap(scope.localNameCounts);
		final candidates = new haxe.ds.StringMap<String>();
		final mapped = new haxe.ds.StringMap<haxe.ds.StringMap<String>>();
		for (stmt in HxFunctionDecl.getBody(fn))
			collectGenericFactoryLocalTypeOverridesFromStmt(stmt, scope, candidates, mapped);
		scope.localTypes = savedLocalTypes;
		scope.localNames = savedLocalNames;
		scope.localNameCounts = savedLocalNameCounts;
	}

	static function collectGenericFactoryLocalTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:haxe.ds.StringMap<String>,
			mapped:haxe.ds.StringMap<haxe.ds.StringMap<String>>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				withGenericFactoryInferenceScope(scope, candidates, mapped, () -> {
					for (s in stmts)
						collectGenericFactoryLocalTypeOverridesFromStmt(s, scope, candidates, mapped);
				});
			case SIf(cond, thenBranch, elseBranch, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(cond, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromStmt(thenBranch, scope, candidates, mapped);
				if (elseBranch != null)
					collectGenericFactoryLocalTypeOverridesFromStmt(elseBranch, scope, candidates, mapped);
			case SForIn(name, iterable, body, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(iterable, scope, candidates, mapped);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectGenericFactoryLocalTypeOverridesFromStmt(body, scope, candidates, mapped);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(iterable, scope, candidates, mapped);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectGenericFactoryLocalTypeOverridesFromStmt(body, scope, candidates, mapped);
					});
				});
			case SWhile(cond, body, _) | SDoWhile(body, cond, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(cond, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromStmt(body, scope, candidates, mapped);
			case SSwitch(scrutinee, _, bodies, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(scrutinee, scope, candidates, mapped);
				for (body in bodies)
					collectGenericFactoryLocalTypeOverridesFromStmt(body, scope, candidates, mapped);
			case STry(tryBody, catches, _):
				collectGenericFactoryLocalTypeOverridesFromStmt(tryBody, scope, candidates, mapped);
				for (c in catches)
					collectGenericFactoryLocalTypeOverridesFromStmt(c.body, scope, candidates, mapped);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectGenericFactoryLocalTypeOverridesFromExpr(init, scope, candidates, mapped);
				final local = declareLocalName(name, scope);
				final className = genericFactoryClassNameFromNewExpr(typeHint, init, scope);
				if (className.length > 0) {
					candidates.set(local, className);
					mapped.set(local, new haxe.ds.StringMap<String>());
				} else {
					final localType = cppLocalTypeHint(typeHint, init, scope);
					if (localType.length > 0)
						scope.localTypes.set(local, localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(expr, scope, candidates, mapped);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function collectGenericFactoryLocalTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:haxe.ds.StringMap<String>,
			mapped:haxe.ds.StringMap<haxe.ds.StringMap<String>>):Void {
		switch (expr) {
			case EBinop("=", EField(EIdent(name), field), rhs) if (candidates.exists(localCppName(name, scope))):
				collectGenericFactoryLocalTypeOverridesFromExpr(rhs, scope, candidates, mapped);
				applyGenericFactoryFieldAssignment(scope, localCppName(name, scope), field, rhs, candidates, mapped);
			case EBinop("=", EArrayAccess(EIdent(name), key), value) if (candidates.exists(localCppName(name, scope))):
				collectGenericFactoryLocalTypeOverridesFromExpr(key, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromExpr(value, scope, candidates, mapped);
				applyGenericFactoryArrayAssignment(scope, localCppName(name, scope), key, value, candidates, mapped);
			case EBinop(_, left, right):
				collectGenericFactoryLocalTypeOverridesFromExpr(left, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromExpr(right, scope, candidates, mapped);
			case ECall(callee, args):
				collectGenericFactoryLocalTypeOverridesFromExpr(callee, scope, candidates, mapped);
				for (arg in args)
					collectGenericFactoryLocalTypeOverridesFromExpr(arg, scope, candidates, mapped);
			case EArrayAccess(array, index):
				collectGenericFactoryLocalTypeOverridesFromExpr(array, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromExpr(index, scope, candidates, mapped);
			case EField(receiver, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(receiver, scope, candidates, mapped);
			case EArrayDecl(elements):
				for (element in elements)
					collectGenericFactoryLocalTypeOverridesFromExpr(element, scope, candidates, mapped);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectGenericFactoryLocalTypeOverridesFromExpr(iterable, scope, candidates, mapped);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectGenericFactoryLocalTypeOverridesFromExpr(guardExpr, scope, candidates, mapped);
					collectGenericFactoryLocalTypeOverridesFromExpr(yieldExpr, scope, candidates, mapped);
				});
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectGenericFactoryLocalTypeOverridesFromExpr(inner, scope, candidates, mapped);
			case ETernary(cond, thenExpr, elseExpr):
				collectGenericFactoryLocalTypeOverridesFromExpr(cond, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromExpr(thenExpr, scope, candidates, mapped);
				collectGenericFactoryLocalTypeOverridesFromExpr(elseExpr, scope, candidates, mapped);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectGenericFactoryLocalTypeOverridesFromExpr(value, scope, candidates, mapped);
			case ESwitch(scrutinee, _, exprs):
				collectGenericFactoryLocalTypeOverridesFromExpr(scrutinee, scope, candidates, mapped);
				for (value in exprs)
					collectGenericFactoryLocalTypeOverridesFromExpr(value, scope, candidates, mapped);
			case ELambda(_, body):
				collectGenericFactoryLocalTypeOverridesFromExpr(body, scope, candidates, mapped);
			case ENew(_, args):
				for (arg in args)
					collectGenericFactoryLocalTypeOverridesFromExpr(arg, scope, candidates, mapped);
			case _:
		}
	}

	static function genericFactoryClassNameFromNewExpr(typeHint:String, init:Null<HxExpr>, scope:CppRenderScope):String {
		if (StringTools.trim(typeHint == null ? "" : typeHint).length > 0)
			return "";
		return switch (init) {
			case ENew(typePath, args) if (args.length == 0):
				final className = sanitizeTypePath(typeBaseName(typePath));
				genericClassTypeParamsForName(className, scope).length > 0 ? className : "";
			case _:
				"";
		};
	}

	static function applyGenericFactoryFieldAssignment(scope:CppRenderScope, local:String, field:String, rhs:HxExpr, candidates:haxe.ds.StringMap<String>,
			mapped:haxe.ds.StringMap<haxe.ds.StringMap<String>>):Void {
		final className = candidates.get(local);
		final cls = scope == null ? null : scope.classByName.get(className);
		if (cls == null)
			return;
		final wanted = sanitizeIdentifier(field);
		for (decl in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(decl) || sanitizeIdentifier(HxFieldDecl.getName(decl)) != wanted)
				continue;
			unifyGenericFactoryTypeHint(HxFieldDecl.getTypeHint(decl), genericFactoryActualCppType(rhs, scope), genericClassTemplateParams(cls),
				mapped.get(local), scope);
			setGenericFactoryLocalTypeOverride(scope, local, className, genericClassTemplateParams(cls), mapped.get(local));
			return;
		}
	}

	static function applyGenericFactoryArrayAssignment(scope:CppRenderScope, local:String, key:HxExpr, value:HxExpr, candidates:haxe.ds.StringMap<String>,
			mapped:haxe.ds.StringMap<haxe.ds.StringMap<String>>):Void {
		final className = candidates.get(local);
		final params = genericClassTypeParamsForName(className, scope);
		if (params.length < 2)
			return;
		final localMapped = mapped.get(local);
		setGenericFactoryMappedType(localMapped, params[0], genericFactoryActualCppType(key, scope));
		setGenericFactoryMappedType(localMapped, params[1], genericFactoryActualCppType(value, scope));
		setGenericFactoryLocalTypeOverride(scope, local, className, params, localMapped);
	}

	static function unifyGenericFactoryTypeHint(patternHint:String, actualType:String, params:Array<String>, mapped:haxe.ds.StringMap<String>,
			?scope:CppRenderScope):Void {
		final pattern = removeTypeHintWhitespace(StringTools.trim(patternHint == null ? "" : patternHint));
		if (pattern.length == 0 || actualType == null || actualType.length == 0)
			return;
		final param = genericTypeParamName(pattern);
		if (param.length > 0 && params.indexOf(cppTypeParamName(param, scope)) >= 0) {
			setGenericFactoryMappedType(mapped, cppTypeParamName(param, scope), actualType);
			return;
		}
		final patternArgs = genericTypeHintArgs(pattern);
		if (patternArgs.length == 0)
			return;
		final actualArgs = templateArgsFromExpectedClassType(sanitizeTypePath(typeBaseName(pattern)), actualType);
		if (actualArgs.length != patternArgs.length)
			return;
		for (i in 0...patternArgs.length)
			unifyGenericFactoryTypeHint(patternArgs[i], actualArgs[i], params, mapped, scope);
	}

	static function setGenericFactoryMappedType(mapped:haxe.ds.StringMap<String>, param:String, typeName:String):Void {
		if (mapped == null || param == null || param.length == 0 || typeName == null || typeName.length == 0)
			return;
		final clean = sanitizeIdentifier(param);
		final existing = mapped.get(clean);
		if (existing == null || existing.length == 0 || existing == typeName)
			mapped.set(clean, typeName);
	}

	static function genericFactoryActualCppType(expr:HxExpr, scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		if (explicit.length > 0)
			return explicit;
		return inferExprCppType(expr, scope);
	}

	static function setGenericFactoryLocalTypeOverride(scope:CppRenderScope, local:String, className:String, params:Array<String>,
			mapped:haxe.ds.StringMap<String>):Void {
		if (scope == null || local == null || local.length == 0 || className == null || className.length == 0 || params.length == 0)
			return;
		final args = new Array<String>();
		for (param in params) {
			final value = mapped == null ? null : mapped.get(sanitizeIdentifier(param));
			if (value == null || value.length == 0)
				return;
			args.push(value);
		}
		final typeName = "std::shared_ptr<" + className + "<" + args.join(", ") + ">>";
		final existing = scope.localTypeOverrides.get(local);
		if (existing != null && existing.length > 0 && existing != typeName)
			return;
		scope.localTypeOverrides.set(local, typeName);
		scope.localTypes.set(local, typeName);
	}

	static function withGenericFactoryInferenceScope(scope:CppRenderScope, candidates:haxe.ds.StringMap<String>,
			mapped:haxe.ds.StringMap<haxe.ds.StringMap<String>>, fn:Void->Void):Void {
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalTypeOverrides = copyStringMap(scope.localTypeOverrides);
		final savedLocalNames = copyStringMap(scope.localNames);
		final savedLocalNameCounts = copyIntMap(scope.localNameCounts);
		final savedCandidates = copyStringMap(candidates);
		final savedMapped = copyNestedStringMap(mapped);
		fn();
		scope.localTypes = savedLocalTypes;
		scope.localTypeOverrides = savedLocalTypeOverrides;
		scope.localNames = savedLocalNames;
		scope.localNameCounts = savedLocalNameCounts;
		restoreStringMap(candidates, savedCandidates);
		restoreNestedStringMap(mapped, savedMapped);
	}

	static function collectDynamicLocalTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectDynamicLocalTypeOverridesFromStmt(s, scope, candidates);
			case SIf(cond, thenBranch, elseBranch, _):
				collectDynamicLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectDynamicLocalTypeOverridesFromStmt(thenBranch, scope, candidates);
				if (elseBranch != null)
					collectDynamicLocalTypeOverridesFromStmt(elseBranch, scope, candidates);
			case SForIn(name, iterable, body, _):
				collectDynamicLocalTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectDynamicLocalTypeOverridesFromStmt(body, scope, candidates);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectDynamicLocalTypeOverridesFromExpr(iterable, scope, candidates);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectDynamicLocalTypeOverridesFromStmt(body, scope, candidates);
					});
				});
			case SWhile(cond, body, _):
				collectDynamicLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectDynamicLocalTypeOverridesFromStmt(body, scope, candidates);
			case SDoWhile(body, cond, _):
				collectDynamicLocalTypeOverridesFromStmt(body, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(cond, scope, candidates);
			case SSwitch(scrutinee, _, bodies, _):
				collectDynamicLocalTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (body in bodies)
					collectDynamicLocalTypeOverridesFromStmt(body, scope, candidates);
			case STry(tryBody, catches, _):
				collectDynamicLocalTypeOverridesFromStmt(tryBody, scope, candidates);
				for (c in catches)
					collectDynamicLocalTypeOverridesFromStmt(c.body, scope, candidates);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectDynamicLocalTypeOverridesFromExpr(init, scope, candidates);
				final local = sanitizeIdentifier(name);
				final localType = cppLocalTypeHint(typeHint, init, scope);
				if (isLocalCallableInit(init) && isCppFunctionType(localType)) {
					candidates.set(local, true);
					scope.localTypes.set(local, localType);
					return;
				}
				final inferredCallableType = inferredLocalCallableType(init, scope);
				if (isLocalCallableInit(init) && localType.length == 0 && inferredCallableType.length > 0) {
					candidates.set(local, true);
					scope.localTypes.set(local, inferredCallableType);
					setDynamicLocalTypeOverride(scope, local, inferredCallableType);
					return;
				}
				if (isLocalCallableInit(init) && localType.length == 0) {
					candidates.set(local, true);
					return;
				}
				final unhintedNoInit = isUnhintedNoInitLocal(typeHint, init);
				final unhintedEmptyArray = isUnhintedEmptyArray(typeHint, init);
				final unhintedNull = isUnhintedNullLocal(typeHint, init);
				if (isDynamicLikeTypeHint(typeHint) || unhintedNoInit || unhintedEmptyArray || unhintedNull) {
					candidates.set(local, true);
					final inferred = init == null || unhintedEmptyArray ? "" : dynamicLocalAssignedType(init, scope);
					if (inferred.length > 0)
						setDynamicLocalTypeOverride(scope, local, inferred);
					else if (!unhintedNoInit)
						scope.localTypes.set(local, "std::string");
				} else {
					if (localType.length > 0)
						scope.localTypes.set(local, localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectDynamicLocalTypeOverridesFromExpr(expr, scope, candidates);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function collectDynamicLocalTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		if (!boolMapHasEntries(candidates))
			return;
		switch (expr) {
			case EBinop("=", EIdent(name), rhs) if (candidates.exists(sanitizeIdentifier(name))):
				collectDynamicLocalTypeOverridesFromExpr(rhs, scope, candidates);
				final inferred = dynamicLocalAssignedType(rhs, scope);
				if (inferred.length > 0)
					setDynamicLocalTypeOverride(scope, sanitizeIdentifier(name), inferred);
			case ECall(EField(EIdent(name), "push"), [value]) if (candidates.exists(sanitizeIdentifier(name))):
				collectDynamicLocalTypeOverridesFromExpr(value, scope, candidates);
				final inferred = dynamicLocalAssignedType(value, scope);
				if (inferred.length > 0)
					setDynamicLocalTypeOverride(scope, sanitizeIdentifier(name), "std::vector<" + inferred + ">");
			case EBinop(_, left, right):
				collectDynamicLocalTypeOverridesFromExpr(left, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(right, scope, candidates);
			case ECall(EIdent(name), args) if (candidates.exists(sanitizeIdentifier(name))):
				refineLocalCallableTypeFromCall(scope, sanitizeIdentifier(name), args);
				for (arg in args)
					collectDynamicLocalTypeOverridesFromExpr(arg, scope, candidates);
			case ECall(EIdent(methodName), args):
				collectSameOwnerDeclaredArgTypeOverrides(methodName, args, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(EIdent(methodName), scope, candidates);
				for (arg in args)
					collectDynamicLocalTypeOverridesFromExpr(arg, scope, candidates);
			case ECall(callee, args):
				collectForwardedCallArgTypeOverrides(callee, args, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(callee, scope, candidates);
				for (arg in args)
					collectDynamicLocalTypeOverridesFromExpr(arg, scope, candidates);
			case EArrayAccess(array, index):
				collectDynamicLocalTypeOverridesFromExpr(array, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(index, scope, candidates);
			case EField(receiver, _):
				collectDynamicLocalTypeOverridesFromExpr(receiver, scope, candidates);
			case EArrayDecl(elements):
				for (element in elements)
					collectDynamicLocalTypeOverridesFromExpr(element, scope, candidates);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectDynamicLocalTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectDynamicLocalTypeOverridesFromExpr(guardExpr, scope, candidates);
					collectDynamicLocalTypeOverridesFromExpr(yieldExpr, scope, candidates);
				});
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectDynamicLocalTypeOverridesFromExpr(inner, scope, candidates);
			case ETernary(cond, thenExpr, elseExpr):
				collectDynamicLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(thenExpr, scope, candidates);
				collectDynamicLocalTypeOverridesFromExpr(elseExpr, scope, candidates);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectDynamicLocalTypeOverridesFromExpr(value, scope, candidates);
			case ESwitch(scrutinee, _, exprs):
				collectDynamicLocalTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (value in exprs)
					collectDynamicLocalTypeOverridesFromExpr(value, scope, candidates);
			case ELambda(_, body):
				collectDynamicLocalTypeOverridesFromExpr(body, scope, candidates);
			case ENew(_, args):
				for (arg in args)
					collectDynamicLocalTypeOverridesFromExpr(arg, scope, candidates);
			case _:
		}
	}

	static function dynamicLocalAssignedType(expr:HxExpr, scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		final inferred = explicit.length > 0 ? explicit : inferExprCppType(expr, scope);
		return inferred.length > 0 ? inferred : "";
	}

	static function isLocalCallableInit(init:Null<HxExpr>):Bool {
		return switch (init) {
			case ELambda(_, _):
				true;
			case ECall(EIdent("__hxhx_optional_lambda"), _):
				true;
			case _:
				false;
		};
	}

	static function inferredLocalCallableType(init:Null<HxExpr>, scope:CppRenderScope):String {
		return switch (init) {
			case ELambda(args, body) if (args.length == 0):
				final returnType = inferExprCppType(body, scope);
				returnType.length == 0 ? "" : "std::function<" + returnType + "()>";
			case _:
				"";
		};
	}

	static function refineLocalCallableTypeFromCall(scope:CppRenderScope, local:String, args:Array<HxExpr>):Void {
		if (scope == null || local == null || local.length == 0)
			return;
		final current = scope.localTypes.get(local);
		if (!isCppFunctionType(current))
			return;
		final argTypes = [for (arg in args) callableArgExprType(arg, scope)].filter(t -> t.length > 0);
		if (argTypes.length != args.length)
			return;
		final returnType = cppFunctionReturnTypeFromCppType(current);
		if (returnType.length == 0)
			return;
		final refined = "std::function<" + returnType + "(" + argTypes.join(", ") + ")>";
		setDynamicLocalTypeOverride(scope, local, refined);
		scope.localTypes.set(local, refined);
	}

	static function setDynamicLocalTypeOverride(scope:CppRenderScope, local:String, typeName:String):Void {
		if (scope == null || local == null || local.length == 0 || typeName == null || typeName.length == 0)
			return;
		final existing = scope.localTypeOverrides.get(local);
		if (existing != null && existing.length > 0 && existing != typeName)
			return;
		scope.localTypeOverrides.set(local, typeName);
		scope.localTypes.set(local, typeName);
	}

	static function inferHelperTypedAsLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null)
			return;
		final savedLocalTypes = copyStringMap(scope.localTypes);
		for (stmt in HxFunctionDecl.getBody(fn))
			collectHelperTypedAsLocalTypeOverridesFromStmt(stmt, scope);
		scope.localTypes = savedLocalTypes;
	}

	static function collectHelperTypedAsLocalTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectHelperTypedAsLocalTypeOverridesFromStmt(s, scope);
			case SIf(cond, thenBranch, elseBranch, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(cond, scope);
				collectHelperTypedAsLocalTypeOverridesFromStmt(thenBranch, scope);
				if (elseBranch != null)
					collectHelperTypedAsLocalTypeOverridesFromStmt(elseBranch, scope);
			case SForIn(name, iterable, body, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectHelperTypedAsLocalTypeOverridesFromStmt(body, scope);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(iterable, scope);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectHelperTypedAsLocalTypeOverridesFromStmt(body, scope);
					});
				});
			case SWhile(cond, body, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(cond, scope);
				collectHelperTypedAsLocalTypeOverridesFromStmt(body, scope);
			case SDoWhile(body, cond, _):
				collectHelperTypedAsLocalTypeOverridesFromStmt(body, scope);
				collectHelperTypedAsLocalTypeOverridesFromExpr(cond, scope);
			case SSwitch(scrutinee, _, bodies, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(scrutinee, scope);
				for (body in bodies)
					collectHelperTypedAsLocalTypeOverridesFromStmt(body, scope);
			case STry(tryBody, catches, _):
				collectHelperTypedAsLocalTypeOverridesFromStmt(tryBody, scope);
				for (c in catches)
					collectHelperTypedAsLocalTypeOverridesFromStmt(c.body, scope);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectHelperTypedAsLocalTypeOverridesFromExpr(init, scope);
				final local = sanitizeIdentifier(name);
				final localType = inferredLocalTypeForArgInference(typeHint, init, scope);
				if (isUsefulHelperTypedAsOverrideType(localType))
					scope.localTypes.set(local, localType);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(expr, scope);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function collectHelperTypedAsLocalTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope):Void {
		switch (expr) {
			case ECall(callee, [EIdent(name), expected]) if (isHelperMacrosTypedAsCallee(callee)):
				collectHelperTypedAsLocalTypeOverridesFromExpr(expected, scope);
				final expectedType = helperTypedAsExpectedCppType(expected, scope);
				if (isUsefulHelperTypedAsOverrideType(expectedType))
					setHelperTypedAsLocalTypeOverride(scope, sanitizeIdentifier(name), expectedType);
			case ECall(callee, args):
				collectHelperTypedAsLocalTypeOverridesFromExpr(callee, scope);
				for (arg in args)
					collectHelperTypedAsLocalTypeOverridesFromExpr(arg, scope);
			case EBinop(_, left, right):
				collectHelperTypedAsLocalTypeOverridesFromExpr(left, scope);
				collectHelperTypedAsLocalTypeOverridesFromExpr(right, scope);
			case EArrayAccess(array, index):
				collectHelperTypedAsLocalTypeOverridesFromExpr(array, scope);
				collectHelperTypedAsLocalTypeOverridesFromExpr(index, scope);
			case EField(receiver, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(receiver, scope);
			case EArrayDecl(elements):
				for (element in elements)
					collectHelperTypedAsLocalTypeOverridesFromExpr(element, scope);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectHelperTypedAsLocalTypeOverridesFromExpr(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectHelperTypedAsLocalTypeOverridesFromExpr(guardExpr, scope);
					collectHelperTypedAsLocalTypeOverridesFromExpr(yieldExpr, scope);
				});
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectHelperTypedAsLocalTypeOverridesFromExpr(inner, scope);
			case ETernary(cond, thenExpr, elseExpr):
				collectHelperTypedAsLocalTypeOverridesFromExpr(cond, scope);
				collectHelperTypedAsLocalTypeOverridesFromExpr(thenExpr, scope);
				collectHelperTypedAsLocalTypeOverridesFromExpr(elseExpr, scope);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectHelperTypedAsLocalTypeOverridesFromExpr(value, scope);
			case ESwitch(scrutinee, _, exprs):
				collectHelperTypedAsLocalTypeOverridesFromExpr(scrutinee, scope);
				for (value in exprs)
					collectHelperTypedAsLocalTypeOverridesFromExpr(value, scope);
			case ELambda(_, body):
				collectHelperTypedAsLocalTypeOverridesFromExpr(body, scope);
			case ENew(_, args):
				for (arg in args)
					collectHelperTypedAsLocalTypeOverridesFromExpr(arg, scope);
			case _:
		}
	}

	static function helperTypedAsExpectedCppType(expr:HxExpr, scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		if (explicit.length > 0)
			return explicit;
		return inferExprCppType(expr, scope);
	}

	static function setHelperTypedAsLocalTypeOverride(scope:CppRenderScope, local:String, typeName:String):Void {
		if (scope == null || local == null || local.length == 0 || !isUsefulHelperTypedAsOverrideType(typeName))
			return;
		final existing = scope.localTypeOverrides.get(local);
		if (existing != null && existing.length > 0 && existing != typeName && existing != "std::any")
			return;
		scope.localTypeOverrides.set(local, typeName);
		scope.localTypes.set(local, typeName);
	}

	static function isUsefulHelperTypedAsOverrideType(typeName:String):Bool {
		if (typeName == null || typeName.length == 0)
			return false;
		return typeName != "void" && typeName != "auto" && typeName != "std::any" && !isBareCppTypeParamName(typeName);
	}

	static function inferReturnLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl):Void {
		if (scope == null || fn == null || !isUsefulReturnLocalOverrideType(scope.returnType))
			return;
		for (stmt in HxFunctionDecl.getBody(fn))
			collectReturnLocalTypeOverridesFromStmt(stmt, scope, scope.returnType);
	}

	static function collectReturnLocalTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, returnType:String):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectReturnLocalTypeOverridesFromStmt(s, scope, returnType);
			case SIf(_, thenBranch, elseBranch, _):
				collectReturnLocalTypeOverridesFromStmt(thenBranch, scope, returnType);
				if (elseBranch != null)
					collectReturnLocalTypeOverridesFromStmt(elseBranch, scope, returnType);
			case SWhile(_, body, _) | SDoWhile(body, _, _):
				collectReturnLocalTypeOverridesFromStmt(body, scope, returnType);
			case SSwitch(_, _, bodies, _):
				for (body in bodies)
					collectReturnLocalTypeOverridesFromStmt(body, scope, returnType);
			case STry(tryBody, catches, _):
				collectReturnLocalTypeOverridesFromStmt(tryBody, scope, returnType);
				for (c in catches)
					collectReturnLocalTypeOverridesFromStmt(c.body, scope, returnType);
			case SReturn(EIdent(name), _):
				setReturnLocalTypeOverride(scope, sanitizeIdentifier(name), returnType);
			case _:
		}
	}

	static function setReturnLocalTypeOverride(scope:CppRenderScope, local:String, typeName:String):Void {
		if (scope == null || local == null || local.length == 0 || typeName == null || typeName.length == 0)
			return;
		final existing = scope.localTypeOverrides.get(local);
		if (existing != null && existing.length > 0 && existing != typeName)
			return;
		scope.localTypeOverrides.set(local, typeName);
	}

	static function isUsefulReturnLocalOverrideType(typeName:String):Bool {
		return typeName != null
			&& typeName.length > 0
			&& typeName != "void"
			&& typeName != "std::string"
			&& isCppReferenceType(typeName);
	}

	static function collectForwardedConstructorArgTypeOverrides(stmts:Array<HxStmt>, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		final expectedTypes = baseConstructorArgCppTypes(scope);
		if (expectedTypes.length == 0)
			return;
		for (stmt in stmts)
			switch (stmt) {
				case SExpr(ECall(ESuper, args), _):
					for (i in 0...args.length)
						switch (args[i]) {
							case EIdent(name) if (i < expectedTypes.length && candidates.exists(sanitizeIdentifier(name))):
								final expectedType = expectedTypes[i];
								if (expectedType.length > 0 && expectedType != "std::string") {
									final local = sanitizeIdentifier(name);
									scope.argTypeOverrides.set(local, expectedType);
									scope.localTypes.set(local, expectedType);
								}
							case _:
						}
					return;
				case _:
			}
	}

	static function baseConstructorArgCppTypes(?scope:CppRenderScope):Array<String> {
		final baseType = scope == null || scope.owner == null ? null : baseTypeName(scope.owner);
		return baseType == null ? [] : constructorArgCppTypes(baseType, scope);
	}

	static function collectAssignedArgTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectAssignedArgTypeOverridesFromStmt(s, scope, candidates);
			case SIf(cond, thenBranch, elseBranch, _):
				collectAssignedArgTypeOverridesFromExpr(cond, scope, candidates);
				collectAssignedArgTypeOverridesFromStmt(thenBranch, scope, candidates);
				if (elseBranch != null)
					collectAssignedArgTypeOverridesFromStmt(elseBranch, scope, candidates);
			case SForIn(name, iterable, body, _):
				collectAssignedArgTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectAssignedArgTypeOverridesFromStmt(body, scope, candidates);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectAssignedArgTypeOverridesFromExpr(iterable, scope, candidates);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectAssignedArgTypeOverridesFromStmt(body, scope, candidates);
					});
				});
			case SWhile(cond, body, _):
				collectAssignedArgTypeOverridesFromExpr(cond, scope, candidates);
				collectAssignedArgTypeOverridesFromStmt(body, scope, candidates);
			case SDoWhile(body, cond, _):
				collectAssignedArgTypeOverridesFromStmt(body, scope, candidates);
				collectAssignedArgTypeOverridesFromExpr(cond, scope, candidates);
			case SSwitch(scrutinee, _, bodies, _):
				collectAssignedArgTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (body in bodies)
					collectAssignedArgTypeOverridesFromStmt(body, scope, candidates);
			case STry(tryBody, catches, _):
				collectAssignedArgTypeOverridesFromStmt(tryBody, scope, candidates);
				for (c in catches)
					collectAssignedArgTypeOverridesFromStmt(c.body, scope, candidates);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectAssignedArgTypeOverridesFromExpr(init, scope, candidates);
				final localType = cppLocalTypeHint(typeHint, init, scope);
				if (localType.length > 0) {
					switch (init) {
						case EIdent(argName) if (candidates.exists(sanitizeIdentifier(argName))):
							setAssignedArgTypeOverride(scope, sanitizeIdentifier(argName), localType);
						case _:
					}
					scope.localTypes.set(sanitizeIdentifier(name), localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectAssignedArgTypeOverridesFromExpr(expr, scope, candidates);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function collectAssignedArgTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		switch (expr) {
			case ECall(EField(EIdent(name), "push"), [value]) if (candidates.exists(sanitizeIdentifier(name))):
				collectAssignedArgTypeOverridesFromExpr(value, scope, candidates);
				var elementType = inferExprCppType(value, scope);
				if (elementType.length == 0)
					elementType = callableArgExprType(value, scope);
				if (elementType.length == 0)
					elementType = "std::string";
				final local = sanitizeIdentifier(name);
				final vectorType = "std::vector<" + elementType + ">";
				scope.argTypeOverrides.set(local, vectorType);
				scope.localTypes.set(local, vectorType);
			case EBinop("=", left, EIdent(name)) if (candidates.exists(sanitizeIdentifier(name))):
				final targetType = exprCppType(left, scope);
				if (targetType.length > 0 && targetType != "std::string")
					setAssignedArgTypeOverride(scope, sanitizeIdentifier(name), targetType);
			case EBinop("=", EIdent(name), rhs) if (candidates.exists(sanitizeIdentifier(name))):
				collectAssignedArgTypeOverridesFromExpr(rhs, scope, candidates);
				final assignedType = dynamicLocalAssignedType(rhs, scope);
				if (assignedType.length > 0)
					setAssignedArgTypeOverride(scope, sanitizeIdentifier(name), assignedType);
			case EBinop(_, left, right):
				collectAssignedArgTypeOverridesFromExpr(left, scope, candidates);
				collectAssignedArgTypeOverridesFromExpr(right, scope, candidates);
			case ECall(callee, args):
				collectAssignedArgTypeOverridesFromExpr(callee, scope, candidates);
				for (arg in args)
					collectAssignedArgTypeOverridesFromExpr(arg, scope, candidates);
			case EArrayAccess(array, index):
				collectAssignedArgTypeOverridesFromExpr(array, scope, candidates);
				collectAssignedArgTypeOverridesFromExpr(index, scope, candidates);
			case EField(receiver, _):
				collectAssignedArgTypeOverridesFromExpr(receiver, scope, candidates);
			case EArrayDecl(elements):
				for (element in elements)
					collectAssignedArgTypeOverridesFromExpr(element, scope, candidates);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectAssignedArgTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectAssignedArgTypeOverridesFromExpr(guardExpr, scope, candidates);
					collectAssignedArgTypeOverridesFromExpr(yieldExpr, scope, candidates);
				});
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectAssignedArgTypeOverridesFromExpr(inner, scope, candidates);
			case ETernary(cond, thenExpr, elseExpr):
				collectAssignedArgTypeOverridesFromExpr(cond, scope, candidates);
				collectAssignedArgTypeOverridesFromExpr(thenExpr, scope, candidates);
				collectAssignedArgTypeOverridesFromExpr(elseExpr, scope, candidates);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectAssignedArgTypeOverridesFromExpr(value, scope, candidates);
			case ESwitch(scrutinee, _, exprs):
				collectAssignedArgTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (value in exprs)
					collectAssignedArgTypeOverridesFromExpr(value, scope, candidates);
			case ELambda(_, body):
				collectAssignedArgTypeOverridesFromExpr(body, scope, candidates);
			case ENew(_, args):
				for (arg in args)
					collectAssignedArgTypeOverridesFromExpr(arg, scope, candidates);
			case _:
		}
	}

	static function collectCallableArgTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>, expectedType:String):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectCallableArgTypeOverridesFromStmt(s, scope, candidates, expectedType);
			case SVar(name, typeHint, init, _):
				final localType = inferredLocalTypeForArgInference(typeHint, init, scope);
				if (init != null)
					collectCallableArgTypeOverridesFromExpr(init, scope, candidates, localType);
				scope.localTypes.set(sanitizeIdentifier(name), localType);
			case SIf(cond, thenBranch, elseBranch, _):
				collectCallableArgTypeOverridesFromExpr(cond, scope, candidates, "bool");
				collectCallableArgTypeOverridesFromStmt(thenBranch, scope, candidates, expectedType);
				if (elseBranch != null)
					collectCallableArgTypeOverridesFromStmt(elseBranch, scope, candidates, expectedType);
			case SForIn(name, iterable, body, _):
				collectCallableArgTypeOverridesFromExpr(iterable, scope, candidates, "");
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectCallableArgTypeOverridesFromStmt(body, scope, candidates, expectedType);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectCallableArgTypeOverridesFromExpr(iterable, scope, candidates, "");
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectCallableArgTypeOverridesFromStmt(body, scope, candidates, expectedType);
					});
				});
			case SWhile(cond, body, _):
				collectCallableArgTypeOverridesFromExpr(cond, scope, candidates, "bool");
				collectCallableArgTypeOverridesFromStmt(body, scope, candidates, expectedType);
			case SDoWhile(body, cond, _):
				collectCallableArgTypeOverridesFromStmt(body, scope, candidates, expectedType);
				collectCallableArgTypeOverridesFromExpr(cond, scope, candidates, "bool");
			case SSwitch(scrutinee, _, bodies, _):
				collectCallableArgTypeOverridesFromExpr(scrutinee, scope, candidates, "");
				for (body in bodies)
					collectCallableArgTypeOverridesFromStmt(body, scope, candidates, expectedType);
			case STry(tryBody, catches, _):
				collectCallableArgTypeOverridesFromStmt(tryBody, scope, candidates, expectedType);
				for (c in catches)
					collectCallableArgTypeOverridesFromStmt(c.body, scope, candidates, expectedType);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectCallableArgTypeOverridesFromExpr(expr, scope, candidates, expectedType);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	static function collectCallableArgTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>, expectedType:String):Void {
		if (!exprReferencesCallableArgCandidate(expr, candidates))
			return;
		switch (expr) {
			case EIdent(name) if (candidates.exists(sanitizeIdentifier(name))):
				final overrideType = callableExpectedArgOverrideType(expectedType, scope);
				if (overrideType.length > 0)
					setAssignedArgTypeOverride(scope, sanitizeIdentifier(name), overrideType);
			case ECall(EIdent(name), args) if (candidates.exists(sanitizeIdentifier(name))):
				final argTypesStartTime = Sys.time();
				final argTypes = [for (arg in args) callableArgExprType(arg, scope)].filter(t -> t.length > 0);
				traceCallableArgExprPhase(scope, expr, "candidate_arg_types", Sys.time() - argTypesStartTime, candidates, expectedType);
				if (argTypes.length == args.length) {
					final returnType = expectedType != null && expectedType.length > 0 ? expectedType : "std::string";
					scope.argTypeOverrides.set(sanitizeIdentifier(name), "std::function<" + returnType + "(" + argTypes.join(", ") + ")>");
				}
				final argWalkStartTime = Sys.time();
				for (arg in args)
					collectCallableArgTypeOverridesFromExpr(arg, scope, candidates, "");
				traceCallableArgExprPhase(scope, expr, "candidate_arg_walk", Sys.time() - argWalkStartTime, candidates, expectedType);
			case ECall(callee, args):
				final forwardedStartTime = Sys.time();
				collectForwardedCallArgTypeOverrides(callee, args, scope, candidates);
				traceCallableArgExprPhase(scope, expr, "forwarded", Sys.time() - forwardedStartTime, candidates, expectedType);
				final calleeWalkStartTime = Sys.time();
				collectCallableArgTypeOverridesFromExpr(callee, scope, candidates, "");
				traceCallableArgExprPhase(scope, expr, "callee_walk", Sys.time() - calleeWalkStartTime, candidates, expectedType);
				final calleeTypeStartTime = Sys.time();
				final calleeType = exprCppType(callee, scope);
				traceCallableArgExprPhase(scope, expr, "callee_type", Sys.time() - calleeTypeStartTime, candidates, expectedType);
				final functionArgTypesStartTime = Sys.time();
				final functionArgTypes = CppTypeModel.cppFunctionArgTypesFromCppType(calleeType);
				traceCallableArgExprPhase(scope, expr, "function_arg_types", Sys.time() - functionArgTypesStartTime, candidates, expectedType);
				final argsWalkStartTime = Sys.time();
				for (i in 0...args.length) {
					final argExpected = i < functionArgTypes.length ? functionArgTypes[i] : "";
					collectCallableArgTypeOverridesFromExpr(args[i], scope, candidates, argExpected);
				}
				traceCallableArgExprPhase(scope, expr, "args_walk", Sys.time() - argsWalkStartTime, candidates, expectedType);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectCallableArgTypeOverridesFromExpr(iterable, scope, candidates, "");
				final elementExpected = isCppVectorType(expectedType) ? cppVectorElementType(expectedType) : "";
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectCallableArgTypeOverridesFromExpr(guardExpr, scope, candidates, "bool");
					collectCallableArgTypeOverridesFromExpr(yieldExpr, scope, candidates, elementExpected);
				});
			case EArrayDecl(elements):
				for (element in elements)
					collectCallableArgTypeOverridesFromExpr(element, scope, candidates, "");
			case EArrayAccess(array, index):
				collectCallableArgTypeOverridesFromExpr(array, scope, candidates, "");
				collectCallableArgTypeOverridesFromExpr(index, scope, candidates, "int");
			case EField(receiver, _):
				collectCallableArgTypeOverridesFromExpr(receiver, scope, candidates, "");
			case EBinop(_, left, right):
				final leftExpected = binaryOperandExpectedType(expr, left, right, scope);
				final rightExpected = binaryOperandExpectedType(expr, right, left, scope);
				collectCallableArgTypeOverridesFromExpr(left, scope, candidates, leftExpected);
				collectCallableArgTypeOverridesFromExpr(right, scope, candidates, rightExpected);
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectCallableArgTypeOverridesFromExpr(inner, scope, candidates, expectedType);
			case ETernary(cond, thenExpr, elseExpr):
				collectCallableArgTypeOverridesFromExpr(cond, scope, candidates, "bool");
				collectCallableArgTypeOverridesFromExpr(thenExpr, scope, candidates, expectedType);
				collectCallableArgTypeOverridesFromExpr(elseExpr, scope, candidates, expectedType);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectCallableArgTypeOverridesFromExpr(value, scope, candidates, "");
			case ESwitch(scrutinee, _, exprs):
				collectCallableArgTypeOverridesFromExpr(scrutinee, scope, candidates, "");
				for (value in exprs)
					collectCallableArgTypeOverridesFromExpr(value, scope, candidates, expectedType);
			case ELambda(_, body):
				collectCallableArgTypeOverridesFromExpr(body, scope, candidates, "");
			case ENew(_, args):
				for (arg in args)
					collectCallableArgTypeOverridesFromExpr(arg, scope, candidates, "");
			case _:
		}
	}

	static function inferredLocalTypeForArgInference(typeHint:String, init:HxExpr, scope:CppRenderScope):String {
		final hinted = cppLocalTypeHint(typeHint, init, scope);
		if (hinted.length > 0)
			return hinted;
		return init == null ? "" : inferExprCppType(init, scope);
	}

	static function binaryOperandExpectedType(expr:HxExpr, operand:HxExpr, other:HxExpr, scope:CppRenderScope):String {
		return switch (expr) {
			case EBinop(op, _, _):
				if (isIntegerArithmeticBinaryOp(op)) "int"; else if (isNumericComparisonOp(op)) numericExpectedTypeFromPeer(other,
					scope); else if (op == "+") numericExpectedTypeFromPeer(other, scope); else "";
			case _:
				"";
		};
	}

	static function isIntegerArithmeticBinaryOp(op:String):Bool {
		return op == "-" || op == "*" || op == "%" || op == "<<" || op == ">>" || op == ">>>";
	}

	static function isNumericComparisonOp(op:String):Bool {
		return op == "<" || op == "<=" || op == ">" || op == ">=";
	}

	static function numericExpectedTypeFromPeer(peer:HxExpr, scope:CppRenderScope):String {
		final peerType = callableArgExprType(peer, scope);
		return peerType == "int" || peerType == "double" ? peerType : "";
	}

	static function collectForwardedCallArgTypeOverrides(callee:HxExpr, args:Array<HxExpr>, scope:CppRenderScope, candidates:haxe.ds.StringMap<Bool>):Void {
		if (isHelperMacrosTypedAsCallee(callee))
			return;
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		final paramsStartTime = timingEnabled ? Sys.time() : 0.0;
		final params = knownCallParams(callee, scope);
		if (timingEnabled)
			traceForwardedCallPhase(scope, callee, "known_params", Sys.time() - paramsStartTime, candidates, args, params);
		if (params == null || params.length == 0 || args == null || args.length == 0)
			return;
		var paramTypes:Null<Array<String>> = null;
		var paramTypesLoaded = false;
		function forwardedArgNeedsOverride(arg:HxExpr):Bool {
			return switch (arg) {
				case EIdent(name):
					candidates.exists(sanitizeIdentifier(name));
				case _:
					false;
			};
		}
		function inferredParamTypeAt(paramIndex:Int, argIndex:Int, param:HxFunctionArg, arg:HxExpr):String {
			if (!forwardedArgNeedsOverride(arg)) {
				if (timingEnabled)
					traceForwardedCallPhase(scope, callee, "known_param_types_skipped", 0.0, candidates, args, params, paramIndex, argIndex,
						HxFunctionArg.getName(param), exprKind(arg), "arg_candidate=false");
				return "";
			}
			if (!paramTypesLoaded) {
				final paramTypesStartTime = timingEnabled ? Sys.time() : 0.0;
				paramTypes = knownCallParamCppTypes(callee, scope);
				paramTypesLoaded = true;
				if (timingEnabled)
					traceForwardedCallPhase(scope, callee, "known_param_types", Sys.time() - paramTypesStartTime, candidates, args, params, paramIndex,
						argIndex, HxFunctionArg.getName(param), exprKind(arg), "arg_candidate=true");
			}
			return paramTypes == null || paramIndex >= paramTypes.length ? "" : paramTypes[paramIndex];
		}
		var paramIndex = 0;
		var argIndex = 0;
		while (argIndex < args.length && paramIndex < params.length) {
			final param = params[paramIndex];
			final arg = args[argIndex];
			final matchStartTime = timingEnabled ? Sys.time() : 0.0;
			final matches = callArgMatchesParam(arg, param, scope);
			var canSkip = false;
			if (!matches)
				canSkip = callParamCanBeSkipped(param);
			if (timingEnabled)
				traceForwardedCallPhase(scope, callee, "loop_match", Sys.time()
					- matchStartTime, candidates, args, params, paramIndex, argIndex,
					HxFunctionArg.getName(param), exprKind(arg), "match="
					+ Std.string(matches)
					+ " skippable="
					+ Std.string(canSkip));
			if (matches || !canSkip) {
				final applyStartTime = timingEnabled ? Sys.time() : 0.0;
				applyForwardedArgTypeOverride(arg, param, inferredParamTypeAt(paramIndex, argIndex, param, arg), scope, candidates);
				if (timingEnabled)
					traceForwardedCallPhase(scope, callee, "apply_direct", Sys.time() - applyStartTime, candidates, args, params, paramIndex, argIndex,
						HxFunctionArg.getName(param), exprKind(arg));
				paramIndex++;
				argIndex++;
				continue;
			}
			final laterStartTime = timingEnabled ? Sys.time() : 0.0;
			final later = findLaterMatchingParam(params, arg, paramIndex + 1, scope);
			if (timingEnabled)
				traceForwardedCallPhase(scope, callee, "find_later", Sys.time() - laterStartTime, candidates, args, params, paramIndex, argIndex,
					HxFunctionArg.getName(param), exprKind(arg), "later=" + Std.string(later));
			if (later < 0) {
				final applyFallbackStartTime = timingEnabled ? Sys.time() : 0.0;
				applyForwardedArgTypeOverride(arg, param, inferredParamTypeAt(paramIndex, argIndex, param, arg), scope, candidates);
				if (timingEnabled)
					traceForwardedCallPhase(scope, callee, "apply_fallback", Sys.time() - applyFallbackStartTime, candidates, args, params, paramIndex,
						argIndex, HxFunctionArg.getName(param), exprKind(arg));
				paramIndex++;
				argIndex++;
				continue;
			}
			paramIndex = later;
			final applyLaterStartTime = timingEnabled ? Sys.time() : 0.0;
			applyForwardedArgTypeOverride(arg, params[paramIndex], inferredParamTypeAt(paramIndex, argIndex, params[paramIndex], arg), scope, candidates);
			if (timingEnabled)
				traceForwardedCallPhase(scope, callee, "apply_later", Sys.time() - applyLaterStartTime, candidates, args, params, paramIndex, argIndex,
					HxFunctionArg.getName(params[paramIndex]), exprKind(arg));
			paramIndex++;
			argIndex++;
		}
	}

	static function isHelperMacrosTypedAsCallee(callee:HxExpr):Bool {
		return switch (callee) {
			case EField(EIdent("HelperMacros"), "typedAs"):
				true;
			case EField(EField(EIdent("unit"), "HelperMacros"), "typedAs"):
				true;
			case _:
				false;
		};
	}

	static function isHelperMacrosStringShimReceiver(receiver:HxExpr, method:String):Bool {
		final isHelperMacros = switch (receiver) {
			case EIdent("HelperMacros"):
				true;
			case EField(EIdent("unit"), "HelperMacros"):
				true;
			case _:
				false;
		};
		if (!isHelperMacros)
			return false;
		return switch (sanitizeIdentifier(method)) {
			case "typeString" | "typedAs" | "getMeta" | "pipeMarkupLiteral" | "pipeMarkupLiteralUnprocessed":
				true;
			case _:
				false;
		};
	}

	static function helperMacrosTypeErrorProbeExpr(callee:HxExpr, args:Array<HxExpr>):Null<String> {
		if (args == null || args.length != 1)
			return null;
		final method = switch (callee) {
			case EIdent(name) if (name == "typeError" || name == "typeErrorText"):
				name;
			case EField(EIdent("HelperMacros"), name):
				name;
			case EField(EField(EIdent("unit"), "HelperMacros"), name):
				name;
			case _:
				return null;
		};
		if (method != "typeError" && method != "typeErrorText")
			return null;
		return switch (args[0]) {
			case EField(_, _) | EArrayAccess(_, _) | EBinop("=", _, ECall(_, _)) | EBinop("=", _, EIdent(_)) | EBinop("=", _, ENew(_, _)):
				method == "typeError" ? "true" : "std::string()";
			case _:
				null;
		};
	}

	static function collectSameOwnerDeclaredArgTypeOverrides(methodName:String, args:Array<HxExpr>, scope:CppRenderScope,
			candidates:haxe.ds.StringMap<Bool>):Void {
		final fn = currentOwnerMethod(methodName, scope);
		if (fn == null || args == null || args.length == 0)
			return;
		final params = HxFunctionDecl.getArgs(fn);
		final count = args.length < params.length ? args.length : params.length;
		for (i in 0...count) {
			switch (args[i]) {
				case EIdent(name) if (candidates.exists(sanitizeIdentifier(name))):
					final expectedType = concreteForwardedOverrideType(cppFunctionArgType(params[i], scope), scope);
					if (expectedType.length > 0)
						setDynamicLocalTypeOverride(scope, sanitizeIdentifier(name), expectedType);
				case _:
			}
		}
	}

	static function exprReferencesCallableArgCandidate(expr:HxExpr, candidates:haxe.ds.StringMap<Bool>):Bool {
		if (expr == null || !boolMapHasEntries(candidates))
			return false;
		return switch (expr) {
			case EIdent(name):
				candidates.exists(sanitizeIdentifier(name));
			case EField(receiver, _):
				exprReferencesCallableArgCandidate(receiver, candidates);
			case ECall(callee, args): exprReferencesCallableArgCandidate(callee, candidates) || exprListReferencesCallableArgCandidate(args, candidates);
			case EMacroExpr(inner, _) | EUnop(_, inner) | ECast(inner, _) | EUntyped(inner):
				exprReferencesCallableArgCandidate(inner, candidates);
			case ELambda(args, body): stringListReferencesCallableArgCandidate(args, candidates) || exprReferencesCallableArgCandidate(body, candidates);
			case ESwitch(scrutinee, _, exprs): exprReferencesCallableArgCandidate(scrutinee,
					candidates) || exprListReferencesCallableArgCandidate(exprs, candidates);
			case ENew(_, args) | EArrayDecl(args):
				exprListReferencesCallableArgCandidate(args, candidates);
			case EBinop(_, left, right): exprReferencesCallableArgCandidate(left, candidates) || exprReferencesCallableArgCandidate(right, candidates);
			case ETernary(cond, thenExpr, elseExpr): exprReferencesCallableArgCandidate(cond,
					candidates) || exprReferencesCallableArgCandidate(thenExpr, candidates) || exprReferencesCallableArgCandidate(elseExpr, candidates);
			case EAnon(_, fieldValues):
				exprListReferencesCallableArgCandidate(fieldValues, candidates);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				candidates.exists(sanitizeIdentifier(name))
				|| exprReferencesCallableArgCandidate(iterable, candidates)
				|| (guardExpr != null && exprReferencesCallableArgCandidate(guardExpr, candidates))
				|| exprReferencesCallableArgCandidate(yieldExpr, candidates);
			case EArrayAccess(array, index) | ERange(array, index): exprReferencesCallableArgCandidate(array,
					candidates) || exprReferencesCallableArgCandidate(index, candidates);
			case _:
				false;
		};
	}

	static function exprListReferencesCallableArgCandidate(exprs:Array<HxExpr>, candidates:haxe.ds.StringMap<Bool>):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprReferencesCallableArgCandidate(expr, candidates))
				return true;
		return false;
	}

	static function stringListReferencesCallableArgCandidate(names:Array<String>, candidates:haxe.ds.StringMap<Bool>):Bool {
		if (names == null)
			return false;
		for (name in names)
			if (candidates.exists(sanitizeIdentifier(name)))
				return true;
		return false;
	}

	static function knownCallParams(callee:HxExpr, scope:CppRenderScope):Null<Array<HxFunctionArg>> {
		return switch (callee) {
			case EIdent(name):
				final fn = currentOrInheritedOwnerMethod(name, scope);
				fn == null ? null : HxFunctionDecl.getArgs(fn);
			case EField(receiver, method):
				final staticOwner = staticReceiverClassName(receiver, scope);
				if (staticOwner != null) {
					final fn = classMethodDecl(staticOwner, method, true, scope);
					fn == null ? null : HxFunctionDecl.getArgs(fn);
				} else {
					final ownerType = classNameFromCppExprType(exprCppType(receiver, scope), scope);
					if (ownerType == null)
						null;
					else {
						final fn = classMethodDecl(ownerType, method, false, scope);
						fn == null ? null : HxFunctionDecl.getArgs(fn);
					}
				}
			case _:
				null;
		};
	}

	static function knownCallParamCppTypes(callee:HxExpr, scope:CppRenderScope):Null<Array<String>> {
		final fn = knownCallDecl(callee, scope);
		if (fn == null)
			return null;
		return inferredFunctionArgCppTypes(fn, ownerForKnownCall(callee, scope), scope.classByName, scope.allClasses);
	}

	static function knownCallDecl(callee:HxExpr, scope:CppRenderScope):Null<HxFunctionDecl> {
		return switch (callee) {
			case EIdent(name):
				currentOrInheritedOwnerMethod(name, scope);
			case EField(receiver, method):
				final staticOwner = staticReceiverClassName(receiver, scope);
				if (staticOwner != null) classMethodDecl(staticOwner, method, true, scope); else {
					final ownerType = classNameFromCppExprType(exprCppType(receiver, scope), scope);
					ownerType == null ? null : classMethodDecl(ownerType, method, false, scope);
				}
			case _:
				null;
		};
	}

	static function ownerForKnownCall(callee:HxExpr, scope:CppRenderScope):HxClassDecl {
		return switch (callee) {
			case EIdent(name):
				final owner = currentOrInheritedOwnerMethodOwner(name, scope);
				owner == null ? (scope == null ? null : scope.owner) : owner;
			case EField(receiver, _):
				final staticOwner = staticReceiverClassName(receiver, scope);
				if (staticOwner != null && scope != null && scope.classByName.exists(staticOwner)) scope.classByName.get(staticOwner); else {
					final ownerType = classNameFromCppExprType(exprCppType(receiver, scope), scope);
					ownerType != null
					&& scope != null
					&& scope.classByName.exists(ownerType) ? scope.classByName.get(ownerType) : (scope == null ? null : scope.owner);
				}
			case _:
				scope == null ? null : scope.owner;
		};
	}

	static function applyForwardedArgTypeOverride(arg:HxExpr, param:HxFunctionArg, inferredParamType:String, scope:CppRenderScope,
			candidates:haxe.ds.StringMap<Bool>):Void {
		switch (arg) {
			case EIdent(name) if (candidates.exists(sanitizeIdentifier(name))):
				final paramType = inferredParamType != null
					&& inferredParamType.length > 0 ? inferredParamType : cppFunctionArgType(param, scope);
				final expectedType = concreteForwardedOverrideType(paramType, scope);
				if (expectedType.length > 0) {
					setAssignedArgTypeOverride(scope, sanitizeIdentifier(name), expectedType);
					setDynamicLocalTypeOverride(scope, sanitizeIdentifier(name), expectedType);
				}
			case _:
		}
	}

	static function concreteForwardedOverrideType(typeName:String, ?scope:CppRenderScope):String {
		if (typeName == null || typeName.length == 0 || typeName == "auto" || typeName == "std::any" || typeName == "std::string")
			return "";
		if (genericTypeParamName(typeName).length > 0 || isScopeTypeParam(typeName, scope))
			return "";
		final inner = cppOptionalInnerType(typeName);
		if (inner.length > 0)
			return inner == "std::string" ? "" : inner;
		return typeName;
	}

	static function callableExpectedArgOverrideType(typeName:String, ?scope:CppRenderScope):String {
		if (typeName == null || typeName.length == 0 || typeName == "auto" || typeName == "std::any" || typeName == "std::string")
			return "";
		final inner = cppOptionalInnerType(typeName);
		return inner.length > 0 ? (inner == "std::string" ? "" : inner) : typeName;
	}

	static function callableArgExprType(expr:HxExpr, scope:CppRenderScope):String {
		return switch (expr) {
			case EUnop("post++", inner) | EUnop("post--", inner):
				callableArgExprType(inner, scope);
			case EInt(_):
				"int";
			case EFloat(_):
				"double";
			case EBool(_):
				"bool";
			case EString(_) | EEnumValue(_) | EMacroExpr(_, _) | EMacroType(_):
				"std::string";
			case _:
				inferExprCppType(expr, scope);
		};
	}

	static function withScopedLocal(scope:CppRenderScope, name:String, typeName:String, fn:Void->Void):Void {
		if (scope == null) {
			fn();
			return;
		}
		final hadPrevious = scope.localTypes.exists(name);
		final previous = hadPrevious ? scope.localTypes.get(name) : "";
		final hadPreviousHint = scope.localTypeHints.exists(name);
		final previousHint = hadPreviousHint ? scope.localTypeHints.get(name) : "";
		final hadPreviousName = scope.localNames.exists(name);
		final previousName = hadPreviousName ? scope.localNames.get(name) : "";
		if (typeName != null && typeName.length > 0)
			scope.localTypes.set(name, typeName);
		scope.localNames.set(name, name);
		fn();
		if (hadPrevious)
			scope.localTypes.set(name, previous);
		else
			scope.localTypes.remove(name);
		if (hadPreviousHint)
			scope.localTypeHints.set(name, previousHint);
		else
			scope.localTypeHints.remove(name);
		if (hadPreviousName)
			scope.localNames.set(name, previousName);
		else
			scope.localNames.remove(name);
	}

	static function withLocalScope(scope:CppRenderScope, fn:Void->Void):Void {
		if (scope == null) {
			fn();
			return;
		}
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalTypeOverrides = copyStringMap(scope.localTypeOverrides);
		final savedLocalNames = copyStringMap(scope.localNames);
		fn();
		scope.localTypes = savedLocalTypes;
		scope.localTypeOverrides = savedLocalTypeOverrides;
		scope.localNames = savedLocalNames;
	}

	static function localCppName(name:String, ?scope:CppRenderScope):String {
		final local = sanitizeIdentifier(name);
		if (scope != null && scope.localNames.exists(local))
			return scope.localNames.get(local);
		return local;
	}

	static function bareIdentifierCppName(name:String, ?scope:CppRenderScope):String {
		final local = sanitizeIdentifier(name);
		if (scope != null && scope.localNames.exists(local))
			return scope.localNames.get(local);
		if (scope != null && inheritedInstanceFieldCppType(name, scope).length > 0)
			return "this->" + local;
		return local;
	}

	static function declareLocalName(name:String, ?scope:CppRenderScope):String {
		final local = sanitizeIdentifier(name);
		if (scope == null)
			return local;
		if (!scope.localTypes.exists(local) && !scope.localNames.exists(local)) {
			scope.localNames.set(local, local);
			scope.localNameCounts.set(local, 1);
			return local;
		}
		final next = scope.localNameCounts.exists(local) ? scope.localNameCounts.get(local) + 1 : 2;
		scope.localNameCounts.set(local, next);
		final cppName = local + "_" + next;
		scope.localNames.set(local, cppName);
		return cppName;
	}

	static function cppFunctionArgDefaultType(arg:HxFunctionArg, ?scope:CppRenderScope):String {
		return switch (HxFunctionArg.getDefaultValue(arg)) {
			case Default(expr):
				inferExprCppType(expr, scope);
			case NoDefault:
				"";
		};
	}

	static function cppFunctionArgDefaultSuffix(arg:HxFunctionArg, typeName:String):String {
		if (HxFunctionArg.getIsRest(arg))
			return "";
		final isOptionalType = isCppOptionalType(typeName);
		final isReferenceType = isCppReferenceType(typeName);
		return switch (HxFunctionArg.getDefaultValue(arg)) {
			case NoDefault:
				if (HxFunctionArg.getIsOptional(arg) && (isOptionalType || isReferenceType)) isOptionalType ? " = std::nullopt" : " = nullptr"; else "";
			case Default(ENull):
				if (isOptionalType || isReferenceType) isOptionalType ? " = std::nullopt" : " = nullptr"; else " = " + cppDefaultValue(typeName);
			case Default(expr):
				" = " + renderExpr(expr);
		};
	}

	static function renderStmts(stmts:Array<HxStmt>, indent:String, ?scope:CppRenderScope):Array<String> {
		inferStringMapLocalTypeOverridesFromStmts(scope, stmts);
		final out = new Array<String>();
		for (stmt in stmts) {
			for (line in renderStmt(stmt, indent, scope))
				out.push(line);
		}
		return out;
	}

	static function renderFunctionBody(stmts:Array<HxStmt>, indent:String, ?scope:CppRenderScope):Array<String> {
		final returnType = scope == null ? "int" : scope.returnType;
		if (returnType != "void" && stmts.length == 1) {
			switch (stmts[0]) {
				case SExpr(expr, _):
					return [indent + returnStmtForExpr(expr, scope)];
				case _:
			}
		}
		return renderStmts(stmts, indent, scope);
	}

	static function renderHelperFunctionBody(stmts:Array<HxStmt>, indent:String, ?scope:CppRenderScope):Array<String> {
		final returnType = scope == null ? "int" : scope.returnType;
		if (returnType != "void" && stmts.length == 1) {
			switch (stmts[0]) {
				case SExpr(expr, _):
					return [indent + returnStmtForExpr(expr, scope)];
				case _:
			}
		}
		final out = new Array<String>();
		for (stmt in stmts)
			for (line in renderStmt(stmt, indent, scope))
				out.push(line);
		return out;
	}

	static function renderTracedHelperFunctionBody(ownerName:String, methodName:String, stmts:Array<HxStmt>, indent:String,
			scope:CppRenderScope):Array<String> {
		final returnType = scope == null ? "int" : scope.returnType;
		if (returnType != "void" && stmts.length == 1) {
			switch (stmts[0]) {
				case SExpr(expr, _):
					traceCppMemberPhase(ownerName, "render_helper_method_stmt", methodName, "index=0 kind=SExprReturn begin");
					final out = [indent + returnStmtForExpr(expr, scope)];
					traceCppMemberPhase(ownerName, "render_helper_method_stmt", methodName, "index=0 kind=SExprReturn end");
					return out;
				case _:
			}
		}
		final out = new Array<String>();
		for (i in 0...stmts.length) {
			final stmt = stmts[i];
			final kind = stmtKind(stmt);
			traceCppMemberPhase(ownerName, "render_helper_method_stmt", methodName, "index=" + i + " kind=" + kind + " begin");
			for (line in renderStmt(stmt, indent, scope))
				out.push(line);
			traceCppMemberPhase(ownerName, "render_helper_method_stmt", methodName, "index=" + i + " kind=" + kind + " end");
		}
		return out;
	}

	static function renderTimedHelperFunctionBody(ownerName:String, methodName:String, stmts:Array<HxStmt>, indent:String, scope:CppRenderScope):Array<String> {
		final priorTraceOwner = scope.traceOwnerName;
		final priorTraceMethod = scope.traceMethodName;
		final priorTraceStmtIndex = scope.traceStmtIndex;
		scope.traceOwnerName = ownerName;
		scope.traceMethodName = methodName;
		final returnType = scope == null ? "int" : scope.returnType;
		if (returnType != "void" && stmts.length == 1) {
			switch (stmts[0]) {
				case SExpr(expr, _):
					scope.traceStmtIndex = 0;
					final startTime = Sys.time();
					final out = [indent + returnStmtForExpr(expr, scope)];
					final elapsed = Sys.time() - startTime;
					traceCppTimingPhase("render_helper_stmt_timing owner=" + ownerName + " name=" + sanitizeIdentifier(methodName)
						+ " index=0 kind=SExprReturn seconds=" + Std.string(elapsed) + " lines=" + out.length);
					scope.traceOwnerName = priorTraceOwner;
					scope.traceMethodName = priorTraceMethod;
					scope.traceStmtIndex = priorTraceStmtIndex;
					return out;
				case _:
			}
		}
		final out = new Array<String>();
		for (i in 0...stmts.length) {
			final stmt = stmts[i];
			final kind = stmtKind(stmt);
			final startTime = Sys.time();
			final before = out.length;
			scope.traceStmtIndex = i;
			for (line in renderStmt(stmt, indent, scope))
				out.push(line);
			final elapsed = Sys.time() - startTime;
			traceCppTimingPhase("render_helper_stmt_timing owner=" + ownerName + " name=" + sanitizeIdentifier(methodName) + " index=" + i + " kind=" + kind
				+ " seconds=" + Std.string(elapsed) + " lines=" + (out.length - before));
		}
		scope.traceOwnerName = priorTraceOwner;
		scope.traceMethodName = priorTraceMethod;
		scope.traceStmtIndex = priorTraceStmtIndex;
		return out;
	}

	static function renderStmt(stmt:HxStmt, indent:String, ?scope:CppRenderScope):Array<String> {
		return switch (stmt) {
			case SBlock(stmts, _):
				final out = [indent + "{"];
				withLocalScope(scope, () -> {
					for (line in renderStmts(stmts, indent + "  ", scope))
						out.push(line);
				});
				out.push(indent + "}");
				out;
			case SIf(cond, thenBranch, elseBranch, _):
				final out = [indent + "if " + cStyleConditionExpr(cond, scope) + " {"];
				withLocalScope(scope, () -> {
					for (line in renderStmtBlockContent(thenBranch, indent + "  ", scope))
						out.push(line);
				});
				if (elseBranch == null) {
					out.push(indent + "}");
				} else {
					out.push(indent + "} else {");
					withLocalScope(scope, () -> {
						for (line in renderStmtBlockContent(elseBranch, indent + "  ", scope))
							out.push(line);
					});
					out.push(indent + "}");
				}
				out;
			case SWhile(cond, body, _):
				final out = [indent + "while " + cStyleConditionExpr(cond, scope) + " {"];
				withLocalScope(scope, () -> {
					for (line in renderStmtBlockContent(body, indent + "  ", scope))
						out.push(line);
				});
				out.push(indent + "}");
				out;
			case SDoWhile(body, cond, _):
				final out = [indent + "do {"];
				withLocalScope(scope, () -> {
					for (line in renderStmtBlockContent(body, indent + "  ", scope))
						out.push(line);
				});
				out.push(indent + "} while " + cStyleConditionExpr(cond, scope) + ";");
				out;
			case SForIn(name, iterable, body, _):
				renderForInStmt(name, iterable, body, indent, scope);
			case SForKeyValue(keyName, valueName, iterable, body, _):
				renderForKeyValueStmt(keyName, valueName, iterable, body, indent, scope);
			case SSwitch(scrutinee, patterns, bodies, _):
				renderSwitchStmt(scrutinee, patterns, bodies, indent, scope);
			case STry(tryBody, catches, _):
				renderTryStmt(tryBody, catches, indent, scope);
			case SExpr(ECall(EField(EIdent("Sys"), "println"), args), _) if (args.length == 1):
				[indent + "std::cout << " + stringExpr(args[0], scope) + " << std::endl;"];
			case SExpr(ECall(EIdent("trace"), args), _) if (args.length >= 1):
				[indent + "std::cout << " + stringExpr(args[0], scope) + " << std::endl;"];
			case SExpr(ECall(ESuper, _), _):
				[indent + "/* base constructor call omitted */"];
			case SExpr(EBinop("=", EThis, EAnon(fieldNames, fieldValues)), _):
				final abstractAnonAssignment = abstractThisAnonAssignmentLines(fieldNames, fieldValues, indent, scope);
				abstractAnonAssignment == null ? [
					indent + renderExpr(EBinop("=", EThis, EAnon(fieldNames, fieldValues)), scope) + ";"
				] : abstractAnonAssignment;
			case SExpr(expr, _):
				final macroApiCall = macroApiCallExprForExpected(expr, "void", scope);
				[indent + (macroApiCall == null ? renderExpr(expr, scope) : macroApiCall) + ";"];
			case SThrow(expr, _):
				[indent + "throw std::runtime_error(" + stringExpr(expr, scope) + ");"];
			case SVar(name, typeHint, init, _):
				final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
				final sourceLocal = sanitizeIdentifier(name);
				final hadPreviousName = scope != null && scope.localNames.exists(sourceLocal);
				final previousName = hadPreviousName ? scope.localNames.get(sourceLocal) : "";
				final localName = declareLocalName(name, scope);
				final localTypeStart = timingEnabled ? Sys.time() : 0.0;
				final localType = cppLocalDeclaredType(name, typeHint, init, scope, localName);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"svar_phase=local_type local="
						+ localName
						+ " seconds="
						+ Std.string(Sys.time() - localTypeStart)
						+ " cpp_type="
						+ traceCppSnippet(localType));
				final hasExplicitType = StringTools.trim(typeHint == null ? "" : typeHint).length > 0;
				final declaredType = (hasExplicitType || init == null) && localType.length > 0 ? localType : "auto";
				if (scope != null) {
					if (hadPreviousName)
						scope.localNames.set(sourceLocal, previousName);
					else
						scope.localNames.remove(sourceLocal);
				}
				final rhsStart = timingEnabled ? Sys.time() : 0.0;
				final rhs = init == null ? cppDefaultValue(declaredType == "auto" ? "int" : declaredType,
					scope) : renderLocalInitExpr(init, declaredType, localType, scope);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"svar_phase=rhs local="
						+ localName
						+ " seconds="
						+ Std.string(Sys.time() - rhsStart)
						+ " declared_type="
						+ traceCppSnippet(declaredType)
						+ " rhs="
						+ traceCppSnippet(rhs));
				if (scope != null)
					scope.localNames.set(sourceLocal, localName);
				if (scope != null) {
					scope.localTypes.set(sanitizeIdentifier(name), localType);
					if (localName != sanitizeIdentifier(name))
						scope.localTypes.set(localName, localType);
					recordLocalTypeHint(scope, sanitizeIdentifier(name), typeHint);
				}
				[indent + declaredType + " " + localName + " = " + rhs + ";"];
			case SReturn(expr, _):
				[indent + returnStmtForExpr(expr, scope)];
			case SReturnVoid(_):
				[indent + returnVoidStmt(scope)];
			case SBreak(_):
				[indent + "break;"];
			case SContinue(_):
				[indent + "continue;"];
			case _:
				throw "C++ source backend MVP unsupported statement: " + stmtKind(stmt);
		};
	}

	/**
		Lower the C++ MVP subset of Haxe `for (x in iterable)` statements.

		Range loops (`a...b`) are emitted as integer counter loops to preserve Haxe's
		exclusive upper bound. Other currently supported iterables are emitted as C++
		range-for loops, which works for the vectors/strings produced by this backend.
		Full Haxe iterator-protocol lowering is intentionally not claimed here.
	**/
	static function renderForInStmt(name:String, iterable:HxExpr, body:HxStmt, indent:String, ?scope:CppRenderScope):Array<String> {
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		final local = sanitizeIdentifier(name);
		final iteratorTypeStart = timingEnabled ? Sys.time() : 0.0;
		final iteratorElementType = iteratorProtocolElementType(iterable, scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"forin_phase=iterator_protocol seconds="
				+ Std.string(Sys.time() - iteratorTypeStart)
				+ " local="
				+ local
				+ " iterable="
				+ exprKind(iterable)
				+ " element_type="
				+ traceCppSnippet(iteratorElementType));
		final out = if (iteratorElementType.length > 0) {
			final iteratorLocal = "__hxhx_iter_" + local;
			final accessTypeStart = timingEnabled ? Sys.time() : 0.0;
			final iterableType = exprCppType(iterable, scope);
			if (timingEnabled)
				traceCppScopeStmtTimingPhase(scope,
					"forin_phase=iterator_access_type seconds="
					+ Std.string(Sys.time() - accessTypeStart)
					+ " iterable="
					+ exprKind(iterable)
					+ " cpp_type="
					+ traceCppSnippet(iterableType));
			final access = isCppReferenceType(iterableType) ? "->" : ".";
			final renderIterableStart = timingEnabled ? Sys.time() : 0.0;
			final renderedIterable = renderExpr(iterable, scope);
			if (timingEnabled)
				traceCppScopeStmtTimingPhase(scope,
					"forin_phase=iterator_render_iterable seconds="
					+ Std.string(Sys.time() - renderIterableStart)
					+ " iterable="
					+ exprKind(iterable)
					+ " rendered="
					+ traceCppSnippet(renderedIterable));
			[indent + "auto " + iteratorLocal + " = " + renderedIterable + ";",
				indent
				+ "while ("
				+ iteratorLocal
				+ access
				+ "hasNext()) {",
				indent
				+ "  auto "
				+ local
				+ " = "
				+ iteratorLocal
				+ access
				+ "next();"];
		} else switch (iterable) {
			case ERange(start, end):
				final startRenderStart = timingEnabled ? Sys.time() : 0.0;
				final renderedStart = renderExpr(start, scope);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"forin_phase=range_start seconds="
						+ Std.string(Sys.time() - startRenderStart)
						+ " expr="
						+ exprKind(start)
						+ " rendered="
						+ traceCppSnippet(renderedStart));
				final endRenderStart = timingEnabled ? Sys.time() : 0.0;
				final renderedEnd = renderExpr(end, scope);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"forin_phase=range_end seconds="
						+ Std.string(Sys.time() - endRenderStart)
						+ " expr="
						+ exprKind(end)
						+ " rendered="
						+ traceCppSnippet(renderedEnd));
				[
					indent + "for (int " + local + " = " + renderedStart + "; " + local + " < " + renderedEnd + "; " + local + "++) {"
				];
			case _:
				final renderIterableStart = timingEnabled ? Sys.time() : 0.0;
				final renderedIterable = renderExpr(iterable, scope);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"forin_phase=range_for_iterable seconds="
						+ Std.string(Sys.time() - renderIterableStart)
						+ " iterable="
						+ exprKind(iterable)
						+ " rendered="
						+ traceCppSnippet(renderedIterable));
				[indent + "for (auto " + local + " : " + renderedIterable + ") {"];
		}
		final loopElementStart = timingEnabled ? Sys.time() : 0.0;
		final loopElementType = iteratorElementType.length > 0 ? iteratorElementType : iterableElementType(iterable, scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"forin_phase=loop_element_type seconds="
				+ Std.string(Sys.time() - loopElementStart)
				+ " local="
				+ local
				+ " element_type="
				+ traceCppSnippet(loopElementType));
		final bodyStart = timingEnabled ? Sys.time() : 0.0;
		final bodyLineStart = out.length;
		withScopedLocal(scope, local, loopElementType, () -> {
			for (line in renderStmtBlockContent(body, indent + "  ", scope))
				out.push(line);
		});
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"forin_phase=body seconds="
				+ Std.string(Sys.time() - bodyStart)
				+ " local="
				+ local
				+ " lines="
				+ Std.string(out.length - bodyLineStart));
		out.push(indent + "}");
		return out;
	}

	static function renderForKeyValueStmt(keyName:String, valueName:String, iterable:HxExpr, body:HxStmt, indent:String, ?scope:CppRenderScope):Array<String> {
		final keyLocal = sanitizeIdentifier(keyName);
		final valueLocal = sanitizeIdentifier(valueName);
		final indexLocal = "__hxhx_kv_" + keyLocal;
		final source = renderExpr(iterable, scope);
		final iterableType = exprCppType(iterable, scope);
		final mapKeyType = mapKeyCppType(iterableType);
		final mapValueType = mapValueCppType(iterableType);
		if (mapKeyType.length > 0 && mapValueType.length > 0) {
			final mapLocal = "__hxhx_kv_map_" + keyLocal;
			final keysLocal = "__hxhx_kv_keys_" + keyLocal;
			final access = isCppReferenceType(iterableType) ? "->" : ".";
			final out = [indent + "auto " + mapLocal + " = " + source + ";",
				indent + "auto " + keysLocal + " = " + mapLocal + access + "keys();",
				indent + "while (" + keysLocal + "->hasNext()) {",
				indent + "  auto " + keyLocal + " = " + keysLocal + "->next();",
				indent
				+ "  auto "
				+ valueLocal
				+ " = "
				+ mapValueLookupExpr(mapLocal, keyLocal, iterableType, mapValueType)
				+ ";"];
			withScopedLocal(scope, keyLocal, mapKeyType, () -> {
				withScopedLocal(scope, valueLocal, mapValueType, () -> {
					for (line in renderStmtBlockContent(body, indent + "  ", scope))
						out.push(line);
				});
			});
			out.push(indent + "}");
			return out;
		}
		final elementType = iterableElementType(iterable, scope);
		final pairArgs = cppPairTypeArgs(elementType);
		final out = [
			indent + "for (std::size_t " + indexLocal + " = 0; " + indexLocal + " < " + source + ".size(); ++" + indexLocal + ") {"
		];
		if (pairArgs.length == 2) {
			final pairLocal = "__hxhx_kv_pair_" + keyLocal;
			out.push(indent + "  auto " + pairLocal + " = " + source + "[" + indexLocal + "];");
			out.push(indent + "  auto " + keyLocal + " = " + pairLocal + ".first;");
			out.push(indent + "  auto " + valueLocal + " = " + pairLocal + ".second;");
			withScopedLocal(scope, keyLocal, pairArgs[0], () -> {
				withScopedLocal(scope, valueLocal, pairArgs[1], () -> {
					for (line in renderStmtBlockContent(body, indent + "  ", scope))
						out.push(line);
				});
			});
		} else {
			out.push(indent + "  auto " + keyLocal + " = static_cast<int>(" + indexLocal + ");");
			out.push(indent + "  auto " + valueLocal + " = " + source + "[" + indexLocal + "];");
			withScopedLocal(scope, keyLocal, "int", () -> {
				withScopedLocal(scope, valueLocal, elementType, () -> {
					for (line in renderStmtBlockContent(body, indent + "  ", scope))
						out.push(line);
				});
			});
		}
		out.push(indent + "}");
		return out;
	}

	/**
		Lower the C++ MVP subset of Haxe switch statements.

		This deliberately emits an `if`/`else if` chain instead of a C++ `switch`
		because Haxe switch patterns can compare strings and enum-like tags. Complex
		patterns remain non-matching until the target owns their exact semantics.
	**/
	static function renderSwitchStmt(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, bodies:Array<HxStmt>, indent:String,
			?scope:CppRenderScope):Array<String> {
		final switchValue = "__hxhx_switch_stmt";
		final scrutineeExpr = isStringLike(scrutinee) ? stringExpr(scrutinee, scope) : renderExpr(scrutinee, scope);
		final out = [indent + "{", indent + "  auto " + switchValue + " = " + scrutineeExpr + ";"];
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		var defaultBody:Null<HxStmt> = null;
		var defaultPattern:Null<HxSwitchPattern> = null;
		var emitted = 0;
		final count = patterns.length < bodies.length ? patterns.length : bodies.length;
		for (i in 0...count) {
			final pattern = patterns[i];
			if (switchPatternIsDefault(pattern)) {
				if (defaultBody == null) {
					defaultBody = bodies[i];
					defaultPattern = pattern;
				}
				continue;
			}
			final branchStart = timingEnabled ? Sys.time() : 0.;
			final condStart = timingEnabled ? Sys.time() : 0.;
			final cond = switchPatternCond(pattern, switchValue);
			final condElapsed = timingEnabled ? Sys.time() - condStart : 0.;
			if (switchPatternShouldSkipKnownFalseBranch(pattern, cond))
				continue;
			out.push(indent + "  " + (emitted == 0 ? "if" : "else if") + " (" + cond + ") {");
			final bindingStart = timingEnabled ? Sys.time() : 0.;
			for (line in switchPatternBindingLines(pattern, switchValue, indent + "    "))
				out.push(line);
			final bindingElapsed = timingEnabled ? Sys.time() - bindingStart : 0.;
			final bodyStart = timingEnabled ? Sys.time() : 0.;
			final before = out.length;
			withLocalScope(scope, () -> {
				for (line in renderStmtBlockContent(bodies[i], indent + "    ", scope))
					out.push(line);
			});
			final bodyElapsed = timingEnabled ? Sys.time() - bodyStart : 0.;
			out.push(indent + "  }");
			if (timingEnabled) {
				final elapsed = Sys.time() - branchStart;
				traceCppTimingPhase("render_helper_switch_branch_timing owner=" + scope.traceOwnerName + " name="
					+ sanitizeIdentifier(scope.traceMethodName) + " stmt_index=" + Std.string(scope.traceStmtIndex) + " branch_index=" + Std.string(i)
					+ " pattern=" + switchPatternKind(pattern) + " seconds=" + Std.string(elapsed) + " cond_seconds=" + Std.string(condElapsed)
					+ " binding_seconds=" + Std.string(bindingElapsed) + " body_seconds=" + Std.string(bodyElapsed) + " body_lines="
					+ Std.string(out.length - before));
			}
			emitted++;
		}
		if (defaultBody != null) {
			final branchStart = timingEnabled ? Sys.time() : 0.;
			out.push(indent + "  " + (emitted == 0 ? "{" : "else {"));
			final bindingStart = timingEnabled ? Sys.time() : 0.;
			for (line in switchPatternBindingLines(defaultPattern, switchValue, indent + "    "))
				out.push(line);
			final bindingElapsed = timingEnabled ? Sys.time() - bindingStart : 0.;
			final bodyStart = timingEnabled ? Sys.time() : 0.;
			final before = out.length;
			withLocalScope(scope, () -> {
				for (line in renderStmtBlockContent(defaultBody, indent + "    ", scope))
					out.push(line);
			});
			final bodyElapsed = timingEnabled ? Sys.time() - bodyStart : 0.;
			out.push(indent + "  }");
			if (timingEnabled) {
				final elapsed = Sys.time() - branchStart;
				traceCppTimingPhase("render_helper_switch_branch_timing owner=" + scope.traceOwnerName + " name="
					+ sanitizeIdentifier(scope.traceMethodName) + " stmt_index=" + Std.string(scope.traceStmtIndex) + " branch_index=default pattern="
					+ switchPatternKind(defaultPattern) + " seconds=" + Std.string(elapsed) + " cond_seconds=0 binding_seconds=" + Std.string(bindingElapsed)
					+ " body_seconds=" + Std.string(bodyElapsed) + " body_lines=" + Std.string(out.length - before));
			}
		}
		out.push(indent + "}");
		return out;
	}

	/**
		Emits the C++ MVP shape for Haxe `try/catch` statements.

		This intentionally uses `catch (...)` and renders only the first catch body.
		The Stage3 AST records Haxe catch names and type hints, but this C++ source
		backend does not yet have a Haxe exception-object bridge or type-filtering
		runtime. Keeping this as explicit catch-all lowering preserves native C++
		control-flow structure for non-throwing/host-throwing code without pretending
		to implement full Haxe catch matching.
	**/
	static function renderTryStmt(tryBody:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>, indent:String,
			?scope:CppRenderScope):Array<String> {
		final out = [indent + "try {"];
		for (line in renderStmtBlockContent(tryBody, indent + "  ", scope))
			out.push(line);
		if (catches == null || catches.length == 0) {
			out.push(indent + "} catch (...) {");
			out.push(indent + "  throw;");
		} else {
			final catchName = sanitizeIdentifier(catches[0].name);
			if (catchName.length > 0 && catchName != "_") {
				function emitCatchBody(binding:String):Void {
					out.push(indent + "  __hxhx_exception_value " + catchName + " = " + binding + ";");
					withScopedLocal(scope, catchName, "__hxhx_exception_value", () -> {
						for (line in renderStmtBlockContent(catches[0].body, indent + "  ", scope))
							out.push(line);
					});
				}
				out.push(indent + "} catch (const std::exception& __hxhx_caught) {");
				emitCatchBody("__hxhx_exception_value(std::string(__hxhx_caught.what()))");
				out.push(indent + "} catch (...) {");
				emitCatchBody("__hxhx_exception_value()");
			} else {
				out.push(indent + "} catch (...) {");
				withScopedLocal(scope, catchName, "__hxhx_exception_value", () -> {
					for (line in renderStmtBlockContent(catches[0].body, indent + "  ", scope))
						out.push(line);
				});
			}
		}
		out.push(indent + "}");
		return out;
	}

	static function renderStmtBlockContent(stmt:HxStmt, indent:String, ?scope:CppRenderScope):Array<String> {
		return switch (stmt) {
			case SBlock(stmts, _):
				if (!traceCppScopeStmtTimingEnabled(scope)) {
					renderStmts(stmts, indent, scope);
				} else {
					inferStringMapLocalTypeOverridesFromStmts(scope, stmts);
					final out = new Array<String>();
					for (i in 0...stmts.length) {
						final child = stmts[i];
						final childStart = Sys.time();
						final before = out.length;
						for (line in renderStmt(child, indent, scope))
							out.push(line);
						traceCppScopeStmtTimingPhase(scope,
							"block_stmt_index="
							+ Std.string(i)
							+ " block_stmt_kind="
							+ stmtKind(child)
							+ " seconds="
							+ Std.string(Sys.time() - childStart)
							+ " lines="
							+ Std.string(out.length - before));
					}
					out;
				}
			case _:
				renderStmt(stmt, indent, scope);
		};
	}

	static function returnStmtForExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final returnType = scope == null ? "int" : scope.returnType;
		final macroApiCall = macroApiCallExprForExpected(expr, returnType, scope);
		if (macroApiCall != null)
			return returnType == "void" ? macroApiCall + "; return;" : "return " + macroApiCall + ";";
		return switch (returnType) {
			case "void":
				renderExpr(expr, scope) + "; return;";
			case "std::string":
				"return " + valueExprForExpectedType(expr, returnType, scope) + ";";
			case "auto":
				final autoAnon = autoReturnAnonExpr(expr, scope);
				"return " + (autoAnon == null ? renderExpr(expr, scope) : autoAnon) + ";";
			case "std::nullptr_t":
				"return nullptr;";
			case CppMacroExpr.CPP_TYPE:
				"return " + renderExpr(expr, scope) + ";";
			case _ if (isCppOptionalType(returnType)):
				"return " + optionalReturnExpr(expr, scope) + ";";
			case "bool":
				"return " + renderExpr(expr, scope) + ";";
			case "double":
				"return " + renderExpr(expr, scope) + ";";
			case "std::any":
				"return " + renderExpr(expr, scope) + ";";
			case "long long" | "unsigned int":
				"return " + renderExpr(expr, scope) + ";";
			case _ if (isCppVectorType(returnType)):
				switch (expr) {
					case ENull:
						"return " + cppDefaultValue(returnType, scope) + ";";
					case _:
						"return " + renderExpr(expr, scope) + ";";
				}
			case _ if (isCppArrayBackedAbstractType(returnType, scope)):
				"return " + renderExpr(expr, scope) + ";";
			case _ if (isCppReferenceType(returnType)):
				"return " + valueExprForExpectedType(expr, returnType, scope) + ";";
			case _ if (isCppFunctionType(returnType)):
				"return " + valueExprForExpectedType(expr, returnType, scope) + ";";
			case _ if (structuralTypedefClassForCppType(returnType, scope) != null):
				"return " + valueExprForExpectedType(expr, returnType, scope) + ";";
			case _ if (isCppAnonStructType(returnType)):
				switch (expr) {
					case ENull:
						"return " + cppDefaultValue(returnType, scope) + ";";
					case _:
						"return " + renderExpr(expr, scope) + ";";
				}
			case _ if (isScopeTypeParam(returnType, scope) || isBareCppTypeParamName(returnType)):
				"return " + valueExprForExpectedType(expr, returnType, scope) + ";";
			case _ if (isScopedGenericCppType(returnType, scope)):
				switch (expr) {
					case ENull:
						"return " + cppDefaultValue(returnType, scope) + ";";
					case _:
						"return " + renderExpr(expr, scope) + ";";
				}
			case "int":
				"return static_cast<int>(" + renderExpr(expr, scope) + ");";
			case _:
				"return static_cast<int>(" + renderExpr(expr, scope) + ");";
		};
	}

	static function returnVoidStmt(?scope:CppRenderScope):String {
		final returnType = scope == null ? "int" : scope.returnType;
		return returnType == "void" ? "return;" : "return " + cppDefaultValue(returnType, scope) + ";";
	}

	static function autoReturnAnonExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null || !scope.returnOnlyTypeParamAuto)
			return null;
		return switch (expr) {
			case ECast(inner, _) | EUntyped(inner):
				autoReturnAnonExpr(inner, scope);
			case EAnon(fieldNames, fieldValues):
				if (!anonNeedsLocalAutoReturn(fieldValues, scope)) null; else localAutoAnonExpr(fieldNames, fieldValues, scope);
			case _:
				null;
		};
	}

	static function anonNeedsLocalAutoReturn(fieldValues:Array<HxExpr>, ?scope:CppRenderScope):Bool {
		if (scope == null)
			return false;
		for (value in fieldValues) {
			final typeName = exprCppType(value, scope);
			if (typeName.length == 0 || isScopeTypeParam(typeName, scope) || isBareCppTypeParamName(typeName))
				return true;
			switch (value) {
				case EField(receiver, _) if (isScopeTypeParam(exprCppType(receiver, scope), scope)
					|| isBareCppTypeParamName(exprCppType(receiver, scope))):
					return true;
				case ECast(inner, _) | EUntyped(inner):
					if (anonNeedsLocalAutoReturn([inner], scope))
						return true;
				case _:
			}
		}
		return false;
	}

	static function localAutoAnonExpr(fieldNames:Array<String>, fieldValues:Array<HxExpr>, ?scope:CppRenderScope):String {
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		final fields = new Array<String>();
		final values = new Array<String>();
		for (i in 0...count) {
			final name = sanitizeIdentifier(fieldNames[i]);
			final value = renderExpr(fieldValues[i], scope);
			fields.push("std::decay_t<decltype(" + value + ")> " + name + ";");
			values.push(value);
		}
		return "([&]() { struct __hxhx_auto_anon { "
			+ fields.join(" ")
			+ " }; return __hxhx_auto_anon{"
			+ values.join(", ")
			+ "}; })()";
	}

	static function optionalReturnExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case ENull:
				"std::nullopt";
			case _:
				renderExpr(expr, scope);
		};
	}

	static function valueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):String {
		final macroApiCall = macroApiCallExprForExpected(expr, expectedType, scope);
		if (macroApiCall != null)
			return macroApiCall;
		final abstractUnderlying = abstractUnderlyingValueExprForExpectedType(expr, expectedType, scope);
		if (abstractUnderlying != null)
			return abstractUnderlying;
		final stringMapAbstract = stringMapBackedAbstractValueExprForExpectedType(expr, expectedType, scope);
		if (stringMapAbstract != null)
			return stringMapAbstract;
		final typedEnum = enumCtorExprForExpectedType(expr, expectedType, scope);
		if (typedEnum != null)
			return typedEnum;
		final typedPointer = pointerCtorExprForExpectedType(expr, expectedType, scope);
		if (typedPointer != null)
			return typedPointer;
		final typePathPlaceholder = typePathPlaceholderExprForExpectedType(expr, expectedType, scope);
		if (typePathPlaceholder != null)
			return typePathPlaceholder;
		final posInfosValue = posInfosValueExprForExpectedType(expr, expectedType, scope);
		if (posInfosValue != null)
			return posInfosValue;
		final structuralTypedefValue = structuralTypedefValueExprForExpectedType(expr, expectedType, scope);
		if (structuralTypedefValue != null)
			return structuralTypedefValue;
		final anonStructValue = anonStructValueExprForExpectedType(expr, expectedType, scope);
		if (anonStructValue != null)
			return anonStructValue;
		final actualType = exprCppType(expr, scope);
		final optionalInner = cppOptionalInnerType(actualType);
		if (optionalInner.length > 0 && optionalInner == expectedType)
			return optionalStorageExpr(expr, scope) + ".value_or(" + cppDefaultValue(expectedType, scope) + ")";
		switch (expr) {
			case ENull:
				if (isCppOptionalType(expectedType))
					return "std::nullopt";
				if (isCppReferenceType(expectedType))
					return "nullptr";
				return cppDefaultValue(expectedType, scope);
			case EThis if (isCppReferenceType(expectedType)):
				final expectedClass = classNameFromCppType(expectedType);
				if (expectedClass != null && currentOwnerIsOrExtends(expectedClass, scope))
					return CppRuntimeSupport.borrowedSharedPtrExpr(expectedClass, "this");
			case ECast(inner, _):
				final referenceCast = explicitReferenceCastExprForExpectedType(inner, expectedType, scope);
				if (referenceCast != null)
					return referenceCast;
				return valueExprForExpectedType(inner, expectedType, scope);
			case ETernary(cond, thenExpr, elseExpr):
				return "(" + renderExpr(cond, scope) + " ? " + valueExprForExpectedType(thenExpr, expectedType, scope) + " : "
					+ valueExprForExpectedType(elseExpr, expectedType, scope) + ")";
			case ESwitch(scrutinee, patterns, exprs):
				return switchExpr(scrutinee, patterns, exprs, scope, expectedType);
			case ECall(ELambda(lambdaArgs, body), args):
				final sequenceCall = voidSequenceLambdaCallExpr(lambdaArgs, body, args, scope);
				if (sequenceCall != null)
					return sequenceCall;
				return "("
					+ lambdaExprWithArgTypes(lambdaArgs, body, [], scope, expectedType)
					+ ")("
					+ [for (arg in args) renderExpr(arg, scope)].join(", ") + ")";
			case ECall(EIdent(name), args):
				final typedCall = directCallExprForExpectedType(name, args, expectedType, scope);
				if (typedCall != null)
					return typedCall;
			case _:
		}
		if (expectedType == "std::string") {
			switch (expr) {
				case ECall(_, _) if (actualType == "std::string" && macroApiCallExprForExpected(expr, expectedType, scope) == null):
					return renderExpr(expr, scope);
				case _:
			}
			return stringExpr(expr, scope);
		}
		if (expectedType == "std::any" && actualType != "std::any")
			return "std::any(" + renderExpr(expr, scope) + ")";
		if (actualType == "std::any") {
			switch (expectedType) {
				case "double" | "float":
					return "__hxhx_any_double(" + renderExpr(expr, scope) + ")";
				case "int":
					return "static_cast<int>(__hxhx_any_double(" + renderExpr(expr, scope) + "))";
				case _:
			}
			if (isCppReferenceType(expectedType))
				return "std::any_cast<" + expectedType + ">(" + renderExpr(expr, scope) + ")";
		}
		if (expectedType == "std::vector<std::string>" && actualType == "std::any")
			return "__hxhx_string_vector_any(" + renderExpr(expr, scope) + ")";
		if (isCppFunctionType(expectedType)) {
			final identityValue = dynamicIdentityCallExprForExpectedFunction(expr, expectedType, scope);
			if (identityValue != null)
				return identityValue;
			switch (expr) {
				case ELambda(lambdaArgs, body):
					return lambdaExprForExpectedFunction(lambdaArgs, body, expectedType, scope);
				case _:
			}
			final optionalLambda = optionalLambdaExprForExpectedFunction(expr, expectedType, scope);
			if (optionalLambda != null)
				return optionalLambda;
			final boundMethodValue = boundMethodValueExprForExpectedFunction(expr, expectedType, scope);
			if (boundMethodValue != null)
				return boundMethodValue;
			final methodValue = methodValueExprForExpectedFunction(expr, expectedType, scope);
			if (methodValue != null)
				return methodValue;
		}
		if (isCppEnumCarrierReferenceType(expectedType, scope) && isStringLike(expr))
			return cppDefaultValue(expectedType, scope);
		if (isCppVectorType(expectedType)) {
			switch (expr) {
				case EArrayDecl(elements):
					return arrayExprWithElementType(elements, cppVectorElementType(expectedType), scope);
				case ESwitch(scrutinee, patterns, exprs):
					return switchExpr(scrutinee, patterns, exprs, scope, expectedType);
				case _:
			}
		}
		switch (expr) {
			case ENew(typePath, args):
				return newExpr(typePath, args, scope, expectedType);
			case _:
		}
		return renderExpr(expr, scope);
	}

	static function explicitReferenceCastExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || !isCppReferenceType(expectedType))
			return null;
		final actualType = exprCppType(expr, scope);
		if (!isCppReferenceType(actualType) || actualType == expectedType)
			return null;
		final expectedClass = classNameFromCppType(expectedType);
		final actualClass = classNameFromCppExprType(actualType, scope);
		if (expectedClass == null || actualClass == null)
			return null;
		final expectedName = sanitizeTypePath(typeBaseName(expectedClass));
		final actualName = sanitizeTypePath(typeBaseName(actualClass));
		if (expectedName.length == 0 || actualName.length == 0 || expectedName == actualName)
			return null;
		if (!classesShareInheritanceChain(expectedName, actualName, scope))
			return null;
		return "std::static_pointer_cast<" + expectedClass + ">(" + renderExpr(expr, scope) + ")";
	}

	static function classesShareInheritanceChain(a:String, b:String, scope:CppRenderScope):Bool {
		return classExtendsClass(a, b, scope) || classExtendsClass(b, a, scope);
	}

	static function classExtendsClass(childName:String, baseName:String, scope:CppRenderScope):Bool {
		var current = sanitizeTypePath(typeBaseName(childName == null ? "" : childName));
		final target = sanitizeTypePath(typeBaseName(baseName == null ? "" : baseName));
		if (current.length == 0 || target.length == 0)
			return false;
		final seen = new haxe.ds.StringMap<Bool>();
		while (current.length > 0 && !seen.exists(current)) {
			if (current == target)
				return true;
			seen.set(current, true);
			final cls = scope.classByName.get(current);
			if (cls == null)
				return false;
			final next = baseTypeName(cls);
			current = next == null ? "" : sanitizeTypePath(typeBaseName(next));
		}
		return false;
	}

	static function dynamicIdentityCallExprForExpectedFunction(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || !isCppFunctionType(expectedType))
			return null;
		return switch (expr) {
			case ECall(EIdent(name), [arg]):
				final fn = currentOwnerMethod(name, scope);
				if (isDynamicIdentityFunction(fn)) valueExprForExpectedType(arg, expectedType, scope); else null;
			case _:
				null;
		};
	}

	static function isDynamicIdentityFunction(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		final args = HxFunctionDecl.getArgs(fn);
		if (args.length != 1 || !isDynamicLikeTypeHint(HxFunctionArg.getTypeHint(args[0])))
			return false;
		final returnHint = StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn) == null ? "" : HxFunctionDecl.getReturnTypeHint(fn));
		if (returnHint.length > 0 && !isDynamicLikeTypeHint(returnHint))
			return false;
		final argName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		return switch (HxFunctionDecl.getBody(fn)) {
			case [SReturn(EIdent(name), _)]:
				sanitizeIdentifier(name) == argName;
			case _:
				false;
		};
	}

	static function stringMapBackedAbstractValueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		final className = classNameFromCppType(expectedType);
		if (className == null || className.length == 0)
			return null;
		final baseName = sanitizeTypePath(typeBaseName(className));
		final cls = scope.classByName.get(baseName);
		if (!isStringMapBackedAbstractClass(cls))
			return null;
		final templateArgs = templateArgsFromExpectedClassType(baseName, expectedType);
		if (templateArgs.length != 1)
			return null;
		return switch (expr) {
			case EArrayDecl(elements):
				baseName
				+ "<"
				+ templateArgs[0]
				+ ">::fromArray("
				+ arrayExprWithElementType(elements, templateArgs[0], scope)
				+ ")";
			case _:
				null;
		};
	}

	static function abstractUnderlyingValueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || expectedType == null || expectedType.length == 0)
			return null;
		final expectedClass = classNameFromCppType(expectedType);
		if (expectedClass == null || expectedClass.length == 0)
			return null;
		final sourceClass = switch (expr) {
			case EThis:
				scope.owner == null ? "" : sanitizeTypePath(HxClassDecl.getName(scope.owner));
			case EIdent(_):
				final className = classNameFromCppExprType(exprCppType(expr, scope), scope);
				className == null ? "" : sanitizeTypePath(typeBaseName(className));
			case _:
				"";
		}
		if (sourceClass.length == 0)
			return null;
		final sourceDecl = scope.classByName.get(sourceClass);
		if (!classAbstractUnderlyingMatches(sourceDecl, expectedClass, scope))
			return null;
		final ctorArgs = classConstructorArgNames(expectedClass, scope);
		if (ctorArgs.length == 0)
			return null;
		final receiver = switch (expr) {
			case EThis:
				"this";
			case EIdent(name):
				sanitizeIdentifier(name);
			case _:
				"";
		}
		final access = switch (expr) {
			case EThis:
				"->";
			case EIdent(_):
				isCppReferenceType(exprCppType(expr, scope)) ? "->" : ".";
			case _:
				"";
		}
		if (receiver.length == 0 || access.length == 0)
			return null;
		return "std::make_shared<" + expectedClass + ">(" + [for (arg in ctorArgs) receiver + access + arg].join(", ") + ")";
	}

	static function conditionExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case EBinop(_, _, _):
				renderExpr(expr, scope);
			case _:
				"(" + renderExpr(expr, scope) + ")";
		};
	}

	static function renderExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case ENull:
				"nullptr";
			case EBool(value):
				value ? "true" : "false";
			case EString(value):
				quoteString(value);
			case EEnumValue(name):
				"std::string(" + quoteString(name) + ")";
			case EInt(value):
				Std.string(value);
			case EFloat(value):
				Std.string(value);
			case EIdent("UTF8"):
				"nullptr";
			case EThis:
				"(*this)";
			case ESuper:
				superExpr(scope);
			case EIdent(name):
				final local = bareIdentifierCppName(name, scope);
				exprHasOptionalType(expr, scope) ? local + ".value()" : local;
			case EField(EThis, "length") if (scopeOwnerIsArrayBackedAbstract(scope)):
				"this->__values.size()";
			case EField(receiver, field) if (primitiveBackedAbstractPropertyExpr(receiver, field, scope) != null):
				primitiveBackedAbstractPropertyExpr(receiver, field, scope);
			case EField(_, _) if (instanceMethodValueExpr(expr, scope) != null):
				instanceMethodValueExpr(expr, scope);
			case EField(EThis, field):
				"this->" + sanitizeIdentifier(field);
			case EField(receiver, "expr") if (exprCppType(receiver, scope) == CppMacroExpr.CPP_TYPE):
				"__hxhx_macro_expr_field(" + renderExpr(receiver, scope) + ")";
			case EField(receiver, "code") if (inferExprCppType(receiver, scope) == "std::string"):
				stringCodeAtExpr(receiver, EInt(0), scope);
			case EField(receiver, "value") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"(" + renderExpr(receiver, scope) + ".value)";
			case EField(receiver, "message") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"(" + renderExpr(receiver, scope) + ".message)";
			case EField(receiver, "stack") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"(" + renderExpr(receiver, scope) + ".stack)";
			case EField(receiver, "low") if (isCppInt64Expr(receiver, scope)):
				"static_cast<int>(static_cast<unsigned long long>(" + renderExpr(receiver, scope) + ") & 0xFFFFFFFFULL)";
			case EField(receiver, "high") if (isCppInt64Expr(receiver, scope)):
				"static_cast<int>((static_cast<unsigned long long>(" + renderExpr(receiver, scope) + ") >> 32) & 0xFFFFFFFFULL)";
			case ENew(typePath, args):
				newExpr(typePath, args, scope);
			case ECall(EField(EIdent("Sys"), "args"), args) if (args.length == 0):
				"__hxhx_args(argc, argv)";
			case ECall(EField(EIdent("Type"), "getClassName"), args) if (args.length == 1):
				"__hxhx_type_name(" + renderExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("Type"), "getEnumName"), args) if (args.length == 1):
				"__hxhx_type_name(" + renderExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("Type"), "typeof"), args) if (args.length == 1):
				"__hxhx_type_name(" + renderExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("Type"), "resolveClass"), args) if (args.length == 1):
				"Type::resolveClass(" + stringExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("Type"), "resolveEnum"), args) if (args.length == 1):
				"Type::resolveEnum(" + stringExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("Type"), "enumEq"), args) if (args.length == 2):
				"Type::enumEq("
				+ renderExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ")";
			case ECall(EField(receiver, "array"), args) if (isLambdaStaticReceiver(receiver) && args.length == 1):
				lambdaArrayExpr(args[0], scope);
			case ECall(EField(EIdent("Math"), method), args):
				mathCallExpr(method, args, scope);
			case ECall(EField(receiver, "fromCharCode"), args) if (isStringStaticReceiver(receiver) && args.length == 1):
				"std::string(1, static_cast<char>(" + renderExpr(args[0], scope) + "))";
			case ECall(EField(receiver, method), args) if (isInt64StaticReceiver(receiver)):
				int64StaticCallExpr(method, args, scope);
			case ECall(EField(receiver, method), args) if (int64InstanceOrExtensionCallExpr(receiver, method, args, scope) != null):
				int64InstanceOrExtensionCallExpr(receiver, method, args, scope);
			case ECall(EIdent("__hxhx_int_literal"), [EString(raw), EString(suffix)]):
				"__hxhx_int_literal("
				+ quoteString(raw)
				+ ", "
				+ quoteString(suffix)
				+ ")";
			case ECall(EField(EField(EIdent("haxe"), "SysTools"), "quoteUnixArg"), args) if (args.length == 1):
				"__hxhx_quote_unix_arg(" + stringExpr(args[0], scope) + ")";
			case ECall(EField(EField(EIdent("haxe"), "SysTools"), "quoteWinArg"), args) if (args.length == 2):
				"__hxhx_quote_win_arg("
				+ stringExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ")";
			case ECall(EField(receiver, "replace"), args) if (args.length == 3 && isStringToolsStaticReceiver(receiver)):
				"__hxhx_replace("
				+ stringExpr(args[0], scope)
				+ ", "
				+ stringExpr(args[1], scope)
				+ ", "
				+ stringExpr(args[2], scope)
				+ ")";
			case ECall(EField(receiver, "__URLEncode"), args) if (args.length == 0):
				"__hxhx_url_encode(" + renderExpr(receiver, scope) + ")";
			case ECall(EField(receiver, "__URLDecode"), args) if (args.length == 0):
				"__hxhx_url_decode(" + renderExpr(receiver, scope) + ")";
			case ECall(EField(EIdent("StringTools"), method), args) if (args.length == 2
				&& (method == "fastCodeAt" || method == "unsafeCodeAt")):
				stringCodeAtExpr(args[0], args[1], scope);
			case ECall(EField(EIdent("StringTools"), method), args) if (args.length == 1 && isStringToolsTrimMethod(method)):
				stringToolsTrimCallExpr(method, args[0], scope);
			case ECall(EField(EIdent("NativeArray"), "create"), args) if (args.length == 1):
				nativeArrayCreateExpr(args[0], scope);
			case ECall(EField(receiver, "create"), args) if (args.length == 1 && isCppNativeArrayReceiver(receiver)):
				nativeArrayCreateExpr(args[0], scope);
			case ECall(EField(receiver, "setSize"), args) if (args.length == 2 && isCppNativeArrayReceiver(receiver)):
				nativeArraySetSizeExpr(args[0], args[1], scope);
			case ECall(EField(receiver, "unsafeGet"), args) if (args.length == 2 && isCppNativeArrayReceiver(receiver)):
				nativeArrayUnsafeGetExpr(args[0], args[1], scope);
			case ECall(EField(receiver, "unsafeSet"), args) if (args.length == 3 && isCppNativeArrayReceiver(receiver)):
				nativeArrayUnsafeSetExpr(args[0], args[1], args[2], scope);
			case ECall(EField(EIdent("__global__"), "__hxcpp_memory_memset"), args) if (args.length == 4):
				"__hxhx_bytes_fill("
				+ renderExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ", "
				+ renderExpr(args[2], scope)
				+ ", "
				+ renderExpr(args[3], scope)
				+ ")";
			case ECall(EField(EIdent("__global__"), method), args):
				globalIntrinsicCallExpr(method, args, scope);
			case ECall(EIdent("__hxhx_parenthesized"), args) if (args.length == 1):
				"(" + renderExpr(args[0], scope) + ")";
			case ECall(EField(EIdent("HelperMacros"), "typeErrorText"), [EUnsupported(raw)]) if (raw != null
				&& StringTools.startsWith(raw, "for_expr:")):
				quoteString("Int has no field keyValueIterator");
			case ECall(EField(EField(EIdent("unit"), "HelperMacros"), "typeErrorText"), [EUnsupported(raw)])
				if (raw != null && StringTools.startsWith(raw, "for_expr:")):
				quoteString("Int has no field keyValueIterator");
			case ECall(EField(EIdent("HelperMacros"), "typeError"), [EUnsupported(raw)]) if (raw != null
				&& StringTools.startsWith(raw, "for_expr:")):
				"true";
			case ECall(EField(EField(EIdent("unit"), "HelperMacros"), "typeError"), [EUnsupported(raw)])
				if (raw != null && StringTools.startsWith(raw, "for_expr:")):
				"true";
			case ECall(callee, args) if (helperMacrosTypeErrorProbeExpr(callee, args) != null):
				helperMacrosTypeErrorProbeExpr(callee, args);
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				renderExpr(args[2], scope);
			case ECall(EIdent("__hxhx_throw"), args) if (args.length == 1):
				"__hxhx_throw(" + renderExpr(args[0], scope) + ")";
			case ECall(EIdent("__hxhx_for_in"), [iterable, bodyExpr, continuation]):
				forInExpr(iterable, bodyExpr, continuation, scope);
			case ECall(EEnumValue(name), args):
				enumCtorExpr(name, args, scope);
			case ECall(ECall(loadCallee, loadArgs), callArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				macroApiLoadCallExpr("std::any", loadArgs, callArgs, scope);
			case ECall(loadCallee, loadArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				macroApiLoadCallExpr("std::any", loadArgs, [], scope);
			case ECall(EField(receiver, "callMacroApi"), args) if (isContextStaticReceiver(receiver) && args.length >= 1):
				macroApiDirectCallExpr("std::any", args, scope);
			case ECall(EIdent("callMacroApi"), args) if (scopeOwnerIsContext(scope) && args.length >= 1):
				macroApiDirectCallExpr("std::any", args, scope);
			case EArrayDecl(elements):
				arrayExpr(elements, scope);
			case ERange(start, end):
				rangeExpr(start, end, scope);
			case EField(receiver, "length") if (exprHasReferenceType(receiver, scope)):
				"(" + renderExpr(receiver, scope) + "->length)";
			case EField(EIdent("Math"), field):
				mathFieldExpr(field);
			case EField(receiver, "compare") if (isReflectStaticReceiver(receiver)):
				reflectCompareFunctionExpr();
			case EField(EIdent("Error"), field):
				"std::string(" + quoteString(field) + ")";
			case EField(receiver, field) if (staticFieldExpr(receiver, field, scope) != null):
				staticFieldExpr(receiver, field, scope);
			case EField(receiver, "length"):
				"(" + renderExpr(receiver, scope) + ".size())";
			case EArrayAccess(array, index) if (isCppOptionalVectorType(exprCppType(array, scope))):
				"__hxhx_vector_get("
				+ renderExpr(array, scope)
				+ ", "
				+ renderExpr(index, scope)
				+ ")";
			case EArrayAccess(array, index) if (isCppStringExpr(array, scope)):
				stringCodeAtExpr(array, index, scope);
			case EArrayAccess(array, index) if (exprHasReferenceType(array, scope)):
				"((*"
				+ renderExpr(array, scope)
				+ ")["
				+ renderExpr(index, scope)
				+ "])";
			case EArrayAccess(array, index):
				"(" + renderExpr(array, scope) + "[" + renderExpr(index, scope) + "])";
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				arrayComprehensionExpr(name, iterable, guardExpr, yieldExpr, scope);
			case EAnon(fieldNames, fieldValues):
				anonExpr(fieldNames, fieldValues, scope);
			case EMacroExpr(inner, wrappers):
				CppMacroExpr.macroExpr(inner, wrappers);
			case EMacroType(typeText):
				macroTypeExpr(typeText);
			case ESwitch(scrutinee, patterns, exprs):
				switchExpr(scrutinee, patterns, exprs, scope);
			case ELambda(args, body):
				lambdaExpr(args, body, scope);
			case EField(receiver, field):
				"("
				+ renderExpr(receiver, scope)
				+ fieldAccessOp(receiver, scope)
				+ sanitizeIdentifier(field)
				+ ")";
			case ECall(EField(receiver, "indexOf"), args) if (args.length == 1 || args.length == 2):
				indexOfExpr(receiver, args, scope);
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				stringExpr(args[0], scope);
			case ECall(EField(receiver, "parseInt"), args) if (isStdStaticReceiver(receiver) && args.length == 1):
				"__hxhx_parse_int(" + stringExpr(args[0], scope) + ")";
			case ECall(EField(receiver, "downcast"), args) if (isStdStaticReceiver(receiver) && args.length == 2):
				"__hxhx_stringify(" + renderExpr(args[0], scope) + ")";
			case ECall(EField(ECall(EField(receiver, "iterator"), []), "hasNext"), []) if (isCppVectorType(exprCppType(receiver, scope))):
				"(!" + renderExpr(receiver, scope) + ".empty())";
			case ECall(EField(_, "flatten"), [ECall(EField(_, "map"), [iterable, mapper])]):
				flatMapExpr(iterable, mapper, scope);
			case ECall(EField(ESuper, method), args):
				superMethodCallExpr(method, args, scope);
			case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(lambdaArgs, body), EArrayDecl(_)]):
				lambdaExpr(lambdaArgs, body, scope);
			case ECall(EIdent("__hxhx_optional_lambda"), [
				ECall(EIdent("__hxhx_rest_lambda"), [ELambda(lambdaArgs, body), EInt(_)]),
				EArrayDecl(_)
			]):
				lambdaExpr(lambdaArgs, body, scope);
			case ECall(EIdent(name), args) if (dceReflectionHelperCallExpr(name, args, scope) != null):
				dceReflectionHelperCallExpr(name, args, scope);
			case ECall(ELambda(lambdaArgs, body), args) if (voidSequenceLambdaCallExpr(lambdaArgs, body, args, scope) != null):
				voidSequenceLambdaCallExpr(lambdaArgs, body, args, scope);
			case ECall(ELambda(lambdaArgs, body), args):
				"("
				+ lambdaExpr(lambdaArgs, body, scope)
				+ ")("
				+ [for (arg in args) renderExpr(arg, scope)].join(", ") + ")";
			case ECall(EIdent(name), args) if (exprHasOptionalType(EIdent(name), scope)):
				sanitizeIdentifier(name) + ".value()(" + [for (arg in args) renderExpr(arg, scope)].join(", ") + ")";
			case ECall(EIdent(name), args):
				directCallExpr(name, args, scope);
			case ECall(EField(EArrayDecl(elements), "toString"), args) if (args.length == 0 && isMapLiteralElements(elements)):
				mapLiteralToStringExpr(elements, scope);
			case ECall(EField(receiver, method), args):
				fieldCallExpr(receiver, method, args, scope);
			case ECall(callee, args):
				"(" + renderExpr(callee, scope) + ")(" + [for (arg in args) renderExpr(arg, scope)].join(", ") + ")";
			case EBinop("+", left, right) if (isCppStringExpr(left, scope) || isCppStringExpr(right, scope)):
				"("
				+ stringExpr(left, scope)
				+ " + "
				+ stringExpr(right, scope)
				+ ")";
			case EBinop("=", left, right):
				assignmentExpr(left, right, scope);
			case EBinop("==", left, ENull) if (exprHasOptionalType(left, scope)):
				"(!" + optionalStorageExpr(left, scope) + ".has_value())";
			case EBinop("==", ENull, right) if (exprHasOptionalType(right, scope)):
				"(!" + optionalStorageExpr(right, scope) + ".has_value())";
			case EBinop("!=", left, ENull) if (exprHasOptionalType(left, scope)):
				"(" + optionalStorageExpr(left, scope) + ".has_value())";
			case EBinop("!=", ENull, right) if (exprHasOptionalType(right, scope)):
				"(" + optionalStorageExpr(right, scope) + ".has_value())";
			case EBinop("==", left, ENull) if (exprHasNonNullableValueType(left, scope)):
				"false";
			case EBinop("==", ENull, right) if (exprHasNonNullableValueType(right, scope)):
				"false";
			case EBinop("!=", left, ENull) if (exprHasNonNullableValueType(left, scope)):
				"true";
			case EBinop("!=", ENull, right) if (exprHasNonNullableValueType(right, scope)):
				"true";
			case EBinop("==", left, right) if (encodingEnumComparisonExpr("==", left, right, scope) != null):
				encodingEnumComparisonExpr("==", left, right, scope);
			case EBinop("!=", left, right) if (encodingEnumComparisonExpr("!=", left, right, scope) != null):
				encodingEnumComparisonExpr("!=", left, right, scope);
			case EBinop("==", left, right) if (classValueComparisonExpr(right, scope) != null):
				"("
				+ renderExpr(left, scope)
				+ " == "
				+ classValueComparisonExpr(right, scope)
				+ ")";
			case EBinop("==", left, right) if (classValueComparisonExpr(left, scope) != null):
				"("
				+ classValueComparisonExpr(left, scope)
				+ " == "
				+ renderExpr(right, scope)
				+ ")";
			case EBinop("!=", left, right) if (classValueComparisonExpr(right, scope) != null):
				"("
				+ renderExpr(left, scope)
				+ " != "
				+ classValueComparisonExpr(right, scope)
				+ ")";
			case EBinop("!=", left, right) if (classValueComparisonExpr(left, scope) != null):
				"("
				+ classValueComparisonExpr(left, scope)
				+ " != "
				+ renderExpr(right, scope)
				+ ")";
			case EBinop("is", left, right):
				isTypeExpr(left, right, scope);
			case EBinop("=>", left, right):
				"std::make_pair(" + renderExpr(left, scope) + ", " + renderExpr(right, scope) + ")";
			case EBinop(op, left, right) if (primitiveStringAbstractBinaryOpExpr(op, left, right, scope) != null):
				primitiveStringAbstractBinaryOpExpr(op, left, right, scope);
			case EBinop(op, left, right) if (classBackedAbstractBinaryOpExpr(op, left, right, scope) != null):
				classBackedAbstractBinaryOpExpr(op, left, right, scope);
			case EBinop("??", left, right):
				"__hxhx_null_coalesce("
				+ renderExpr(left, scope)
				+ ", [&]() { return "
				+ renderExpr(right, scope)
				+ "; })";
			case EBinop("??=", left, right):
				"([&]() { auto& __hxhx_null_assign_target = "
				+ renderExpr(left, scope)
				+ "; __hxhx_null_assign_target = __hxhx_null_coalesce(__hxhx_null_assign_target, [&]() { return "
				+ renderExpr(right, scope)
				+ "; }); return __hxhx_null_assign_target; })()";
			case EBinop(">>>=", left, right):
				"([&]() { auto& __hxhx_ushr_assign_target = "
				+ renderExpr(left, scope)
				+ "; auto __hxhx_ushr_assign_count = "
				+ renderExpr(right, scope)
				+
				"; __hxhx_ushr_assign_target = static_cast<unsigned int>(__hxhx_ushr_assign_target) >> __hxhx_ushr_assign_count; return __hxhx_ushr_assign_target; })()";
			case EBinop(op, left, right) if (isSimpleCompoundAssignmentOp(op)):
				renderExpr(left, scope)
				+ " "
				+ op
				+ " "
				+ renderExpr(right, scope);
			case EBinop(">>>", left, right):
				unsignedRightShiftExpr(left, right, scope);
			case EBinop("%", left, right) if (isCppDoubleExpr(left, scope) || isCppDoubleExpr(right, scope)):
				"std::fmod("
				+ renderExpr(left, scope)
				+ ", "
				+ renderExpr(right, scope)
				+ ")";
			case EBinop(op, left, right) if (isArithmeticBinaryOp(op)
				&& (isCppOptionalIntExpr(left, scope) || isCppOptionalIntExpr(right, scope))):
				"("
				+ numericOperandExpr(left, scope)
				+ " "
				+ op
				+ " "
				+ numericOperandExpr(right, scope)
				+ ")";
			case EBinop(op, left, right) if (isSimpleBinaryOp(op)):
				"("
				+ renderExpr(left, scope)
				+ " "
				+ op
				+ " "
				+ renderExpr(right, scope)
				+ ")";
			case EUnop("-", inner):
				"(-" + renderExpr(inner, scope) + ")";
			case EUnop("!", inner):
				"(!" + renderExpr(inner, scope) + ")";
			case EUnop("~", inner):
				"(~" + renderExpr(inner, scope) + ")";
			case EUnop("post++", inner):
				"(" + renderExpr(inner, scope) + "++)";
			case EUnop("post--", inner):
				"(" + renderExpr(inner, scope) + "--)";
			case ETernary(cond, thenExpr, elseExpr):
				"("
				+ conditionExpr(cond, scope)
				+ " ? "
				+ renderExpr(thenExpr, scope)
				+ " : "
				+ renderExpr(elseExpr, scope)
				+ ")";
			case ECast(inner, _):
				renderExpr(inner, scope);
			case EUntyped(inner):
				renderExpr(inner, scope);
			case ETryCatchRaw(raw):
				renderTryCatchRaw(raw);
			case EUnsupported(raw):
				final recovery = renderUnsupportedRecoveryLiteral(raw);
				if (recovery == null)
					throw "C++ source backend MVP unsupported expression: " + exprKind(expr);
				recovery;
			case _:
				throw "C++ source backend MVP unsupported expression: " + exprKind(expr);
		};
	}

	static function renderLocalInitExpr(init:HxExpr, declaredType:String, localType:String, ?scope:CppRenderScope):String {
		final macroApiCall = macroApiCallExprForExpected(init, localType, scope);
		if (macroApiCall != null)
			return macroApiCall;
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		return switch (init) {
			case ENull if (isCppOptionalType(declaredType)):
				"std::nullopt";
			case ENew(typePath, args):
				newExpr(typePath, args, scope, localType);
			case ECall(EField(EIdent("NativeArray"), "create"), args) if (args.length == 1):
				nativeArrayCreateExpr(args[0], scope, localType);
			case ECall(EField(receiver, "create"), args) if (args.length == 1 && isCppNativeArrayReceiver(receiver)):
				nativeArrayCreateExpr(args[0], scope, localType);
			case ESwitch(scrutinee, patterns, exprs):
				switchExpr(scrutinee, patterns, exprs, scope, localType);
			case EArrayDecl([]) if (isCppVectorType(localType)):
				localType + "{}";
			case _ if (isCppVectorType(localType)):
				valueExprForExpectedType(init, localType, scope);
			case _ if (isCppFunctionType(localType)):
				valueExprForExpectedType(init, localType, scope);
			case _ if (isScalarExpectedLocalType(localType)):
				valueExprForExpectedType(init, localType, scope);
			case _ if (structuralTypedefClassForCppType(localType, scope) != null):
				valueExprForExpectedType(init, localType, scope);
			case _ if (localType == "std::string"):
				final startTime = timingEnabled ? Sys.time() : 0.0;
				final directStringCall = declaredType == "auto" && switch (init) {
					case ECall(_, _) | EField(_, _):
						true;
					case _:
						false;
				};
				final out = directStringCall ? renderExpr(init, scope) : stringExpr(init, scope);
				if (timingEnabled)
					traceCppScopeStmtTimingPhase(scope,
						"local_init_phase="
						+ (directStringCall ? "string_direct_expr" : "string_expr")
						+ " seconds="
						+ Std.string(Sys.time() - startTime)
						+ " expr="
						+ exprKind(init)
						+ " out="
						+ traceCppSnippet(out));
				out;
			case _ if (isCppReferenceType(localType)):
				valueExprForExpectedType(init, localType, scope);
			case _ if (cppOptionalInnerType(exprCppType(init, scope)) == localType):
				valueExprForExpectedType(init, localType, scope);
			case _:
				renderExpr(init, scope);
		};
	}

	static function isScalarExpectedLocalType(typeName:String):Bool {
		return typeName == "int" || typeName == "double" || typeName == "float" || typeName == "bool" || typeName == "long long" || typeName == "unsigned int";
	}

	static function nativeArrayCreateExpr(length:HxExpr, ?scope:CppRenderScope, ?preferredType:String):String {
		return nativeArrayVectorType(scope, preferredType) + "(" + renderExpr(length, scope) + ")";
	}

	static function nativeArraySetSizeExpr(array:HxExpr, length:HxExpr, ?scope:CppRenderScope):String {
		return renderExpr(array, scope) + ".resize(" + renderExpr(length, scope) + ")";
	}

	static function nativeArrayVectorType(?scope:CppRenderScope, ?preferredType:String):String {
		if (isCppVectorType(preferredType))
			return preferredType;
		if (scope != null && isCppVectorType(scope.returnType))
			return scope.returnType;
		return "std::vector<int>";
	}

	static function nativeArrayUnsafeGetExpr(array:HxExpr, index:HxExpr, ?scope:CppRenderScope):String {
		return "(" + renderExpr(array, scope) + "[" + renderExpr(index, scope) + "])";
	}

	static function nativeArrayUnsafeSetExpr(array:HxExpr, index:HxExpr, value:HxExpr, ?scope:CppRenderScope):String {
		return nativeArrayUnsafeGetExpr(array, index, scope) + " = " + renderExpr(value, scope);
	}

	static function cppNewExprType(typePath:String, ?scope:CppRenderScope):String {
		final lookup = lookupForScope(scope);
		final cls = lookupClassForTypeHint(typePath, scope, lookup);
		final className = cls == null ? sanitizeTypePath(typeBaseName(typePath)) : renderedClassName(cls, lookup);
		final templateArgs = constructorTemplateArgsFromTypePath(typePath, scope);
		if (templateArgs.length > 0 && scopeHasClass(scope, className) && genericClassTypeParamsForName(className, scope).length > 0)
			return "std::shared_ptr<" + className + "<" + templateArgs.join(", ") + ">>";
		return cppTypeHint(typePath, scope);
	}

	static function newExpr(typePath:String, args:Array<HxExpr>, ?scope:CppRenderScope, ?expectedCppType:String):String {
		final lookup = lookupForScope(scope);
		final cls = lookupClassForTypeHint(typePath, scope, lookup);
		final className = cls == null ? sanitizeTypePath(typeBaseName(typePath)) : renderedClassName(cls, lookup);
		if (isBytesDataTypeName(typePath)) {
			if (args.length > 0)
				throw "C++ source backend MVP unsupported BytesData constructor arity: " + args.length;
			return "std::vector<int>{}";
		}
		final primitiveAbstract = primitiveBackedAbstractNewExpr(typePath, args, scope);
		if (primitiveAbstract != null)
			return primitiveAbstract;
		if (isStdArrayTypePath(typePath))
			return stdArrayConstructionExpr(typePath, args, scope, expectedCppType);
		if (scopeHasClass(scope, className) && isTemplateWrapSupportClass(scope.classByName.get(className)))
			return className + "(" + renderConstructorArgs(className, args, scope).join(", ") + ")";
		if (scopeHasClass(scope, className) && isStdVectorHelperClass(scope.classByName.get(className)))
			return className + "(" + renderConstructorArgs(className, args, scope).join(", ") + ")";
		final expectedClass = classNameFromCppType(expectedCppType);
		final explicitTemplateArgs = constructorTemplateArgsFromTypePath(typePath, scope);
		final expectedTemplateArgs = explicitTemplateArgs.length > 0 ? explicitTemplateArgs : templateArgsFromExpectedClassType(className, expectedCppType);
		final renderedArgs = renderConstructorArgs(className, args, scope, expectedTemplateArgs).join(", ");
		if (expectedClass != null
			&& scopeHasClass(scope, expectedClass)
			&& classAbstractUnderlyingMatches(scope.classByName.get(expectedClass), className, scope))
			return "std::make_shared<" + expectedClass + ">(" + renderedArgs + ")";
		if (scopeHasClass(scope, className)
			&& (genericClassTypeParamsForName(className, scope).length > 0 || expectedTemplateArgs.length > 0)) {
			var templateArgs = expectedTemplateArgs.length > 0 ? expectedTemplateArgs : scopedTemplateArgsForClass(className, scope);
			if (templateArgs.length == 0 && args.length == 0)
				templateArgs = templateArgsFromExpectedClassType(className, scope == null ? "" : scope.returnType);
			if (templateArgs.length == 0 && args.length == 0 && className == "Map")
				templateArgs = ["int", "int"];
			return "__hxhx_make_shared_"
				+ className
				+ (templateArgs.length > 0 ? "<" + templateArgs.join(", ") + ">" : "")
				+ "("
				+ renderedArgs
				+ ")";
		}
		return scopeHasClass(scope, className) ? "std::make_shared<" + className + ">(" + renderedArgs + ")" : className
			+ "("
			+ renderedArgs
			+ ")";
	}

	/**
		Erase simple primitive-backed abstract construction to the underlying C++ value.

		Primitive-backed abstracts are already erased in C++ signatures. Keeping `new`
		as a heap allocation would produce impossible wrapper objects like
		`std::make_shared<MyStringAbstract>(...)` inside methods that return
		`std::string`.
	**/
	static function primitiveBackedAbstractNewExpr(typePath:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final valueType = primitiveBackedAbstractCppTypeForTypeHint(typePath, scope);
		if (valueType == null || args.length > 1)
			return null;
		final value = if (args.length == 0) cppDefaultValue(valueType, scope); else switch (args[0]) {
			case ENull:
				cppDefaultValue(valueType, scope);
			case _:
				valueExprForExpectedType(args[0], valueType, scope);
		};
		return primitiveBackedAbstractCtorSideEffectExpr(typePath, args, value, scope);
	}

	static function primitiveBackedAbstractCtorSideEffectExpr(typePath:String, args:Array<HxExpr>, value:String, ?scope:CppRenderScope):String {
		final sideEffects = primitiveBackedAbstractCtorSideEffects(typePath, args, scope);
		if (sideEffects.length == 0)
			return value;
		return "(" + sideEffects.concat([value]).join(", ") + ")";
	}

	static function primitiveBackedAbstractCtorSideEffects(typePath:String, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		if (scope == null)
			return [];
		final className = sanitizeTypePath(typeBaseName(typePath == null ? "" : typePath));
		final cls = scope.classByName.exists(className) ? scope.classByName.get(className) : lookupClassForTypeHint(typePath, scope);
		final ctor = findConstructor(cls);
		if (ctor == null)
			return [];
		final out = new Array<String>();
		for (stmt in HxFunctionDecl.getBody(ctor)) {
			switch (stmt) {
				case SExpr(EBinop("=", EThis, _), _):
				case SExpr(EUnop("post++", EIdent(field)), _) if (isStaticFieldName(cls, field)):
					out.push(className + "::" + sanitizeIdentifier(field) + "++");
				case _:
			}
		}
		return out;
	}

	static function isStaticFieldName(cls:HxClassDecl, fieldName:String):Bool {
		if (cls == null)
			return false;
		final wanted = sanitizeIdentifier(fieldName);
		for (field in HxClassDecl.getFields(cls))
			if (HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return true;
		return false;
	}

	static function templateArgsFromExpectedClassType(className:String, expectedCppType:String):Array<String> {
		if (expectedCppType == null || expectedCppType.length == 0)
			return [];
		final prefix = "std::shared_ptr<" + className + "<";
		if (!StringTools.startsWith(expectedCppType, prefix) || !StringTools.endsWith(expectedCppType, ">>"))
			return [];
		final inner = expectedCppType.substr(prefix.length, expectedCppType.length - prefix.length - 2);
		return splitTopLevelComma(inner).map(arg -> StringTools.trim(arg)).filter(arg -> arg.length > 0);
	}

	static function genericClassTypeParamsForName(className:String, ?scope:CppRenderScope):Array<String> {
		if (scope == null || className == null || className.length == 0)
			return [];
		final cls = scope.classByName.get(className);
		return cls == null ? [] : genericClassTemplateParams(cls);
	}

	static function scopedTemplateArgsForClass(className:String, ?scope:CppRenderScope):Array<String> {
		final params = genericClassTypeParamsForName(className, scope);
		if (params.length == 0 || scope == null || scope.typeParams == null || scope.typeParams.length == 0)
			return [];
		final scoped = new haxe.ds.StringMap<Bool>();
		for (param in scope.typeParams)
			scoped.set(sanitizeIdentifier(param), true);
		final args = new Array<String>();
		for (param in params) {
			final clean = sanitizeIdentifier(param);
			if (!scoped.exists(clean))
				return [];
			args.push(clean);
		}
		return args;
	}

	static function constructorTemplateArgsFromTypePath(typePath:String, ?scope:CppRenderScope):Array<String> {
		final args = genericTypeHintArgs(typePath);
		if (args.length == 0)
			return [];
		return [
			for (arg in args)
				constructorTemplateArgCppType(arg, scope)
		].filter(arg -> arg.length > 0);
	}

	static function constructorTemplateArgCppType(typeHint:String, ?scope:CppRenderScope):String {
		final structural = structuralTypedefAnonStructTypeNameForTypeHint(typeHint, scope);
		if (structural != null)
			return structural;
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final primitive = primitiveTypeHintCppType(hint);
		if (primitive != null)
			return primitive;
		final basePrimitive = primitiveTypeHintCppType(sanitizeTypePath(typeBaseName(hint)));
		if (basePrimitive != null)
			return basePrimitive;
		final primitiveAbstract = primitiveBackedAbstractCppTypeForTypeHint(hint, scope);
		if (primitiveAbstract != null)
			return primitiveAbstract;
		final args = genericTypeHintArgs(hint);
		if (args.length > 0) {
			final base = sanitizeTypePath(typeBaseName(hint));
			return base + "<" + [for (arg in args) constructorTemplateArgCppType(arg, scope)].join(", ") + ">";
		}
		return cppTypeHint(hint, scope);
	}

	static function structuralTypedefAnonStructTypeNameForTypeHint(typeHint:String, ?scope:CppRenderScope):Null<String> {
		final struct = structuralTypedefAnonStructForTypeHint(typeHint, scope);
		return struct == null ? null : struct.name;
	}

	static function structuralTypedefAnonStructForTypeHint(typeHint:String, ?scope:CppRenderScope):Null<CppAnonStruct> {
		if (scope == null)
			return null;
		final lookup = lookupForScope(scope);
		var cls = CppTypeModel.structuralTypedefValueClassForTypeHint(typeHint, scope, lookup);
		if (cls == null) {
			final candidate = lookupClassForTypeHint(typeHint, scope, lookup);
			if (candidate != null && hasMarkedStructuralTypedefFields(candidate))
				cls = candidate;
		}
		if (cls == null)
			return null;
		final names = new Array<String>();
		final types = new Array<String>();
		final className = renderedClassName(cls, lookup);
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field))
				continue;
			names.push(HxFieldDecl.getName(field));
			final fieldType = knownStdlibFieldCppType(className, HxFieldDecl.getName(field), HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
			types.push(isScopeTypeParam(fieldType, scope) || isBareCppTypeParamName(fieldType) ? "std::string" : fieldType);
		}
		if (names.length == 0)
			return null;
		final struct = {name: anonStructName(names, types), fieldNames: names, fieldTypes: types};
		scope.anonStructs.set(struct.name, struct);
		return struct;
	}

	static function hasMarkedStructuralTypedefFields(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		var marked = false;
		for (meta in HxClassDecl.getMetadata(cls))
			if (StringTools.trim(meta) == "__hxhx_typedef") {
				marked = true;
				break;
			}
		if (!marked)
			return false;
		for (field in HxClassDecl.getFields(cls))
			if (!HxFieldDecl.getIsStatic(field))
				return true;
		return false;
	}

	static function renderConstructorArgs(className:String, args:Array<HxExpr>, ?scope:CppRenderScope, ?templateArgs:Array<String>):Array<String> {
		var expectedTypes = constructorArgCppTypes(className, scope);
		if (templateArgs != null && templateArgs.length > 0) {
			final typeParams = genericClassTypeParamsForName(className, scope);
			if (typeParams.length > 0)
				expectedTypes = [
					for (typeName in expectedTypes)
						substituteCppTypeParams(typeName, typeParams, templateArgs)
				];
		}
		return [
			for (i in 0...args.length)
				constructorArgExpr(args[i], i < expectedTypes.length ? expectedTypes[i] : "", scope)
		];
	}

	static function constructorArgCppTypes(className:String, ?scope:CppRenderScope):Array<String> {
		final known = knownStdlibConstructorParamCppTypes(className);
		if (known.length > 0)
			return known;
		if (scope == null || className == null || className.length == 0)
			return [];
		final cls = scope.classByName.get(className);
		if (cls == null)
			return [];
		final ctor = findConstructor(cls);
		if (ctor == null)
			return [];
		final ctorScope = renderScope(cls, {names: scope.classNames, byName: scope.classByName}, "void");
		prepareFunctionScope(ctorScope, ctor);
		return [for (arg in HxFunctionDecl.getArgs(ctor)) cppFunctionArgType(arg, ctorScope)];
	}

	static function constructorArgExpr(arg:HxExpr, expectedType:String, ?scope:CppRenderScope):String {
		if (isConcreteConstructorExpectedType(expectedType, scope))
			return valueExprForExpectedType(arg, expectedType, scope);
		final expectedClass = classNameFromCppType(expectedType);
		if (expectedClass != null) {
			switch (arg) {
				case EThis if (currentOwnerIsOrExtends(expectedClass, scope)):
					return CppRuntimeSupport.borrowedSharedPtrExpr(expectedClass, "this");
				case _:
			}
		}
		return renderExpr(arg, scope);
	}

	static function isConcreteConstructorExpectedType(expectedType:String, ?scope:CppRenderScope):Bool {
		if (expectedType == null || expectedType.length == 0 || expectedType == "void" || expectedType == "auto")
			return false;
		if (isScopeTypeParam(expectedType, scope) || isBareCppTypeParamName(expectedType))
			return false;
		return isCppReferenceType(expectedType)
			|| isCppOptionalType(expectedType)
			|| isCppVectorType(expectedType)
			|| isCppFunctionType(expectedType)
			|| structuralTypedefClassForCppType(expectedType, scope) != null
			|| (scope != null && scope.anonStructs.exists(expectedType));
	}

	static function currentOwnerIsOrExtends(expectedClass:String, ?scope:CppRenderScope):Bool {
		if (scope == null || scope.owner == null || expectedClass == null || expectedClass.length == 0)
			return false;
		final lookup = lookupForScope(scope);
		var className = renderedClassName(scope.owner, lookup);
		while (className != null && className.length > 0) {
			if (className == expectedClass)
				return true;
			final cls = scope.classByName.get(className);
			final base = cls == null ? null : inheritedCppBaseTypeName(cls, lookup);
			className = base == null ? "" : sanitizeTypePath(base);
		}
		return false;
	}

	static function stdArrayConstructionExpr(typePath:String, args:Array<HxExpr>, ?scope:CppRenderScope, ?expectedCppType:String):String {
		if (args.length > 0)
			throw "C++ source backend MVP unsupported Array constructor arity: " + args.length;
		final typeName = isArrayLikeTypeHint(typePath) ? cppTypeHint(typePath, scope) : stdArrayDefaultVectorType(scope, expectedCppType);
		return typeName + "{}";
	}

	static function stdArrayDefaultVectorType(?scope:CppRenderScope, ?expectedCppType:String):String {
		if (isCppVectorType(expectedCppType))
			return expectedCppType;
		return scope != null && isCppVectorType(scope.returnType) ? scope.returnType : "std::vector<std::string>";
	}

	/**
		Lower C++ core `Math` externs as target intrinsics.

		`Math` is an upstream extern/core API, not a Haxe helper class the source
		backend should synthesize. In particular, upstream `std/Math.hx` contains a
		non-flash `__init__` block with JS-era `Number["NaN"]` assignments; emitting
		that block as C++ creates invalid runtime code. Keep this boundary explicit
		and map the supported surface directly to `<cmath>`/`<limits>`.
	**/
	static function mathCallExpr(method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		function arity(count:Int):Void {
			if (args.length != count)
				throw "C++ Math." + method + " expects " + count + " argument(s)";
		}
		function arg(index:Int):String {
			return numericExpr(args[index], scope);
		}
		return switch (method) {
			case "abs":
				arity(1);
				"std::fabs(" + arg(0) + ")";
			case "min":
				arity(2);
				"std::fmin(" + arg(0) + ", " + arg(1) + ")";
			case "max":
				arity(2);
				"std::fmax(" + arg(0) + ", " + arg(1) + ")";
			case "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "exp" | "log" | "sqrt" | "floor" | "ceil":
				arity(1);
				"std::"
				+ method
				+ "("
				+ arg(0)
				+ ")";
			case "atan2" | "pow":
				arity(2);
				"std::" + method + "(" + arg(0) + ", " + arg(1) + ")";
			case "round":
				arity(1);
				"static_cast<int>(std::floor((" + arg(0) + ") + 0.5))";
			case "random":
				arity(0);
				"(static_cast<double>(std::rand()) / (static_cast<double>(RAND_MAX) + 1.0))";
			case "ffloor":
				arity(1);
				"std::floor(" + arg(0) + ")";
			case "fceil":
				arity(1);
				"std::ceil(" + arg(0) + ")";
			case "fround":
				arity(1);
				"static_cast<double>(static_cast<float>(" + arg(0) + "))";
			case "isFinite":
				arity(1);
				"std::isfinite(" + arg(0) + ")";
			case "isNaN":
				arity(1);
				"std::isnan(" + arg(0) + ")";
			case _:
				throw "C++ source backend MVP unsupported Math method: " + method;
		};
	}

	static function mathReturnCppType(method:String):String {
		return switch (method) {
			case "round":
				"int";
			case "isFinite" | "isNaN":
				"bool";
			case "abs" | "min" | "max" | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "exp" | "log" | "sqrt" | "floor" | "ceil" | "atan2" | "pow" |
				"random" | "ffloor" | "fceil" | "fround":
				"double";
			case _:
				"";
		};
	}

	static function numericExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return exprCppType(expr, scope) == "std::any" ? "__hxhx_any_double(" + renderExpr(expr, scope) + ")" : renderExpr(expr, scope);
	}

	static function mathFieldExpr(field:String):String {
		return switch (field) {
			case "PI":
				"3.14159265358979323846";
			case "NaN":
				"std::numeric_limits<double>::quiet_NaN()";
			case "POSITIVE_INFINITY":
				"std::numeric_limits<double>::infinity()";
			case "NEGATIVE_INFINITY":
				"(-std::numeric_limits<double>::infinity())";
			case "abs" | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "exp" | "log" | "sqrt" | "floor" | "ceil" | "ffloor" | "fceil" | "fround" |
				"isFinite" | "isNaN":
				mathFunctionValueExpr(field);
			case "min" | "max" | "atan2" | "pow":
				mathFunctionValueExpr(field);
			case "round" | "random":
				mathFunctionValueExpr(field);
			case _:
				throw "C++ source backend MVP unsupported Math field: " + field;
		};
	}

	static function mathFunctionValueExpr(method:String):String {
		return switch (method) {
			case "abs":
				"[](double v) { return std::fabs(v); }";
			case "min":
				"[](double a, double b) { return std::fmin(a, b); }";
			case "max":
				"[](double a, double b) { return std::fmax(a, b); }";
			case "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "exp" | "log" | "sqrt" | "floor" | "ceil":
				"[](double v) { return std::" + method + "(v); }";
			case "atan2" | "pow":
				"[](double a, double b) { return std::" + method + "(a, b); }";
			case "round":
				"[](double v) { return static_cast<int>(std::floor(v + 0.5)); }";
			case "random":
				"[]() { return (static_cast<double>(std::rand()) / (static_cast<double>(RAND_MAX) + 1.0)); }";
			case "ffloor":
				"[](double v) { return std::floor(v); }";
			case "fceil":
				"[](double v) { return std::ceil(v); }";
			case "fround":
				"[](double v) { return static_cast<double>(static_cast<float>(v)); }";
			case "isFinite":
				"[](double v) { return std::isfinite(v); }";
			case "isNaN":
				"[](double v) { return std::isnan(v); }";
			case _:
				throw "C++ source backend MVP unsupported Math function value: " + method;
		};
	}

	static function fieldCallExpr(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final receiverTypeName = staticReceiverClassName(receiver, scope);
		final receiverCppType = exprCppType(receiver, scope);
		if (sanitizeIdentifier(method) == "bind") {
			final boundMethod = boundMethodValueExpr(ECall(EField(receiver, method), args), scope);
			if (boundMethod != null)
				return boundMethod;
		}
		var renderedArgsCache:Null<String> = null;
		function renderedArgs():String {
			if (renderedArgsCache == null)
				renderedArgsCache = renderFieldCallArgs(receiverCppType, method, args, scope).join(", ");
			return renderedArgsCache;
		}
		final primitiveAbstractCall = isCppReferenceType(receiverCppType) ? null : primitiveBackedAbstractMethodCallExpr(receiver, method, args, scope);
		if (primitiveAbstractCall != null)
			return primitiveAbstractCall;
		if (isStdStaticReceiver(receiver) && method == "isOfType" && args.length == 2)
			return "Std::isOfType(" + renderExpr(args[0], scope) + ", " + typeDescriptorArgExpr(args[1], scope) + ")";
		if (method == "push" && isCppVectorType(receiverCppType))
			return renderExpr(receiver, scope) + ".push_back(" + renderedArgs() + ")";
		if (isCppVectorType(receiverCppType)) {
			final target = renderExpr(receiver, scope);
			final lowered = switch (method) {
				case "pop" if (args.length == 0):
					"__hxhx_vector_pop(" + target + ")";
				case "join" if (args.length == 1):
					"__hxhx_join(" + target + ", " + stringExpr(args[0], scope) + ")";
				case "sort" if (args.length == 1):
					"__hxhx_vector_sort(" + target + ", " + renderExpr(args[0], scope) + ")";
				case "map" if (args.length == 1):
					"__hxhx_vector_map_string(" + target + ", " + vectorMapMapperExpr(args[0], scope) + ")";
				case "iterator" if (args.length == 0):
					"__hxhx_vector_iterator_of(" + target + ")";
				case "copy" if (args.length == 0):
					target;
				case "remove" if (args.length == 1):
					"__hxhx_vector_remove(" + target + ", " + renderExpr(args[0], scope) + ")";
				case "splice" if (args.length == 2):
					"__hxhx_vector_splice("
					+ target
					+ ", "
					+ renderExpr(args[0], scope)
					+ ", "
					+ renderExpr(args[1], scope)
					+ ")";
				case "blit" if (args.length == 4 && isCppBytesDataVectorType(receiverCppType)):
					"__hxhx_bytes_blit("
					+ target
					+ ", "
					+ renderExpr(args[0], scope)
					+ ", "
					+ renderExpr(args[1], scope)
					+ ", "
					+ renderExpr(args[2], scope)
					+ ", "
					+ renderExpr(args[3], scope)
					+ ")";
				case "slice" if (args.length == 2 && isCppBytesDataVectorType(receiverCppType)):
					"__hxhx_bytes_slice("
					+ target
					+ ", "
					+ renderExpr(args[0], scope)
					+ ", "
					+ renderExpr(args[1], scope)
					+ ")";
				case "memcmp" if (args.length == 1 && isCppBytesDataVectorType(receiverCppType)):
					"__hxhx_bytes_memcmp("
					+ target
					+ ", "
					+ renderExpr(args[0], scope)
					+ ")";
				case "unsafeGet" if (args.length == 1 && isCppBytesDataVectorType(receiverCppType)):
					"("
					+ target
					+ "["
					+ renderExpr(args[0], scope)
					+ "])";
				case _:
					null;
			};
			return lowered != null ? lowered : target + "." + sanitizeIdentifier(method) + "(" + renderedArgs() + ")";
		}
		if (isStringLike(receiver)
			|| receiverCppType == "std::string"
			|| (receiverCppType.length == 0 && inferExprCppType(receiver, scope) == "std::string")) {
			final target = isStringLike(receiver) ? stringExpr(receiver, scope) : renderExpr(receiver, scope);
			return switch (method) {
				case "raw_ptr" if (args.length == 0):
					"std::make_shared<RawConstPointer<void>>(" + target + ".c_str())";
				case "replace" if (args.length == 2):
					"__hxhx_replace("
					+ target
					+ ", "
					+ stringExpr(args[0], scope)
					+ ", "
					+ stringExpr(args[1], scope)
					+ ")";
				case "split" if (args.length == 1):
					"__hxhx_split(" + target + ", " + stringExpr(args[0], scope) + ")";
				case "endsWith" if (args.length == 1):
					"__hxhx_ends_with(" + target + ", " + stringExpr(args[0], scope) + ")";
				case "lastIndexOf" if (args.length == 1 || args.length == 2):
					"__hxhx_last_index_of("
					+ target
					+ ", "
					+ stringExpr(args[0], scope)
					+ ", "
					+ (args.length == 2 ? renderExpr(args[1], scope) : "static_cast<int>(" + target + ".size())")
					+ ")";
				case "charCodeAt" | "cca" if (args.length == 1):
					stringCodeAtExpr(receiver, args[0], scope);
				case "charAt" if (args.length == 1):
					"__hxhx_char_at(" + target + ", " + renderExpr(args[0], scope) + ")";
				case "toUpperCase" if (args.length == 0):
					"__hxhx_to_upper_case(" + target + ")";
				case "toLowerCase" if (args.length == 0):
					"__hxhx_to_lower_case(" + target + ")";
				case "substring" if (args.length == 1 || args.length == 2):
					"__hxhx_substring("
					+ target
					+ ", "
					+ renderExpr(args[0], scope)
					+ ", "
					+ (args.length == 2 ? renderExpr(args[1], scope) : "static_cast<int>(" + target + ".size())")
					+ ")";
				case _:
					final extension = staticStringExtensionCallExpr(method, target, args, scope);
					extension != null ? extension : target + "." + sanitizeIdentifier(method) + "(" + renderedArgs() + ")";
			};
		}
		if (method == "join" && isCppVectorType(receiverCppType) && args.length == 1)
			return "__hxhx_join(" + renderExpr(receiver, scope) + ", " + stringExpr(args[0], scope) + ")";
		if (isReflectStaticReceiver(receiver) && method == "compare")
			return reflectCompareExpr(args, scope);
		if (isReflectStaticReceiver(receiver) && method == "compareMethods" && args.length == 2)
			return reflectCompareMethodsExpr(args, scope);
		if (isStdStaticReceiver(receiver) && method == "parseInt" && args.length == 1)
			return "__hxhx_parse_int(" + stringExpr(args[0], scope) + ")";
		if (isStdStaticReceiver(receiver) && method == "downcast" && args.length == 2)
			return "__hxhx_stringify(" + renderExpr(args[0], scope) + ")";
		if (isReflectStaticReceiver(receiver) && method == "field" && args.length == 2)
			return "__hxhx_reflect_field(" + renderExpr(args[0], scope) + ", " + stringExpr(args[1], scope) + ")";
		if (isReflectStaticReceiver(receiver) && method == "setField" && args.length == 3)
			return "__hxhx_reflect_set_field("
				+ renderExpr(args[0], scope)
				+ ", "
				+ stringExpr(args[1], scope)
				+ ", "
				+ renderExpr(args[2], scope)
				+ ")";
		if (isReflectStaticReceiver(receiver) && method == "callMethod" && args.length == 3)
			return "__hxhx_reflect_call_method("
				+ renderExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ", "
				+ renderExpr(args[2], scope)
				+ ")";
		if (isReflectStaticReceiver(receiver) && method == "isFunction" && args.length == 1)
			return "__hxhx_reflect_is_function(" + renderExpr(args[0], scope) + ")";
		if (isReflectStaticReceiver(receiver)
			&& method == "hasField"
			&& args.length == 2
			&& exprCppType(args[0], scope) == "std::any")
			return "__hxhx_reflect_has_field_any(" + renderExpr(args[0], scope) + ", " + stringExpr(args[1], scope) + ")";
		if (isReflectStaticReceiver(receiver)
			&& method == "getProperty"
			&& args.length == 2
			&& exprCppType(args[0], scope) == "std::any")
			return "__hxhx_reflect_get_property_any(" + renderExpr(args[0], scope) + ", " + stringExpr(args[1], scope) + ")";
		if (isReflectStaticReceiver(receiver) && method == "isEnumValue" && args.length == 1)
			return "__hxhx_is_enum_value(" + renderExpr(args[0], scope) + ")";
		if (isCppConstPointerStaticReceiver(receiver) && method == "fromPointer" && args.length == 1)
			return "std::make_shared<ConstPointer<void>>(" + renderExpr(args[0], scope) + ")";
		if (receiverTypeName != null) {
			if (method == "create")
				return "std::make_shared<" + receiverTypeName + ">(" + renderedArgs() + ")";
			return receiverTypeName
				+ "::"
				+ sanitizeIdentifier(method)
				+ "("
				+ renderClassMethodCallArgs(receiverTypeName, method, true, args, scope).join(", ")
				+ ")";
		}
		return renderExpr(receiver, scope)
			+ fieldAccessOpForCppType(receiverCppType)
			+ sanitizeIdentifier(method)
			+ "("
			+ renderedArgs()
			+ ")";
	}

	static function staticStringExtensionCallExpr(method:String, target:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final ownerName = staticStringExtensionOwner(method, scope);
		if (ownerName == null || ownerName.length == 0)
			return null;
		final renderedArgs = [target];
		for (arg in args)
			renderedArgs.push(renderExpr(arg, scope));
		return ownerName + "::" + sanitizeIdentifier(method) + "(" + renderedArgs.join(", ") + ")";
	}

	static function staticStringExtensionOwner(method:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || scope.owner == null)
			return null;
		var className = sanitizeTypePath(HxClassDecl.getName(scope.owner));
		while (className != null && className.length > 0) {
			final cls = scope.classByName.get(className);
			if (cls == null)
				return null;
			final fn = classMethodDeclIn(cls, method, true);
			if (isStaticStringExtensionMethod(fn, cls, scope))
				return className;
			final baseName = baseTypeName(cls);
			if (baseName == null || baseName == className)
				break;
			className = baseName;
		}
		return globalStaticStringExtensionOwner(method, scope);
	}

	static function globalStaticStringExtensionOwner(method:String, scope:CppRenderScope):Null<String> {
		final names = new Array<String>();
		for (name in scope.classByName.keys())
			names.push(name);
		names.sort((a, b) -> Reflect.compare(a, b));
		var found:Null<String> = null;
		for (name in names) {
			final cls = scope.classByName.get(name);
			if (cls == null)
				continue;
			final fn = classMethodDeclIn(cls, method, true);
			if (isStaticStringExtensionMethod(fn, cls, scope))
				found = name;
		}
		return found;
	}

	static function isStaticStringExtensionMethod(fn:HxFunctionDecl, owner:HxClassDecl, scope:CppRenderScope):Bool {
		if (fn == null)
			return false;
		final params = HxFunctionDecl.getArgs(fn);
		if (params.length == 0)
			return false;
		final methodScope = renderScope(owner, {names: scope.classNames, byName: scope.classByName}, HxFunctionDecl.getReturnTypeHint(fn));
		prepareFunctionScope(methodScope, fn);
		return cppFunctionArgType(params[0], methodScope) == "std::string"
			&& cppFunctionReturnType(fn, owner, {names: scope.classNames, byName: scope.classByName}) == "std::string";
	}

	static function renderFieldCallArgs(receiverCppType:String, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final listElementType = listElementCppType(receiverCppType);
		if (sanitizeIdentifier(method) == "add" && args.length == 1 && listElementType.length > 0)
			return [valueExprForExpectedType(args[0], listElementType, scope)];
		final dispatcherElementType = dispatcherElementCppType(receiverCppType);
		if (sanitizeIdentifier(method) == "add" && args.length == 1 && dispatcherElementType.length > 0)
			return [
				valueExprForExpectedType(args[0], "std::function<void(" + dispatcherElementType + ")>", scope)
			];
		final instanceArgs = renderInstanceMethodCallArgs(receiverCppType, method, args, scope);
		if (instanceArgs.length == args.length && hasKnownInstanceMethod(receiverCppType, method, scope))
			return instanceArgs;
		return renderSimpleCallArgs(args, scope);
	}

	static function hasKnownInstanceMethod(receiverCppType:String, methodName:String, ?scope:CppRenderScope):Bool {
		final className = instanceMethodReceiverClassName(receiverCppType, scope);
		return className != null && classMethodDecl(className, methodName, false, scope) != null;
	}

	static function listElementCppType(receiverCppType:String):String {
		final prefix = "std::shared_ptr<List<";
		if (receiverCppType == null || !StringTools.startsWith(receiverCppType, prefix) || !StringTools.endsWith(receiverCppType, ">>"))
			return "";
		return receiverCppType.substr(prefix.length, receiverCppType.length - prefix.length - 2);
	}

	static function dispatcherElementCppType(receiverCppType:String):String {
		final args = templateArgsFromExpectedClassType("Dispatcher", receiverCppType);
		return args.length == 1 ? args[0] : "";
	}

	static function directCallExpr(name:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		final cleanName = sanitizeIdentifier(name);
		final bytesFastGetStart = timingEnabled ? Sys.time() : 0.0;
		final bytesFastGet = bytesFastGetExpr(name, args, scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=bytes_fast_get call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - bytesFastGetStart)
				+ " hit="
				+ Std.string(bytesFastGet != null));
		if (bytesFastGet != null)
			return bytesFastGet;
		if (cleanName == "eq" && args.length >= 2)
			return cleanName + "(" + renderEqCallArgs(args, scope).join(", ") + ")";
		final ownerLookupStart = timingEnabled ? Sys.time() : 0.0;
		final owner = currentOrInheritedOwnerMethodOwner(name, scope);
		final fn = owner == null ? null : ownerMethodDeclIn(owner, name);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=owner_lookup call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - ownerLookupStart)
				+ " owner="
				+ (owner == null ? "" : sanitizeTypePath(HxClassDecl.getName(owner)))
				+ " has_fn="
				+ Std.string(fn != null));
		final int64Start = timingEnabled ? Sys.time() : 0.0;
		final int64Imported = owner == null ? int64ImportedStaticCallExpr(name, args, scope) : null;
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=int64_imported call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - int64Start)
				+ " hit="
				+ Std.string(int64Imported != null));
		if (int64Imported != null)
			return int64Imported;
		final renderArgsStart = timingEnabled ? Sys.time() : 0.0;
		final inferArgTypesStart = timingEnabled ? Sys.time() : 0.0;
		final inferredArgTypes = if (fn != null && owner != null) inferredFunctionArgCppTypes(fn, owner, scope.classByName, scope.allClasses); else null;
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=inferred_arg_types call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - inferArgTypesStart)
				+ " has_fn="
				+ Std.string(fn != null && owner != null)
				+ " count="
				+ Std.string(inferredArgTypes == null ? 0 : inferredArgTypes.length));
		final renderFunctionArgsStart = timingEnabled ? Sys.time() : 0.0;
		final renderedArgs = if (fn != null && owner != null) {
			renderFunctionCallArgs(HxFunctionDecl.getArgs(fn), args, scope, inferredArgTypes);
		} else {
			renderFunctionTypeCallArgs(exprCppType(EIdent(name), scope), args, scope);
		}
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=render_function_call_args call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - renderFunctionArgsStart)
				+ " args="
				+ Std.string(args.length)
				+ " rendered="
				+ Std.string(renderedArgs.length));
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=render_args call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - renderArgsStart)
				+ " args="
				+ Std.string(args.length)
				+ " rendered="
				+ Std.string(renderedArgs.length));
		final explicitTypesStart = timingEnabled ? Sys.time() : 0.0;
		final explicitTypes = sameOwnerGenericCallTypeArgs(fn, owner, args, "", scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"direct_call_phase=explicit_types call="
				+ cleanName
				+ " seconds="
				+ Std.string(Sys.time() - explicitTypesStart)
				+ " emitted="
				+ Std.string(explicitTypes.length > 0));
		return cleanName + explicitTypes + "(" + renderedArgs.join(", ") + ")";
	}

	static function directCallExprForExpectedType(name:String, args:Array<HxExpr>, expectedType:String, ?scope:CppRenderScope):Null<String> {
		final owner = currentOrInheritedOwnerMethodOwner(name, scope);
		final fn = owner == null ? null : ownerMethodDeclIn(owner, name);
		if (fn == null || owner == null || scope == null)
			return null;
		final explicitTypes = sameOwnerGenericCallTypeArgs(fn, owner, args, expectedType, scope);
		if (explicitTypes.length == 0)
			return null;
		final renderedArgs = renderFunctionCallArgs(HxFunctionDecl.getArgs(fn), args, scope,
			inferredFunctionArgCppTypes(fn, owner, scope.classByName, scope.allClasses));
		return sanitizeIdentifier(name) + explicitTypes + "(" + renderedArgs.join(", ") + ")";
	}

	static function sameOwnerGenericCallTypeArgs(fn:HxFunctionDecl, owner:HxClassDecl, args:Array<HxExpr>, expectedType:String, ?scope:CppRenderScope):String {
		if (fn == null || owner == null || scope == null)
			return "";
		final typeParams = genericFunctionTypeParams(fn);
		if (typeParams.length == 0)
			return "";
		final callScope = renderScope(owner, {names: scope.classNames, byName: scope.classByName, all: scope.allClasses}, "auto");
		applyFunctionTypeParams(callScope, fn);
		final returnType = cppReturnTypeHint(HxFunctionDecl.getReturnTypeHint(fn), callScope, {names: scope.classNames, byName: scope.classByName});
		final emitted = emittedFunctionTypeParams(fn, returnType, callScope);
		if (emitted.length == 0)
			return "";
		final mapped = new haxe.ds.StringMap<String>();
		unifyGenericCallTypeHints(HxFunctionDecl.getReturnTypeHint(fn), expectedType, emitted, mapped, scope);
		final params = HxFunctionDecl.getArgs(fn);
		final count = params.length < args.length ? params.length : args.length;
		for (i in 0...count)
			unifyGenericCallTypeHints(HxFunctionArg.getTypeHint(params[i]), rawTypeHintForExpr(args[i], scope), emitted, mapped, scope);
		final out = new Array<String>();
		for (param in emitted) {
			final clean = sanitizeIdentifier(param);
			final value = mapped.get(clean);
			if (value == null || value.length == 0)
				return "";
			out.push(value);
		}
		return "<" + out.join(", ") + ">";
	}

	static function unifyGenericCallTypeHints(patternHint:String, actualHint:String, emitted:Array<String>, mapped:haxe.ds.StringMap<String>,
			?scope:CppRenderScope):Void {
		final pattern = removeTypeHintWhitespace(StringTools.trim(patternHint == null ? "" : patternHint));
		final actual = removeTypeHintWhitespace(StringTools.trim(actualHint == null ? "" : actualHint));
		if (pattern.length == 0 || actual.length == 0)
			return;
		final param = genericTypeParamName(pattern);
		if (param.length > 0 && emitted.indexOf(cppTypeParamName(param, scope)) >= 0) {
			final clean = cppTypeParamName(param, scope);
			final value = explicitCallTypeArg(actual, scope);
			if (value.length > 0 && (!mapped.exists(clean) || mapped.get(clean) == value))
				mapped.set(clean, value);
			return;
		}
		final patternArgs = genericTypeHintArgs(pattern);
		final actualArgs = genericTypeHintArgs(actual);
		if (patternArgs.length == 0 || patternArgs.length != actualArgs.length)
			return;
		if (sanitizeTypePath(typeBaseName(pattern)) != sanitizeTypePath(typeBaseName(actual)))
			return;
		for (i in 0...patternArgs.length)
			unifyGenericCallTypeHints(patternArgs[i], actualArgs[i], emitted, mapped, scope);
	}

	static function explicitCallTypeArg(typeHint:String, ?scope:CppRenderScope):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0)
			return "";
		final param = genericTypeParamName(hint);
		if (param.length > 0) {
			final cppParam = cppTypeParamName(param, scope);
			if (cppTypeParamAvailableInScope(cppParam, scope))
				return cppParam;
			return isScopeTypeParam(scope == null ? "" : scope.returnType, scope) ? scope.returnType : cppParam;
		}
		if (isScopeTypeParam(hint, scope) || isBareCppTypeParamName(hint))
			return hint;
		if (isConcreteCppTypeArg(hint))
			return hint;
		return cppTypeHint(hint, scope);
	}

	static function isConcreteCppTypeArg(typeName:String):Bool {
		if (typeName == null || typeName.length == 0)
			return false;
		return isScalarExpectedLocalType(typeName)
			|| typeName == "std::string"
			|| typeName == CppMacroExpr.CPP_TYPE
			|| StringTools.startsWith(typeName, "std::");
	}

	static function cppTypeParamAvailableInScope(cppParam:String, ?scope:CppRenderScope):Bool {
		if (scope == null || cppParam == null || cppParam.length == 0)
			return false;
		if (cppTypeTextMentionsParam(scope.returnType, cppParam))
			return true;
		for (typeName in scope.localTypes)
			if (cppTypeTextMentionsParam(typeName, cppParam))
				return true;
		return false;
	}

	static function rawTypeHintForExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		if (scope == null)
			return "";
		return switch (expr) {
			case EIdent(name):
				final local = localCppName(name, scope);
				final hinted = scope.localTypeHints.exists(local) ? scope.localTypeHints.get(local) : scope.localTypeHints.get(sanitizeIdentifier(name));
				hinted == null ? "" : hinted;
			case ECast(inner, _) | EUntyped(inner):
				rawTypeHintForExpr(inner, scope);
			case _:
				"";
		};
	}

	static function dceReflectionHelperCallExpr(name:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final helper = sanitizeIdentifier(name);
		if ((helper != "hf" && helper != "nhf") || args == null || args.length < 2)
			return null;
		final classArg = classReferenceArgExprForExpectedType(args[0], "std::shared_ptr<Class>", scope);
		if (classArg == null)
			return null;
		final rendered = [classArg, stringExpr(args[1], scope)];
		for (i in 2...args.length)
			rendered.push(renderExpr(args[i], scope));
		return helper + "(" + rendered.join(", ") + ")";
	}

	static function bytesFastGetExpr(name:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		if (sanitizeIdentifier(name) != "fget" || args.length != 2 || !isCppBytesDataVectorType(exprCppType(args[0], scope)))
			return null;
		return "(" + renderExpr(args[0], scope) + "[" + renderExpr(args[1], scope) + "])";
	}

	static function renderEqCallArgs(args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final out = new Array<String>();
		final firstOptionalStringCode = stringCodeAccessOptionalExpr(args[0], scope);
		final secondOptionalStringCode = stringCodeAccessOptionalExpr(args[1], scope);
		if (firstOptionalStringCode != null && isNullExpr(args[1])) {
			out.push(firstOptionalStringCode);
			out.push("std::optional<int>{}");
			for (i in 2...args.length)
				out.push(renderExpr(args[i], scope));
			return out;
		}
		if (secondOptionalStringCode != null && isNullExpr(args[0])) {
			out.push("std::optional<int>{}");
			out.push(secondOptionalStringCode);
			for (i in 2...args.length)
				out.push(renderExpr(args[i], scope));
			return out;
		}
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		final firstTypeStart = timingEnabled ? Sys.time() : 0.;
		final firstType = inferExprCppType(args[0], scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"phase=eq_infer_first seconds="
				+ Std.string(Sys.time() - firstTypeStart)
				+ " kind="
				+ exprKind(args[0])
				+ " type="
				+ firstType);
		final secondTypeStart = timingEnabled ? Sys.time() : 0.;
		final secondType = inferExprCppType(args[1], scope);
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope,
				"phase=eq_infer_second seconds="
				+ Std.string(Sys.time() - secondTypeStart)
				+ " kind="
				+ exprKind(args[1])
				+ " type="
				+ secondType);
		final firstRenderStart = timingEnabled ? Sys.time() : 0.;
		out.push(eqComparableArgExpr(args[0], firstType, secondType, scope));
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope, "phase=eq_render_first seconds=" + Std.string(Sys.time() - firstRenderStart) + " kind=" + exprKind(args[0]));
		final secondRenderStart = timingEnabled ? Sys.time() : 0.;
		out.push(eqComparableArgExpr(args[1], secondType, firstType, scope));
		if (timingEnabled)
			traceCppScopeStmtTimingPhase(scope, "phase=eq_render_second seconds=" + Std.string(Sys.time() - secondRenderStart) + " kind=" + exprKind(args[1]));
		for (i in 2...args.length)
			out.push(renderExpr(args[i], scope));
		return out;
	}

	static function eqComparableArgExpr(arg:HxExpr, argType:String, otherType:String, ?scope:CppRenderScope):String {
		final otherOptionalInner = cppOptionalInnerType(otherType);
		return switch (arg) {
			case ENull if (otherOptionalInner.length > 0):
				"std::optional<" + otherOptionalInner + ">{}";
			case ENull if (otherType.length > 0 && !isCppOptionalType(otherType) && !isCppReferenceType(otherType)):
				cppDefaultValue(otherType, scope);
			case _ if (isCppVectorLengthExpr(arg, scope)):
				"static_cast<int>(" + renderExpr(arg, scope) + ")";
			case _ if (otherType == "double" && (argType == "int" || isIntLiteralExpr(arg))):
				"static_cast<double>(" + renderExpr(arg, scope) + ")";
			case _ if (argType == "std::any" && otherType.length > 0 && otherType != "std::any"):
				valueExprForExpectedType(arg, otherType, scope);
			case ECall(_, _) if (argType == "std::string"):
				renderExpr(arg, scope);
			case _ if (isEqStringArgExpr(arg, argType, scope)):
				stringExpr(arg, scope);
			case _:
				if (otherOptionalInner.length > 0 && argType == otherOptionalInner) "std::optional<"
					+ otherOptionalInner
					+ ">("
					+ renderExpr(arg, scope)
					+ ")"; else renderExpr(arg, scope);
		};
	}

	static function stringCodeAccessOptionalExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case EArrayAccess(array, index) if (isCppStringExpr(array, scope)):
				"__hxhx_string_code_at("
				+ stringReceiverExpr(array, scope)
				+ ", "
				+ renderExpr(index, scope)
				+ ")";
			case ECall(EField(receiver, method), args) if ((method == "charCodeAt" || method == "cca")
				&& args.length == 1
				&& isCppStringExpr(receiver, scope)):
				"__hxhx_string_code_at("
				+ stringReceiverExpr(receiver, scope)
				+ ", "
				+ renderExpr(args[0], scope)
				+ ")";
			case _:
				null;
		};
	}

	static function isNullExpr(expr:HxExpr):Bool {
		return switch (expr) {
			case ENull:
				true;
			case _:
				false;
		};
	}

	static function isEqStringArgExpr(expr:HxExpr, argType:String, ?scope:CppRenderScope):Bool {
		return isStringLike(expr)
			|| argType == "std::string"
			|| primitiveBackedAbstractToStringExpr(expr, scope) != null
			|| classBackedAbstractToStringExpr(expr, scope) != null;
	}

	static function isIntLiteralExpr(expr:HxExpr):Bool {
		return switch (expr) {
			case EInt(_):
				true;
			case _:
				false;
		};
	}

	static function isCppVectorLengthExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return switch (expr) {
			case EField(receiver, "length"):
				isCppVectorType(exprCppType(receiver, scope));
			case ECall(EField(receiver, "size"), []) | ECall(EField(receiver, "length"), []):
				isCppVectorType(exprCppType(receiver, scope));
			case _:
				false;
		};
	}

	static function vectorMapMapperExpr(mapper:HxExpr, ?scope:CppRenderScope):String {
		final instanceValue = instanceMethodValueExpr(mapper, scope);
		if (instanceValue != null)
			return instanceValue;
		return switch (mapper) {
			case EIdent(name):
				final fn = currentOwnerMethod(name, scope);
				if (fn == null) {
					renderExpr(mapper, scope);
				} else {final names = [
					for (arg in HxFunctionDecl.getArgs(fn))
						sanitizeIdentifier(HxFunctionArg.getName(arg))
				];
					final params = [for (paramName in names) "auto " + paramName];
					final target = HxFunctionDecl.getIsStatic(fn) ? "" : "this->";
					"[&]("
					+ params.join(", ")
					+ ") { return "
					+ target
					+ sanitizeIdentifier(name)
					+ "("
					+ names.join(", ")
					+ "); }";
				}
			case _:
				renderExpr(mapper, scope);
		};
	}

	static function reflectCompareExpr(args:Array<HxExpr>, ?scope:CppRenderScope):String {
		if (args.length != 2)
			throw "C++ Reflect.compare expects 2 argument(s)";
		return "([&]() { auto __hxhx_cmp_left = "
			+ reflectCompareArgExpr(args[0], scope)
			+ "; auto __hxhx_cmp_right = "
			+ reflectCompareArgExpr(args[1], scope)
			+ "; return __hxhx_compare(__hxhx_cmp_left, __hxhx_cmp_right); })()";
	}

	static function reflectCompareFunctionExpr():String {
		return "[](auto left, auto right) { return __hxhx_compare(left, right); }";
	}

	static function reflectCompareMethodsExpr(args:Array<HxExpr>, ?scope:CppRenderScope):String {
		return "__hxhx_reflect_compare_methods("
			+ reflectCompareMethodArgExpr(args[0], scope)
			+ ", "
			+ reflectCompareMethodArgExpr(args[1], scope)
			+ ")";
	}

	static function reflectCompareMethodArgExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final identity = reflectCompareMethodIdentityExpr(expr, scope);
		if (identity != null)
			return identity;
		final sameOwner = sameOwnerMethodValueExpr(expr, scope);
		if (sameOwner != null)
			return sameOwner;
		final instance = instanceMethodValueExpr(expr, scope);
		return instance == null ? renderExpr(expr, scope) : instance;
	}

	/**
		Lower method-value operands to comparable target tokens only for
		`Reflect.compareMethods`. General method values still render as callables.
	**/
	static function reflectCompareMethodIdentityExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		return switch (expr) {
			case EIdent(name):
				final fn = currentOwnerMethod(name, scope);
				if (fn == null) null; else {
					final ownerType = scope.owner == null ? "" : sanitizeTypePath(HxClassDecl.getName(scope.owner));
					if (ownerType.length == 0)
						null;
					else
						cppMethodIdentityExpr(HxFunctionDecl.getIsStatic(fn) ? "nullptr" : "this", ownerType, name);
				}
			case EField(receiver, method):
				final ownerType = switch (receiver) {
					case EThis:
						scope.owner == null ? null : sanitizeTypePath(HxClassDecl.getName(scope.owner));
					case _:
						classNameFromCppExprType(exprCppType(receiver, scope), scope);
				}
				if (ownerType == null || ownerType.length == 0) null; else {
					final fn = classMethodDecl(ownerType, method, false, scope);
					final target = reflectCompareMethodTargetExpr(receiver, scope);
					if (fn == null || target == null)
						null;
					else
						cppMethodIdentityExpr(target, ownerType, method);
				}
			case _:
				null;
		};
	}

	static function reflectCompareMethodTargetExpr(receiver:HxExpr, ?scope:CppRenderScope):Null<String> {
		return switch (receiver) {
			case EThis:
				"this";
			case EIdent(_):
				final rendered = renderExpr(receiver, scope);
				isCppReferenceType(exprCppType(receiver, scope)) ? rendered + ".get()" : "&" + rendered;
			case EField(_, _):
				final rendered = renderExpr(receiver, scope);
				isCppReferenceType(exprCppType(receiver, scope)) ? rendered + ".get()" : null;
			case _:
				null;
		};
	}

	static function cppMethodIdentityExpr(target:String, ownerType:String, method:String):String {
		return "__hxhx_method_identity("
			+ target
			+ ", std::string("
			+ quoteString(sanitizeTypePath(ownerType) + "::" + sanitizeIdentifier(method))
			+ "))";
	}

	static function sameOwnerMethodValueExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		return switch (expr) {
			case EIdent(name):
				final fn = currentOwnerMethod(name, scope);
				if (fn == null) null; else {final names = [
					for (arg in HxFunctionDecl.getArgs(fn))
						sanitizeIdentifier(HxFunctionArg.getName(arg))
				];
					final params = [for (paramName in names) "auto " + paramName];
					final target = HxFunctionDecl.getIsStatic(fn) ? "" : "this->";
					"[&]("
					+ params.join(", ")
					+ ") { return "
					+ target
					+ sanitizeIdentifier(name)
					+ "("
					+ names.join(", ")
					+ "); }";
				}
			case _:
				null;
		};
	}

	static function reflectCompareArgExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final typeName = inferExprCppType(expr, scope);
		return typeName == "std::string" || isStringLike(expr) ? stringExpr(expr, scope) : renderExpr(expr, scope);
	}

	static function lambdaArrayExpr(iterable:HxExpr, ?scope:CppRenderScope):String {
		final structuralIterator = lambdaArrayStructuralIteratorExpr(iterable, scope);
		if (structuralIterator != null)
			return "__hxhx_iterator_to_vector(" + structuralIterator + ")";
		final typeName = exprCppType(iterable, scope);
		if (cppIteratorElementType(typeName).length > 0)
			return "__hxhx_iterator_to_vector(" + renderExpr(iterable, scope) + ")";
		final mapValue = mapValueCppType(typeName);
		if (mapValue.length > 0)
			return "__hxhx_iterator_to_vector(" + renderExpr(iterable, scope) + "->iterator())";
		return "Lambda::array(" + renderExpr(iterable, scope) + ")";
	}

	static function lambdaArrayStructuralIteratorExpr(iterable:HxExpr, ?scope:CppRenderScope):Null<String> {
		return switch (iterable) {
			case EAnon(fieldNames, fieldValues):
				for (i in 0...fieldNames.length) {
					if (sanitizeIdentifier(fieldNames[i]) != "iterator")
						continue;
					return iteratorProviderCallExpr(fieldValues[i], scope);
				}
				null;
			case _:
				null;
		};
	}

	static function iteratorProviderCallExpr(provider:HxExpr, ?scope:CppRenderScope):String {
		return switch (provider) {
			case EField(receiver, method):
				renderExpr(receiver, scope)
				+ fieldAccessOp(receiver, scope)
				+ sanitizeIdentifier(method)
				+ "()";
			case ELambda(args, body) if (args.length == 0):
				"(" + lambdaExpr(args, body, scope) + ")()";
			case _:
				renderExpr(provider, scope);
		};
	}

	static function lambdaArrayResultCppType(iterable:HxExpr, ?scope:CppRenderScope):String {
		final structuralIterator = lambdaArrayStructuralIteratorProvider(iterable);
		if (structuralIterator != null) {
			final element = iteratorProviderElementType(structuralIterator, scope);
			return element.length > 0 ? "std::vector<" + element + ">" : "";
		}
		final typeName = exprCppType(iterable, scope);
		final iteratorElement = cppIteratorElementType(typeName);
		if (iteratorElement.length > 0)
			return "std::vector<" + iteratorElement + ">";
		final mapValue = mapValueCppType(typeName);
		if (mapValue.length > 0)
			return "std::vector<" + mapValue + ">";
		return isCppVectorType(typeName) ? typeName : "";
	}

	static function lambdaArrayStructuralIteratorProvider(iterable:HxExpr):Null<HxExpr> {
		return switch (iterable) {
			case EAnon(fieldNames, fieldValues):
				for (i in 0...fieldNames.length)
					if (sanitizeIdentifier(fieldNames[i]) == "iterator")
						return fieldValues[i];
				null;
			case _:
				null;
		};
	}

	static function iteratorProviderElementType(provider:HxExpr, ?scope:CppRenderScope):String {
		return switch (provider) {
			case EField(receiver, method):
				final receiverType = exprCppType(receiver, scope);
				final methodReturn = mapIteratorMethodReturnType(receiverType, method);
				if (methodReturn.length > 0) cppIteratorElementType(methodReturn); else {
					final ownerType = instanceMethodReceiverClassName(receiverType, scope);
					ownerType == null ? "" : cppIteratorElementType(classMethodCppReturnType(ownerType, method, false, scope));
				}
			case ECall(EField(receiver, method), args) if (args.length == 0):
				cppIteratorElementType(exprCppType(ECall(EField(receiver, method), args), scope));
			case _:
				cppIteratorElementType(exprCppType(provider, scope));
		};
	}

	static function renderSimpleCallArgs(args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		return [for (arg in args) renderExpr(arg, scope)];
	}

	static function renderClassMethodCallArgs(className:String, methodName:String, wantStatic:Bool, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final preludeParamTypes = cppPreludeMethodParamTypes(className, methodName);
		if (preludeParamTypes.length > 0)
			return renderKnownCppParamCallArgs(preludeParamTypes, args, scope);
		final supportParamTypes = knownStdlibMethodParamCppTypes(className, methodName, scope, lookupForScope(scope));
		if (supportParamTypes.length > 0)
			return renderKnownCppParamCallArgs(supportParamTypes, args, scope);
		final fn = classMethodDecl(className, methodName, wantStatic, scope);
		if (fn == null)
			return renderSimpleCallArgs(args, scope);
		final owner = scope == null ? null : scope.classByName.get(className);
		final paramTypes = owner == null ? null : inferredFunctionArgCppTypes(fn, owner, scope.classByName, scope.allClasses);
		return renderFunctionCallArgs(HxFunctionDecl.getArgs(fn), args, scope, paramTypes);
	}

	static function renderKnownCppParamCallArgs(paramTypes:Array<String>, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final out = new Array<String>();
		for (i in 0...args.length) {
			final expected = i < paramTypes.length ? paramTypes[i] : "";
			out.push(expected.length > 0 ? valueExprForExpectedType(args[i], expected, scope) : renderExpr(args[i], scope));
		}
		return out;
	}

	static function renderInstanceMethodCallArgs(receiverCppType:String, methodName:String, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final className = instanceMethodReceiverClassName(receiverCppType, scope);
		if (className == null)
			return renderSimpleCallArgs(args, scope);
		final supportParamTypes = knownStdlibMethodParamCppTypes(className, methodName, scope, lookupForScope(scope));
		if (supportParamTypes.length > 0)
			return renderKnownCppParamCallArgs(supportParamTypes, args, scope);
		final fn = classMethodDecl(className, methodName, false, scope);
		if (fn == null)
			return renderSimpleCallArgs(args, scope);
		final owner = scope == null ? null : scope.classByName.get(className);
		final paramTypes = owner == null ? null : instantiateGenericClassParamTypes(className, receiverCppType,
			inferredFunctionArgCppTypes(fn, owner, scope.classByName, scope.allClasses), scope);
		return renderFunctionCallArgs(HxFunctionDecl.getArgs(fn), args, scope, paramTypes);
	}

	static function instanceMethodReceiverClassName(receiverCppType:String, ?scope:CppRenderScope):Null<String> {
		final referenceName = classNameFromCppType(receiverCppType);
		if (referenceName != null) {
			final base = sanitizeTypePath(typeBaseName(referenceName));
			return scopeHasClass(scope, base) ? base : null;
		}
		return classNameFromCppExprType(receiverCppType, scope);
	}

	static function instantiateGenericClassParamTypes(className:String, receiverCppType:String, paramTypes:Array<String>, ?scope:CppRenderScope):Array<String> {
		if (paramTypes == null || paramTypes.length == 0)
			return paramTypes;
		final typeParams = genericClassTypeParamsForName(className, scope);
		final typeArgs = templateArgsFromExpectedClassType(className, receiverCppType);
		if (typeParams.length == 0 || typeArgs.length == 0)
			return paramTypes;
		return [
			for (typeName in paramTypes)
				substituteCppTypeParams(typeName, typeParams, typeArgs)
		];
	}

	static function instantiateGenericClassFieldType(className:String, receiverCppType:String, fieldType:String, ?scope:CppRenderScope):String {
		if (fieldType == null || fieldType.length == 0)
			return fieldType;
		final typeParams = genericClassTypeParamsForName(className, scope);
		final typeArgs = templateArgsFromExpectedClassType(className, receiverCppType);
		if (typeParams.length == 0 || typeArgs.length == 0)
			return fieldType;
		return substituteCppTypeParams(fieldType, typeParams, typeArgs);
	}

	static function stringMapValueCppType(receiverCppType:String):String {
		return mapValueCppType(receiverCppType);
	}

	static function mapValueCppType(receiverCppType:String):String {
		final stringArgs = templateArgsFromExpectedClassType("StringMap", receiverCppType);
		if (stringArgs.length == 1)
			return stringArgs[0];
		final intArgs = templateArgsFromExpectedClassType("IntMap", receiverCppType);
		if (intArgs.length == 1)
			return intArgs[0];
		final hashArgs = templateArgsFromExpectedClassType("HashMap", receiverCppType);
		if (hashArgs.length == 2)
			return hashArgs[1];
		final mapArgs = templateArgsFromExpectedClassType("Map", receiverCppType);
		return mapArgs.length == 2 ? mapArgs[1] : "";
	}

	static function mapKeyCppType(receiverCppType:String):String {
		if (templateArgsFromExpectedClassType("StringMap", receiverCppType).length == 1)
			return "std::string";
		if (templateArgsFromExpectedClassType("IntMap", receiverCppType).length == 1)
			return "int";
		final hashArgs = templateArgsFromExpectedClassType("HashMap", receiverCppType);
		if (hashArgs.length == 2)
			return hashArgs[0];
		final mapArgs = templateArgsFromExpectedClassType("Map", receiverCppType);
		return mapArgs.length == 2 ? mapArgs[0] : "";
	}

	static function mapValueLookupExpr(mapLocal:String, keyLocal:String, receiverCppType:String, valueType:String):String {
		final access = isCppReferenceType(receiverCppType) ? "->" : ".";
		final getExpr = mapLocal + access + "get(" + keyLocal + ")";
		if (templateArgsFromExpectedClassType("StringMap", receiverCppType).length == 1
			|| templateArgsFromExpectedClassType("IntMap", receiverCppType).length == 1)
			return getExpr + ".value_or(" + valueType + "{})";
		return getExpr;
	}

	static function keyValueLoopTypes(iterable:HxExpr, ?scope:CppRenderScope):Array<String> {
		final iterableType = exprCppType(iterable, scope);
		final mapKey = mapKeyCppType(iterableType);
		final mapValue = mapValueCppType(iterableType);
		if (mapKey.length > 0 && mapValue.length > 0)
			return [mapKey, mapValue];
		final elementType = iterableElementType(iterable, scope);
		final pairArgs = cppPairTypeArgs(elementType);
		return pairArgs.length == 2 ? pairArgs : ["int", elementType];
	}

	static function mapIteratorMethodReturnType(receiverCppType:String, method:String):String {
		final cleanMethod = sanitizeIdentifier(method == null ? "" : method);
		if (cleanMethod == "keys") {
			final keyType = mapKeyCppType(receiverCppType);
			return keyType.length > 0 ? "std::shared_ptr<__hxhx_iterator<" + keyType + ">>" : "";
		}
		if (cleanMethod == "iterator") {
			final valueType = mapValueCppType(receiverCppType);
			return valueType.length > 0 ? "std::shared_ptr<__hxhx_iterator<" + valueType + ">>" : "";
		}
		return "";
	}

	static function substituteCppTypeParams(typeName:String, typeParams:Array<String>, typeArgs:Array<String>):String {
		var out = typeName;
		final count = typeParams.length < typeArgs.length ? typeParams.length : typeArgs.length;
		for (i in 0...count)
			out = replaceCppTypeParamToken(out, typeParams[i], typeArgs[i]);
		return out;
	}

	static function replaceCppTypeParamToken(typeName:String, param:String, replacement:String):String {
		final clean = sanitizeIdentifier(param);
		if (typeName == null || clean.length == 0 || replacement == null || replacement.length == 0)
			return typeName;
		final out = new StringBuf();
		var i = 0;
		while (i < typeName.length) {
			if (typeName.substr(i, clean.length) == clean
				&& !isCppIdentChar(typeName.charAt(i - 1))
				&& !isCppIdentChar(typeName.charAt(i + clean.length))) {
				out.add(replacement);
				i += clean.length;
			} else {
				out.add(typeName.charAt(i));
				i++;
			}
		}
		return out.toString();
	}

	static function isCppIdentChar(ch:String):Bool {
		if (ch == null || ch.length == 0)
			return false;
		final code = ch.charCodeAt(0);
		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| (code >= "0".code && code <= "9".code)
			|| ch == "_";
	}

	static function renderFunctionCallArgs(params:Array<HxFunctionArg>, args:Array<HxExpr>, ?scope:CppRenderScope, ?paramTypes:Array<String>):Array<String> {
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		if (params == null || params.length == 0 || args == null || args.length == 0) {
			final simpleStart = timingEnabled ? Sys.time() : 0.0;
			final simple = renderSimpleCallArgs(args, scope);
			if (timingEnabled && args != null && args.length > 0)
				traceCallArgRenderPhase(scope, args[0], null, "simple_args", Sys.time()
					- simpleStart, "", "", "", "",
					"args="
					+ Std.string(args.length)
					+ " rendered="
					+ Std.string(simple.length));
			return simple;
		}
		final out = new Array<String>();
		var paramIndex = 0;
		var argIndex = 0;
		while (argIndex < args.length) {
			if (paramIndex >= params.length) {
				final extraStart = timingEnabled ? Sys.time() : 0.0;
				final extra = renderExpr(args[argIndex], scope);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, args[argIndex], null, "extra_arg_render", Sys.time() - extraStart, "", "", "", "",
						"arg_index=" + Std.string(argIndex));
				out.push(extra);
				argIndex++;
				continue;
			}
			final param = params[paramIndex];
			final arg = args[argIndex];
			final matchStart = timingEnabled ? Sys.time() : 0.0;
			final canSkip = callParamCanBeSkipped(param);
			final matchesParam = !canSkip || callArgMatchesParam(arg, param, scope);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "param_match", Sys.time()
					- matchStart, "", paramTypes == null ? "" : paramTypes[paramIndex], "",
					"",
					"can_skip="
					+ Std.string(canSkip)
					+ " matches="
					+ Std.string(matchesParam)
					+ " arg_index="
					+ Std.string(argIndex)
					+ " param_index="
					+ Std.string(paramIndex));
			if (matchesParam) {
				final renderStart = timingEnabled ? Sys.time() : 0.0;
				final rendered = callArgExprForParam(arg, param, scope, paramTypes == null ? "" : paramTypes[paramIndex]);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, param, "param_arg_render", Sys.time()
						- renderStart, "",
						paramTypes == null ? "" : paramTypes[paramIndex], "", "",
						"arg_index="
						+ Std.string(argIndex)
						+ " param_index="
						+ Std.string(paramIndex));
				out.push(rendered);
				paramIndex++;
				argIndex++;
				continue;
			}
			final laterStart = timingEnabled ? Sys.time() : 0.0;
			final later = findLaterMatchingParam(params, arg, paramIndex + 1, scope);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "later_match", Sys.time()
					- laterStart, "", paramTypes == null ? "" : paramTypes[paramIndex], "",
					"", "later="
					+ Std.string(later)
					+ " arg_index="
					+ Std.string(argIndex)
					+ " param_index="
					+ Std.string(paramIndex));
			if (later < 0) {
				final renderStart = timingEnabled ? Sys.time() : 0.0;
				final rendered = callArgExprForParam(arg, param, scope, paramTypes == null ? "" : paramTypes[paramIndex]);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, param, "fallback_arg_render", Sys.time()
						- renderStart, "",
						paramTypes == null ? "" : paramTypes[paramIndex], "", "",
						"arg_index="
						+ Std.string(argIndex)
						+ " param_index="
						+ Std.string(paramIndex));
				out.push(rendered);
				paramIndex++;
				argIndex++;
				continue;
			}
			while (paramIndex < later) {
				final defaultStart = timingEnabled ? Sys.time() : 0.0;
				final defaultArg = callDefaultArgExpr(params[paramIndex], scope);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, params[paramIndex], "default_arg_render", Sys.time()
						- defaultStart, "", "", "", "",
						"arg_index="
						+ Std.string(argIndex)
						+ " param_index="
						+ Std.string(paramIndex));
				out.push(defaultArg);
				paramIndex++;
			}
			final renderStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = callArgExprForParam(arg, params[paramIndex], scope, paramTypes == null ? "" : paramTypes[paramIndex]);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, params[paramIndex], "later_arg_render", Sys.time()
					- renderStart, "",
					paramTypes == null ? "" : paramTypes[paramIndex], "", "", "arg_index="
					+ Std.string(argIndex)
					+ " param_index="
					+ Std.string(paramIndex));
			out.push(rendered);
			paramIndex++;
			argIndex++;
		}
		return out;
	}

	static function renderFunctionTypeCallArgs(functionType:String, args:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		final argTypes = CppTypeModel.cppFunctionArgTypesFromCppType(functionType);
		if (argTypes.length == 0)
			return renderSimpleCallArgs(args, scope);
		final rendered = new Array<String>();
		final callArgs = args == null ? [] : args;
		var argIndex = 0;
		var paramIndex = 0;
		while (argIndex < callArgs.length) {
			final arg = callArgs[argIndex];
			if (paramIndex >= argTypes.length) {
				rendered.push(renderExpr(arg, scope));
				argIndex++;
				continue;
			}
			if (functionTypeArgMatches(arg, argTypes[paramIndex], scope)) {
				rendered.push(functionTypeArgExpr(arg, argTypes[paramIndex], scope));
				argIndex++;
				paramIndex++;
				continue;
			}
			final later = findLaterMatchingFunctionTypeArg(argTypes, arg, paramIndex + 1, scope);
			if (later >= 0) {
				while (paramIndex < later) {
					rendered.push(cppDefaultValue(argTypes[paramIndex], scope));
					paramIndex++;
				}
				rendered.push(functionTypeArgExpr(arg, argTypes[paramIndex], scope));
				argIndex++;
				paramIndex++;
				continue;
			}
			rendered.push(functionTypeArgExpr(arg, argTypes[paramIndex], scope));
			argIndex++;
			paramIndex++;
		}
		while (paramIndex < argTypes.length) {
			rendered.push(cppDefaultValue(argTypes[paramIndex], scope));
			paramIndex++;
		}
		return rendered;
	}

	static function functionTypeArgExpr(arg:HxExpr, expectedType:String, ?scope:CppRenderScope):String {
		final actualType = exprCppType(arg, scope);
		if (isCppFunctionType(expectedType))
			return actualType == expectedType ? renderExpr(arg, scope) : valueExprForExpectedType(arg, expectedType, scope);
		if (actualType == null || actualType.length == 0)
			return renderExpr(arg, scope);
		return actualType == expectedType ? renderExpr(arg, scope) : valueExprForExpectedType(arg, expectedType, scope);
	}

	static function findLaterMatchingFunctionTypeArg(argTypes:Array<String>, arg:HxExpr, startIndex:Int, ?scope:CppRenderScope):Int {
		for (i in startIndex...argTypes.length)
			if (functionTypeArgMatches(arg, argTypes[i], scope))
				return i;
		return -1;
	}

	static function functionTypeArgMatches(arg:HxExpr, expectedType:String, ?scope:CppRenderScope):Bool {
		if (expectedType == null || expectedType.length == 0)
			return false;
		final actualType = exprCppType(arg, scope);
		if (actualType.length > 0)
			return actualType == expectedType || (actualType == "std::any" && expectedType.length > 0);
		return switch (expectedType) {
			case "std::string":
				isCppStringExpr(arg, scope);
			case "int":
				isCppIntExpr(arg, scope);
			case "double" | "float": isCppDoubleExpr(arg, scope) || isCppIntExpr(arg, scope);
			case "bool":
				isCppBoolExpr(arg, scope);
			case _:
				false;
		};
	}

	static function findLaterMatchingParam(params:Array<HxFunctionArg>, arg:HxExpr, startIndex:Int, ?scope:CppRenderScope):Int {
		for (i in startIndex...params.length) {
			var skippable = true;
			for (j in startIndex...i)
				if (!callParamCanBeSkipped(params[j]))
					skippable = false;
			if (skippable && callArgMatchesParam(arg, params[i], scope))
				return i;
		}
		return -1;
	}

	static function callParamCanBeSkipped(param:HxFunctionArg):Bool {
		if (HxFunctionArg.getIsOptional(param))
			return true;
		return switch (HxFunctionArg.getDefaultValue(param)) {
			case NoDefault:
				false;
			case Default(_):
				true;
		};
	}

	static function callArgMatchesParam(arg:HxExpr, param:HxFunctionArg, ?scope:CppRenderScope):Bool {
		final argType = callArgMatchCppType(arg, scope);
		if (argType == null || argType.length == 0)
			return false;
		final paramType = cppFunctionArgType(param, scope);
		if (argType == paramType)
			return true;
		final inner = cppOptionalInnerType(paramType);
		return inner.length > 0 && argType == inner;
	}

	static function callArgMatchCppType(arg:HxExpr, ?scope:CppRenderScope):String {
		final explicit = exprCppType(arg, scope);
		if (explicit.length > 0)
			return explicit;
		return inferExprCppType(arg, scope);
	}

	static function callArgExprForParam(arg:HxExpr, param:HxFunctionArg, ?scope:CppRenderScope, ?expectedParamType:String):String {
		final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
		final declaredTypeStart = timingEnabled ? Sys.time() : 0.0;
		final declaredParamType = cppFunctionArgType(param, scope);
		final declaredValueType = cppOptionalInnerType(declaredParamType).length > 0 ? cppOptionalInnerType(declaredParamType) : declaredParamType;
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "declared_type", Sys.time() - declaredTypeStart, declaredParamType, expectedParamType,
				declaredValueType);
		final declaredClassRefStart = timingEnabled ? Sys.time() : 0.0;
		final declaredClassReferenceArg = classReferenceArgExprForExpectedType(arg, declaredValueType, scope);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "declared_class_ref", Sys.time() - declaredClassRefStart, declaredParamType, expectedParamType,
				declaredValueType, "", "hit=" + Std.string(declaredClassReferenceArg != null));
		if (declaredClassReferenceArg != null)
			return declaredClassReferenceArg;
		final expectedTypeStart = timingEnabled ? Sys.time() : 0.0;
		final paramType = expectedParamType != null && expectedParamType.length > 0 ? expectedParamType : cppFunctionArgType(param, scope);
		final valueType = cppOptionalInnerType(paramType).length > 0 ? cppOptionalInnerType(paramType) : paramType;
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "expected_type", Sys.time() - expectedTypeStart, declaredParamType, paramType, valueType);
		final abstractStart = timingEnabled ? Sys.time() : 0.0;
		final abstractArg = primitiveBackedAbstractCallArgExpr(arg, param, valueType, scope);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "primitive_abstract", Sys.time() - abstractStart, declaredParamType, paramType, valueType, "",
				"hit=" + Std.string(abstractArg != null));
		if (abstractArg != null)
			return abstractArg;
		switch (arg) {
			case ENull:
				final nullStart = timingEnabled ? Sys.time() : 0.0;
				final rendered = valueExprForExpectedType(arg, valueType, scope);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, param, "null_expected_render", Sys.time() - nullStart, declaredParamType, paramType, valueType);
				return rendered;
			case _:
		}
		final expectedClassStart = timingEnabled ? Sys.time() : 0.0;
		final expectedClass = classNameFromCppType(valueType);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "expected_class", Sys.time() - expectedClassStart, declaredParamType, paramType, valueType, "",
				"class=" + (expectedClass == null ? "" : sanitizeTypePath(expectedClass)));
		if (expectedClass != null) {
			switch (arg) {
				case EThis if (currentOwnerIsOrExtends(expectedClass, scope)):
					final rendered = CppRuntimeSupport.borrowedSharedPtrExpr(expectedClass, "this");
					if (timingEnabled)
						traceCallArgRenderPhase(scope, arg, param, "this_shared_ptr", 0.0, declaredParamType, paramType, valueType);
					return rendered;
				case _:
			}
		}
		if (valueType == "std::shared_ptr<PosInfos>") {
			final posStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = posInfosSharedPtrExpr(arg, scope);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "pos_infos_render", Sys.time() - posStart, declaredParamType, paramType, valueType);
			return rendered;
		}
		final classRefStart = timingEnabled ? Sys.time() : 0.0;
		final classReferenceArg = classReferenceArgExprForExpectedType(arg, valueType, scope);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "class_ref", Sys.time() - classRefStart, declaredParamType, paramType, valueType, "",
				"hit=" + Std.string(classReferenceArg != null));
		if (classReferenceArg != null)
			return classReferenceArg;
		final actualTypeStart = timingEnabled ? Sys.time() : 0.0;
		final actualType = exprCppType(arg, scope);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "actual_type", Sys.time() - actualTypeStart, declaredParamType, paramType, valueType, actualType);
		if (valueType == "std::shared_ptr<EnumValue>" && actualType == "std::any") {
			final enumStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = "__hxhx_enum_value_ptr(" + renderExpr(arg, scope) + ")";
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "enum_any_render", Sys.time() - enumStart, declaredParamType, paramType, valueType, actualType);
			return rendered;
		}
		if (structuralTypedefClassForCppType(valueType, scope) != null && actualType != valueType) {
			final structuralStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = valueExprForExpectedType(arg, valueType, scope);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "structural_expected_render", Sys.time() - structuralStart, declaredParamType, paramType,
					valueType, actualType);
			return rendered;
		}
		if (valueType == "std::string") {
			if (actualType == "std::string") {
				final stringStart = timingEnabled ? Sys.time() : 0.0;
				final rendered = renderExpr(arg, scope);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, param, "string_render", Sys.time() - stringStart, declaredParamType, paramType, valueType, actualType);
				return rendered;
			}
			if (actualType == "std::any"
				|| isScalarStringCoercibleCppType(actualType)
				|| isCppAnonStructType(actualType)
				|| argHasErasedArgTypeOverride(arg, scope)) {
				final stringStart = timingEnabled ? Sys.time() : 0.0;
				final rendered = stringExpr(arg, scope);
				if (timingEnabled)
					traceCallArgRenderPhase(scope, arg, param, "string_coerce_render", Sys.time() - stringStart, declaredParamType, paramType, valueType,
						actualType);
				return rendered;
			}
		}
		if ((valueType == "double" || valueType == "float") && actualType == "std::any") {
			final anyStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = "__hxhx_any_double(" + renderExpr(arg, scope) + ")";
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "double_any_render", Sys.time() - anyStart, declaredParamType, paramType, valueType, actualType);
			return rendered;
		}
		if (valueType == "int" && actualType == "std::any") {
			final anyStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = "static_cast<int>(__hxhx_any_double(" + renderExpr(arg, scope) + "))";
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "int_any_render", Sys.time() - anyStart, declaredParamType, paramType, valueType, actualType);
			return rendered;
		}
		if (valueType == "std::vector<std::string>" && actualType == "std::any") {
			final anyStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = "__hxhx_string_vector_any(" + renderExpr(arg, scope) + ")";
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "string_vector_any_render", Sys.time() - anyStart, declaredParamType, paramType, valueType,
					actualType);
			return rendered;
		}
		if (isCppVectorType(valueType)) {
			switch (arg) {
				case EArrayDecl([]):
					final rendered = valueType + "{}";
					if (timingEnabled)
						traceCallArgRenderPhase(scope, arg, param, "empty_vector_literal", 0.0, declaredParamType, paramType, valueType, actualType);
					return rendered;
				case EArrayDecl(_):
					final vectorStart = timingEnabled ? Sys.time() : 0.0;
					final rendered = valueExprForExpectedType(arg, valueType, scope);
					if (timingEnabled)
						traceCallArgRenderPhase(scope, arg, param, "vector_expected_render", Sys.time() - vectorStart, declaredParamType, paramType,
							valueType, actualType);
					return rendered;
				case _:
			}
		}
		if (isCppReferenceType(valueType)) {
			final refStart = timingEnabled ? Sys.time() : 0.0;
			final rendered = valueExprForExpectedType(arg, valueType, scope);
			if (timingEnabled)
				traceCallArgRenderPhase(scope, arg, param, "reference_expected_render", Sys.time() - refStart, declaredParamType, paramType, valueType,
					actualType);
			return rendered;
		}
		final finalRenderStart = timingEnabled ? Sys.time() : 0.0;
		final rendered = renderExpr(arg, scope);
		if (timingEnabled)
			traceCallArgRenderPhase(scope, arg, param, "final_render", Sys.time() - finalRenderStart, declaredParamType, paramType, valueType, actualType);
		return rendered;
	}

	static function primitiveBackedAbstractCallArgExpr(arg:HxExpr, param:HxFunctionArg, valueType:String, ?scope:CppRenderScope):Null<String> {
		if (param == null || scope == null)
			return null;
		final hint = HxFunctionArg.getTypeHint(param);
		final underlying = primitiveBackedAbstractCppTypeForTypeHint(hint, scope);
		if (underlying == null || underlying != valueType)
			return null;
		final rendered = valueExprForExpectedType(arg, valueType, scope);
		final converted = primitiveBackedAbstractCtorSideEffectExpr(hint, [arg], rendered, scope);
		return converted == rendered ? null : converted;
	}

	static function isScalarStringCoercibleCppType(typeName:String):Bool {
		return typeName == "int" || typeName == "double" || typeName == "float" || typeName == "long long" || typeName == "unsigned int" || typeName == "bool";
	}

	static function argHasErasedArgTypeOverride(arg:HxExpr, ?scope:CppRenderScope):Bool {
		if (scope == null)
			return false;
		return switch (arg) {
			case EIdent(name):
				scope.argTypeOverrides.get(sanitizeIdentifier(name)) == "std::any";
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				argHasErasedArgTypeOverride(args[2], scope);
			case ECall(EIdent("__hxhx_parenthesized"), args) if (args.length == 1):
				argHasErasedArgTypeOverride(args[0], scope);
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				argHasErasedArgTypeOverride(inner, scope);
			case _:
				false;
		};
	}

	static function callDefaultArgExpr(param:HxFunctionArg, ?scope:CppRenderScope):String {
		final paramType = cppFunctionArgType(param, scope);
		return switch (HxFunctionArg.getDefaultValue(param)) {
			case Default(expr):
				final valueType = cppOptionalInnerType(paramType).length > 0 ? cppOptionalInnerType(paramType) : paramType;
				valueType == "std::string" ? stringExpr(expr, scope) : callArgExprForParam(expr, param, scope);
			case NoDefault:
				cppDefaultValue(paramType, scope);
		};
	}

	static function cppOptionalInnerType(typeName:String):String {
		final prefix = "std::optional<";
		return typeName != null
			&& StringTools.startsWith(typeName, prefix)
			&& StringTools.endsWith(typeName, ">") ? typeName.substr(prefix.length, typeName.length - prefix.length - 1) : "";
	}

	static function isCppOptionalVectorType(typeName:String):Bool {
		return isCppVectorType(typeName) && cppOptionalInnerType(cppVectorElementType(typeName)).length > 0;
	}

	static function globalIntrinsicCallExpr(method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final rendered = [for (arg in args) renderExpr(arg, scope)];
		return switch (method) {
			case "__hxcpp_memory_get_double" if (args.length == 2):
				"__hxhx_memory_get_double(" + rendered.join(", ") + ")";
			case "__hxcpp_memory_get_float" if (args.length == 2):
				"__hxhx_memory_get_float(" + rendered.join(", ") + ")";
			case "__hxcpp_memory_set_double" if (args.length == 3):
				"__hxhx_memory_set_double(" + rendered.join(", ") + ")";
			case "__hxcpp_memory_set_float" if (args.length == 3):
				"__hxhx_memory_set_float(" + rendered.join(", ") + ")";
			case "__hxcpp_reinterpret_le_int32_as_float32" if (args.length == 1):
				"__hxhx_reinterpret_le_int32_as_float32(" + rendered.join(", ") + ")";
			case "__hxcpp_reinterpret_float32_as_le_int32" if (args.length == 1):
				"__hxhx_reinterpret_float32_as_le_int32(" + rendered.join(", ") + ")";
			case "__hxcpp_reinterpret_le_int32s_as_float64" if (args.length == 2):
				"__hxhx_reinterpret_le_int32s_as_float64(" + rendered.join(", ") + ")";
			case "__hxcpp_reinterpret_float64_as_le_int32_low" if (args.length == 1):
				"__hxhx_reinterpret_float64_as_le_int32_low(" + rendered.join(", ") + ")";
			case "__hxcpp_reinterpret_float64_as_le_int32_high" if (args.length == 1):
				"__hxhx_reinterpret_float64_as_le_int32_high(" + rendered.join(", ") + ")";
			case "__hxcpp_string_of_bytes" if (args.length >= 4):
				"__hxhx_string_of_bytes("
				+ renderExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ", "
				+ renderExpr(args[2], scope)
				+ ", "
				+ renderExpr(args[3], scope)
				+ ")";
			case "__hxcpp_bytes_of_string" if (args.length == 2):
				"__hxhx_bytes_of_string(" + rendered.join(", ") + ")";
			case "__hxcpp_utc_date" if (args.length == 6):
				"__hxhx_utc_date(" + rendered.join(", ") + ")";
			case "String" if (args.length == 1):
				"__hxhx_string_from_pointer(" + renderExpr(args[0], scope) + ")";
			case "String" if (args.length == 2):
				"__hxhx_string_from_pointer("
				+ renderExpr(args[0], scope)
				+ ", "
				+ renderExpr(args[1], scope)
				+ ")";
			case _:
				renderExpr(EIdent("__global__"), scope) + "." + sanitizeIdentifier(method) + "(" + rendered.join(", ") + ")";
		};
	}

	static function globalIntrinsicReturnCppType(method:String):String {
		return switch (method) {
			case "__hxcpp_memory_get_double" | "__hxcpp_memory_get_float":
				"double";
			case "__hxcpp_utc_date":
				"double";
			case "__hxcpp_reinterpret_le_int32_as_float32" | "__hxcpp_reinterpret_le_int32s_as_float64":
				"double";
			case "__hxcpp_reinterpret_float32_as_le_int32" | "__hxcpp_reinterpret_float64_as_le_int32_low" | "__hxcpp_reinterpret_float64_as_le_int32_high":
				"int";
			case "String":
				"std::string";
			case "__hxcpp_memory_set_double" | "__hxcpp_memory_set_float" | "__hxcpp_string_of_bytes" | "__hxcpp_bytes_of_string":
				"void";
			case _:
				"";
		};
	}

	static function stringCodeAtExpr(s:HxExpr, index:HxExpr, ?scope:CppRenderScope):String {
		return "static_cast<int>(static_cast<unsigned char>(" + stringReceiverExpr(s, scope) + "[" + renderExpr(index, scope) + "]))";
	}

	static function flatMapExpr(iterable:HxExpr, mapper:HxExpr, ?scope:CppRenderScope):String {
		final mappedType = cppFunctionReturnTypeFromCppType(exprCppType(mapper, scope));
		final elementType = cppIterableElementType(mappedType, scope);
		final outputType = elementType.length > 0 ? elementType : "std::string";
		final source = renderExpr(iterable, scope);
		final f = renderExpr(mapper, scope);
		return "([&]() {\n"
			+ "  std::vector<"
			+ outputType
			+ "> __hxhx_flat_map_out;\n"
			+ "  for (auto __hxhx_flat_map_item : "
			+ source
			+ ") {\n"
			+ "    for (auto __hxhx_flat_map_value : "
			+ f
			+ "(__hxhx_flat_map_item)) {\n"
			+ "      __hxhx_flat_map_out.push_back(__hxhx_flat_map_value);\n"
			+ "    }\n"
			+ "  }\n"
			+ "  return __hxhx_flat_map_out;\n"
			+ "})()";
	}

	static function fieldAccessOp(receiver:HxExpr, ?scope:CppRenderScope):String {
		return fieldAccessOpForCppType(exprCppType(receiver, scope));
	}

	static function fieldAccessOpForCppType(typeName:String):String {
		return isCppReferenceType(typeName) ? "->" : ".";
	}

	static function isCppExceptionValueType(typeName:String):Bool {
		return typeName == "__hxhx_exception_value";
	}

	static function isCppDynamicValueType(typeName:String):Bool {
		return typeName == "__hxhx_dynamic_value";
	}

	static function exprHasReferenceType(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return isCppReferenceType(exprCppType(expr, scope));
	}

	static function isCppEnumCarrierReferenceType(typeName:String, ?scope:CppRenderScope):Bool {
		final className = classNameFromCppType(typeName);
		if (className == null || scope == null)
			return false;
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return false;
		for (field in HxClassDecl.getFields(cls))
			if (HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == "__hx_is_enum")
				return true;
		return false;
	}

	static function isCppTypePathReferenceType(typeName:String):Bool {
		final className = classNameFromCppType(typeName);
		return className != null && sanitizeTypePath(typeBaseName(className)) == "TypePath";
	}

	static function exprHasOptionalType(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return isCppOptionalType(exprCppType(expr, scope));
	}

	static function exprHasNonNullableValueType(expr:HxExpr, ?scope:CppRenderScope):Bool {
		final typeName = exprCppType(expr, scope);
		return typeName.length > 0 && !isCppOptionalType(typeName) && !isCppReferenceType(typeName);
	}

	static function optionalStorageExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case EIdent(name):
				sanitizeIdentifier(name);
			case _:
				renderExpr(expr, scope);
		};
	}

	static function exprCppType(expr:HxExpr, ?scope:CppRenderScope):String {
		if (scope == null)
			return "";
		return switch (expr) {
			case EIdent(name):
				final cppLocal = localCppName(name, scope);
				final local = scope.localTypes.exists(cppLocal) ? scope.localTypes.get(cppLocal) : scope.localTypes.get(sanitizeIdentifier(name));
				if (local != null && local.length > 0) {
					local;
				} else {
					final currentField = currentOwnerFieldCppType(name, scope);
					currentField.length > 0 ? currentField : inheritedInstanceFieldCppType(name, scope);
				}
			case ECast(inner, _) | EUntyped(inner):
				exprCppType(inner, scope);
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				exprCppType(args[2], scope);
			case ECall(EIdent("__hxhx_parenthesized"), args) if (args.length == 1):
				exprCppType(args[0], scope);
			case EThis:
				sanitizeTypePath(HxClassDecl.getName(scope.owner));
			case ENew(typePath, _):
				cppNewExprType(typePath, scope);
			case ECall(EField(EIdent("NativeArray"), "create"), _):
				nativeArrayVectorType(scope);
			case ECall(EField(receiver, "create"), _) if (isCppNativeArrayReceiver(receiver)):
				nativeArrayVectorType(scope);
			case ECall(EField(receiver, "unsafeGet"), args) if (args.length == 2 && isCppNativeArrayReceiver(receiver)):
				cppVectorElementType(exprCppType(args[0], scope));
			case ECall(EField(receiver, method), args) if (int64StaticOrHelperCallReturnCppType(receiver, method, args.length).length > 0):
				int64StaticOrHelperCallReturnCppType(receiver, method, args.length);
			case ECall(EField(receiver, method), args) if (int64InstanceOrExtensionCallReturnCppType(receiver, method, args, scope).length > 0):
				int64InstanceOrExtensionCallReturnCppType(receiver, method, args, scope);
			case ECall(EIdent("__hxhx_int_literal"), [_, EString(_)]):
				"long long";
			case ECall(EIdent(name), args)
				if (int64ImportedStaticCallReturnCppType(name, args.length).length > 0
					&& currentOrInheritedOwnerMethodOwner(name, scope) == null):
				int64ImportedStaticCallReturnCppType(name, args.length);
			case ECall(EField(EIdent("Math"), method), _):
				mathReturnCppType(method);
			case ECall(EField(receiver, "field"), args) if (isReflectStaticReceiver(receiver) && args.length == 2):
				"std::any";
			case ECall(EField(receiver, "callMethod"), args) if (isReflectStaticReceiver(receiver) && args.length == 3):
				"std::any";
			case ECall(EField(receiver, "isFunction"), args) if (isReflectStaticReceiver(receiver) && args.length == 1):
				"bool";
			case ECall(EField(EArrayDecl(elements), "toString"), args) if (args.length == 0 && isMapLiteralElements(elements)):
				"std::string";
			case ECall(ECall(loadCallee, loadArgs), _) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				"std::any";
			case ECall(loadCallee, loadArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				"std::any";
			case ECall(EIdent("__hxhx_optional_lambda"), args) if (args.length >= 1):
				inferExprCppType(args[0], scope);
			case ECall(EField(receiver, "callMacroApi"), args) if (isContextStaticReceiver(receiver) && args.length >= 1):
				"std::any";
			case ECall(EIdent("callMacroApi"), args) if (scopeOwnerIsContext(scope) && args.length >= 1):
				"std::any";
			case ECall(EField(receiver, "array"), args) if (isLambdaStaticReceiver(receiver) && args.length == 1):
				lambdaArrayResultCppType(args[0], scope);
			case ECall(EField(EIdent("Type"), method), args):
				typeIntrinsicReturnCppType(method, args);
			case ECall(EField(receiver, "fromCharCode"), args) if (isStringStaticReceiver(receiver) && args.length == 1):
				"std::string";
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				"std::string";
			case ECall(EField(receiver, "parseInt"), args) if (isStdStaticReceiver(receiver) && args.length == 1):
				"std::optional<int>";
			case ECall(EField(receiver, "downcast"), args) if (isStdStaticReceiver(receiver) && args.length == 2):
				"std::string";
			case ECall(EField(receiver, "isOfType"), args) if (isStdStaticReceiver(receiver) && args.length == 2):
				"bool";
			case ECall(EIdent(name), _) if (sameOwnerCallReturnsErasedDynamicValue(name, scope)):
				"std::any";
			case ECall(EIdent(name), args) if (bytesFastGetExpr(name, args, scope) != null):
				"int";
			case ECall(EIdent(name), _):
				callableOrSameOwnerReturnCppType(name, scope);
			case ECall(EField(receiver, method), _) if (isHelperMacrosStringShimReceiver(receiver, method)):
				"std::string";
			case ECall(EField(_, method), _) if (method == "__URLEncode" || method == "__URLDecode"):
				"std::string";
			case ECall(EField(EField(EIdent("haxe"), "SysTools"), method), _) if (method == "quoteUnixArg" || method == "quoteWinArg"):
				"std::string";
			case ECall(EField(receiver, "replace"), _) if (isStringToolsStaticReceiver(receiver)):
				"std::string";
			case ECall(EField(EIdent("__global__"), method), _):
				globalIntrinsicReturnCppType(method);
			case ECall(EField(EIdent(typeName), "create"), _) if (scopeHasClass(scope, sanitizeTypePath(typeBaseName(typeName)))):
				cppTypeHint(typeName, scope);
			case ECall(EField(EIdent("StringTools"), method), _) if (method == "fastCodeAt" || method == "unsafeCodeAt"):
				"int";
			case ECall(EField(EIdent("StringTools"), method), _) if (isStringToolsTrimMethod(method)):
				"std::string";
			case ECall(EField(ESuper, method), _):
				final baseType = scope.owner == null ? null : baseTypeName(scope.owner);
				baseType == null ? "" : classMethodCppReturnType(baseType, method, false, scope);
			case ECall(EField(receiver, method), _) if (isCppStringExpr(receiver, scope)):
				stringReceiverMethodReturnCppType(method, scope);
			case ECall(EField(receiver, "value"), args) if (args.length == 0):
				final optionalInner = cppOptionalInnerType(exprCppType(receiver, scope));
				optionalInner.length > 0 ? optionalInner : "";
			case EAnon(fieldNames, fieldValues):
				anonStruct(fieldNames, fieldValues, scope).name;
			case EField(receiver, "value") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"__hxhx_dynamic_value";
			case EField(receiver, "message") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"std::string";
			case EField(receiver, "stack") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"std::vector<std::string>";
			case ECall(EField(receiver, method), args):
				var receiverType:Null<String> = null;
				function fieldReceiverCppType():String {
					if (receiverType == null)
						receiverType = exprCppType(receiver, scope);
					return receiverType;
				}
				final knownReturn = knownFieldCallReturnCppTypeWithReceiverCppType(receiver, method, args, fieldReceiverCppType, scope);
				final primitiveAbstractReturn = knownReturn.length > 0 ? knownReturn : primitiveBackedAbstractMethodReturnCppTypeWithReceiverCppType(receiver,
					method, fieldReceiverCppType, scope);
				if (primitiveAbstractReturn.length > 0) primitiveAbstractReturn; else {
					final staticOwner = staticReceiverClassName(receiver, scope);
					if (staticOwner != null) {
						classMethodCppReturnType(staticOwner, method, true, scope);
					} else {
						final ownerType = classNameFromCppExprType(fieldReceiverCppType(), scope);
						ownerType == null ? "" : classMethodCppReturnType(ownerType, method, false, scope);
					}
				}
			case ECall(ELambda(lambdaArgs, body), args):
				lambdaCallReturnCppType(lambdaArgs, body, args, scope);
			case EBinop("=", left, _):
				assignmentExpectedCppType(left, scope);
			case EBinop(op, left, right) if (primitiveStringAbstractBinaryOpCppType(op, left, right, scope).length > 0):
				primitiveStringAbstractBinaryOpCppType(op, left, right, scope);
			case EBinop(op, left, right) if (classBackedAbstractBinaryOpCppType(op, left, right, scope).length > 0):
				classBackedAbstractBinaryOpCppType(op, left, right, scope);
			case EArrayAccess(array, _) if (isCppStringExpr(array, scope)):
				"int";
			case EArrayAccess(array, _):
				cppVectorElementType(exprCppType(array, scope));
			case EField(receiver, "expr") if (exprCppType(receiver, scope) == CppMacroExpr.CPP_TYPE):
				CppMacroExpr.CPP_TYPE;
			case EField(EIdent("Error"), _):
				"std::string";
			case EField(ESuper, field):
				final baseType = scope.owner == null ? null : baseTypeName(scope.owner);
				baseType == null ? "" : classFieldCppType(baseType, field, scope);
			case EField(receiver, field):
				final abstractPropertyType = primitiveBackedAbstractPropertyCppType(receiver, field, scope);
				if (abstractPropertyType.length > 0) abstractPropertyType; else {
					final staticOwner = staticReceiverClassName(receiver, scope);
					if (staticOwner != null)
						classFieldCppType(staticOwner, field, scope);
					else {
						final receiverType = exprCppType(receiver, scope);
						final fieldReceiverType = cppOptionalInnerType(receiverType).length > 0 ? cppOptionalInnerType(receiverType) : receiverType;
						final anonFieldType = anonStructFieldCppType(fieldReceiverType, field, scope);
						if (anonFieldType.length > 0)
							anonFieldType;
						else {
							final directFieldType = classFieldCppType(fieldReceiverType, field, scope);
							if (directFieldType.length > 0)
								directFieldType;
							else {
								final ownerType = classNameFromCppExprType(fieldReceiverType, scope);
								ownerType == null ? "" : receiverClassFieldCppType(ownerType, fieldReceiverType, field, scope);
							}
						}
					}
				}
			case EBinop(op, _, _) if (isBoolBinaryOp(op)):
				"bool";
			case EUnop("!", _):
				"bool";
			case _:
				"";
		};
	}

	static function primitiveBackedAbstractPropertyExpr(receiver:HxExpr, field:String, ?scope:CppRenderScope):Null<String> {
		final cls = primitiveBackedAbstractClassForExpr(receiver, scope);
		if (cls == null)
			return null;
		final getter = classMethodDecl(sanitizeTypePath(HxClassDecl.getName(cls)), "get_" + field, false, scope);
		if (getter == null)
			return null;
		final underlying = primitiveAbstractUnderlyingCppType(cls);
		if (underlying == null || underlying.length == 0)
			return null;
		return primitiveBackedAbstractGetterExpr(receiver, getter, underlying, scope);
	}

	static function primitiveBackedAbstractMethodCallExpr(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		if (args.length != 0)
			return null;
		var cls = primitiveBackedAbstractClassForExpr(receiver, scope);
		if (cls == null)
			cls = primitiveBackedAbstractClassForReceiverMethod(receiver, method, scope);
		if (cls == null) {
			final intLike = primitiveIntLikeAbstractMethodCallExpr(receiver, method, scope);
			return intLike;
		}
		final fn = classMethodDecl(sanitizeTypePath(HxClassDecl.getName(cls)), method, false, scope);
		if (fn == null)
			return null;
		final underlying = primitiveAbstractUnderlyingCppType(cls);
		if (underlying == null || underlying.length == 0)
			return null;
		return primitiveBackedAbstractMethodBodyExpr(receiver, fn, scope);
	}

	static function primitiveBackedAbstractMethodReturnCppType(receiver:HxExpr, method:String, ?scope:CppRenderScope):String {
		return primitiveBackedAbstractMethodReturnCppTypeWithReceiverCppType(receiver, method, function() return exprCppType(receiver, scope), scope);
	}

	static function primitiveBackedAbstractMethodReturnCppTypeWithReceiverCppType(receiver:HxExpr, method:String, receiverType:Void->String,
			?scope:CppRenderScope):String {
		var cls = primitiveBackedAbstractClassForExpr(receiver, scope);
		if (cls == null) {
			final cppType = receiverType();
			if (isCppReferenceType(cppType))
				return "";
			cls = primitiveBackedAbstractClassForReceiverCppType(cppType, method, scope);
		}
		if (cls == null)
			return "";
		final fn = classMethodDeclIn(cls, method, false);
		return fn == null ? "" : inferredFunctionReturnCppType(fn, cls, scope.classByName, lookupForScope(scope));
	}

	static function primitiveBackedAbstractClassForReceiverMethod(receiver:HxExpr, method:String, ?scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null)
			return null;
		final receiverType = exprCppType(receiver, scope);
		return primitiveBackedAbstractClassForReceiverCppType(receiverType, method, scope);
	}

	static function primitiveBackedAbstractClassForReceiverCppType(receiverType:String, method:String, ?scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null)
			return null;
		if (receiverType.length == 0)
			return null;
		var found:Null<HxClassDecl> = null;
		for (className in scope.classByName.keys()) {
			final cls = scope.classByName.get(className);
			final underlying = primitiveAbstractUnderlyingCppType(cls);
			if (underlying == null || underlying != receiverType)
				continue;
			if (classMethodDeclIn(cls, method, false) == null)
				continue;
			if (found != null)
				return null;
			found = cls;
		}
		return found;
	}

	static function primitiveIntLikeAbstractMethodCallExpr(receiver:HxExpr, method:String, ?scope:CppRenderScope):Null<String> {
		if (exprCppType(receiver, scope) != "int")
			return null;
		final self = renderExpr(receiver, scope);
		return switch (method) {
			case "toInt":
				self;
			case "incr":
				"(" + self + "++)";
			case _:
				null;
		};
	}

	static function primitiveBackedAbstractMethodBodyExpr(receiver:HxExpr, fn:HxFunctionDecl, ?scope:CppRenderScope):Null<String> {
		final self = renderExpr(receiver, scope);
		return switch (HxFunctionDecl.getBody(fn)) {
			case [SReturn(EThis, _)]:
				self;
			case [SReturn(ECast(EThis, _), _)]:
				self;
			case [SReturn(EBinop(op, EThis, rhs), _)] if (isPrimitiveAbstractInlineBinaryOp(op)):
				"("
				+ self
				+ " "
				+ op
				+ " "
				+ renderExpr(rhs, scope)
				+ ")";
			case [SExpr(EUnop("post++", EThis), _)]:
				"(" + self + "++)";
			case [SExpr(EUnop("post--", EThis), _)]:
				"(" + self + "--)";
			case [SExpr(EBinop("+=", EThis, rhs), _)]:
				self + " += " + renderExpr(rhs, scope);
			case [SExpr(EBinop("-=", EThis, rhs), _)]:
				self + " -= " + renderExpr(rhs, scope);
			case _:
				null;
		};
	}

	static function primitiveBackedAbstractToStringExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		final cls = primitiveBackedAbstractClassForExpr(expr, scope);
		if (cls == null)
			return null;
		final fn = classMethodDeclIn(cls, "toString", false);
		if (fn == null || inferredFunctionReturnCppType(fn, cls, scope.classByName, lookupForScope(scope)) != "std::string")
			return null;
		return primitiveBackedAbstractToStringBodyExpr(expr, fn, scope);
	}

	static function primitiveBackedAbstractToStringBodyExpr(receiver:HxExpr, fn:HxFunctionDecl, ?scope:CppRenderScope):Null<String> {
		final self = renderExpr(receiver, scope);
		return switch (HxFunctionDecl.getBody(fn)) {
			case [SReturn(EThis, _)]:
				"__hxhx_stringify(" + self + ")";
			case [SReturn(ECall(EField(EIdent("Std"), "string"), [EThis]), _)]:
				"__hxhx_stringify(" + self + ")";
			case [SReturn(EBinop("+", EThis, rhs), _)]:
				"(__hxhx_stringify(" + self + ") + " + stringExpr(rhs, scope) + ")";
			case [SReturn(EBinop("+", lhs, EThis), _)]:
				"(" + stringExpr(lhs, scope) + " + __hxhx_stringify(" + self + "))";
			case _:
				null;
		};
	}

	static function classBackedAbstractToStringExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		final cls = classBackedAbstractClassForExpr(expr, scope);
		if (cls == null || scope == null)
			return null;
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final fn = classMethodDecl(className, "toString", false, scope);
		if (fn == null || inferredFunctionReturnCppType(fn, cls, scope.classByName, lookupForScope(scope)) != "std::string")
			return null;
		return renderExpr(expr, scope) + "->toString()";
	}

	static function isPrimitiveAbstractInlineBinaryOp(op:String):Bool {
		return switch (op) {
			case "+" | "-" | "*" | "/" | "%":
				true;
			case _:
				false;
		};
	}

	static function primitiveBackedAbstractGetterExpr(receiver:HxExpr, getter:HxFunctionDecl, underlying:String, ?scope:CppRenderScope):Null<String> {
		final body = HxFunctionDecl.getBody(getter);
		if (body.length != 1)
			return null;
		final self = renderExpr(receiver, scope);
		final nullDefault = cppDefaultValue(underlying, scope);
		return switch (body[0]) {
			case SReturn(EThis, _):
				self;
			case SReturn(EBinop("!=", EThis, ENull), _):
				"(" + self + " != " + nullDefault + ")";
			case SReturn(EBinop("!=", ENull, EThis), _):
				"(" + nullDefault + " != " + self + ")";
			case SReturn(EBinop("==", EThis, ENull), _):
				"(" + self + " == " + nullDefault + ")";
			case SReturn(EBinop("==", ENull, EThis), _):
				"(" + nullDefault + " == " + self + ")";
			case _:
				null;
		};
	}

	static function primitiveBackedAbstractPropertyCppType(receiver:HxExpr, field:String, ?scope:CppRenderScope):String {
		final cls = primitiveBackedAbstractClassForExpr(receiver, scope);
		if (cls == null)
			return "";
		for (decl in HxClassDecl.getFields(cls))
			if (HxFieldDecl.getName(decl) == field)
				return cppTypeHint(HxFieldDecl.getTypeHint(decl), scope);
		return "";
	}

	static function primitiveBackedAbstractClassForExpr(expr:HxExpr, ?scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null)
			return null;
		final hint = exprHaxeTypeHint(expr, scope);
		if (hint.length == 0 || primitiveBackedAbstractCppTypeForTypeHint(hint, scope) == null)
			return null;
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(hint)));
		return cls != null && primitiveAbstractUnderlyingCppType(cls) != null ? cls : null;
	}

	static function recordLocalTypeHint(scope:CppRenderScope, name:String, typeHint:String):Void {
		if (scope == null || name == null || name.length == 0)
			return;
		final hint = StringTools.trim(typeHint == null ? "" : typeHint);
		if (hint.length > 0)
			scope.localTypeHints.set(name, hint);
	}

	static function exprHaxeTypeHint(expr:HxExpr, scope:CppRenderScope):String {
		return switch (expr) {
			case ECast(inner, _) | EUntyped(inner):
				exprHaxeTypeHint(inner, scope);
			case EThis:
				HxClassDecl.getName(scope.owner);
			case EIdent(name):
				final hint = scope.localTypeHints.get(sanitizeIdentifier(name));
				hint == null ? "" : hint;
			case ENew(typePath, _):
				typePath;
			case EField(receiver, field):
				final staticOwner = staticReceiverClassName(receiver, scope);
				if (staticOwner != null) {
					classFieldTypeHint(staticOwner, field, scope);
				} else {
					final ownerType = classNameFromCppExprType(exprCppType(receiver, scope), scope);
					ownerType == null ? "" : classFieldTypeHint(ownerType, field, scope);
				}
			case _:
				"";
		};
	}

	static function classFieldTypeHint(className:String, fieldName:String, scope:CppRenderScope):String {
		if (scope == null || className == null || className.length == 0)
			return "";
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return "";
		final wanted = sanitizeIdentifier(fieldName);
		for (field in HxClassDecl.getFields(cls))
			if (sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return HxFieldDecl.getTypeHint(field);
		return "";
	}

	static function currentOwnerFieldCppType(name:String, scope:CppRenderScope):String {
		if (scope == null || scope.owner == null)
			return "";
		final wanted = sanitizeIdentifier(name);
		for (field in HxClassDecl.getFields(scope.owner)) {
			if (sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return knownStdlibFieldCppType(sanitizeTypePath(HxClassDecl.getName(scope.owner)), name, HxFieldDecl.getTypeHint(field),
					HxFieldDecl.getInit(field), scope);
		}
		return "";
	}

	static function inheritedInstanceFieldCppType(name:String, scope:CppRenderScope):String {
		if (scope == null || scope.owner == null)
			return "";
		return inheritedInstanceFieldCppTypeFromClass(name, scope.owner, scope);
	}

	static function inheritedInstanceFieldCppTypeFromClass(name:String, cls:HxClassDecl, scope:CppRenderScope):String {
		final baseName = baseTypeName(cls);
		if (baseName == null || baseName.length == 0)
			return "";
		final baseCls = scope.classByName.get(baseName);
		if (baseCls == null)
			return "";
		final wanted = sanitizeIdentifier(name);
		for (field in HxClassDecl.getFields(baseCls)) {
			if (!HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return knownStdlibFieldCppType(baseName, name, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
		}
		return inheritedInstanceFieldCppTypeFromClass(name, baseCls, scope);
	}

	static function classFieldCppType(className:String, fieldName:String, scope:CppRenderScope):String {
		if (scope == null || className == null || className.length == 0)
			return "";
		final posInfosFieldType = posInfosFieldCppType(className, fieldName);
		if (posInfosFieldType.length > 0)
			return posInfosFieldType;
		final cls = scope.classByName.exists(className) ? scope.classByName.get(className) : scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return "";
		final wanted = sanitizeIdentifier(fieldName);
		for (field in HxClassDecl.getFields(cls)) {
			if (sanitizeIdentifier(HxFieldDecl.getName(field)) == wanted)
				return knownStdlibFieldCppType(className, fieldName, HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
		}
		return "";
	}

	static function receiverClassFieldCppType(className:String, receiverCppType:String, fieldName:String, scope:CppRenderScope):String {
		if (scope == null || className == null || className.length == 0)
			return "";
		final baseClassName = sanitizeTypePath(typeBaseName(className));
		final cls = scope.classByName.exists(baseClassName) ? scope.classByName.get(baseClassName) : scope.classByName.get(className);
		if (cls == null)
			return "";
		final ownerScope = renderScope(cls, {names: scope.classNames, byName: scope.classByName}, scope.returnType);
		final fieldType = classFieldCppType(baseClassName, fieldName, ownerScope);
		return instantiateGenericClassFieldType(baseClassName, receiverCppType, fieldType, ownerScope);
	}

	static function anonStructFieldCppType(typeName:String, fieldName:String, scope:CppRenderScope):String {
		if (scope == null || typeName == null || typeName.length == 0)
			return "";
		final struct = scope.anonStructs.get(typeName);
		if (struct == null)
			return encodedAnonStructFieldCppType(typeName, fieldName);
		final wanted = sanitizeIdentifier(fieldName == null ? "" : fieldName);
		for (i in 0...struct.fieldNames.length)
			if (sanitizeIdentifier(struct.fieldNames[i]) == wanted)
				return struct.fieldTypes[i];
		return "";
	}

	static function encodedAnonStructFieldCppType(typeName:String, fieldName:String):String {
		final cleanType = sanitizeTypePath(typeName == null ? "" : typeName);
		final cleanField = sanitizeIdentifier(fieldName == null ? "" : fieldName);
		final prefix = "__hxhx_anon_" + cleanField + "_";
		if (!StringTools.startsWith(cleanType, prefix))
			return "";
		final suffix = cleanType.substr(prefix.length);
		if (suffix == "int_" || suffix == "int")
			return "int";
		if (suffix == "std__string" || suffix == "std__string_")
			return "std::string";
		return "";
	}

	static function classMethodCppReturnType(className:String, methodName:String, wantStatic:Bool, scope:CppRenderScope):String {
		final preludeReturn = cppPreludeMethodReturnType(className, methodName);
		if (preludeReturn.length > 0)
			return preludeReturn;
		final fn = classMethodDecl(className, methodName, wantStatic, scope);
		if (fn == null) {
			final inherited = inheritedClassMethodCppReturnType(className, methodName, wantStatic, scope);
			if (inherited.length > 0)
				return inherited;
			final fallback = missingInterfaceMethodReturnCppType(className, methodName);
			return fallback.length > 0 ? fallback : "";
		}
		final ownerName = sanitizeTypePath(typeBaseName(className == null ? "" : className));
		final method = sanitizeIdentifier(methodName == null ? "" : methodName);
		if (isStringIteratorHelper(ownerName)
			|| ownerName == "BalancedTree"
			|| ownerName == "Template"
			|| isTypeResolverHelper(ownerName)
			|| (ownerName == "Bytes" && method == "fill"))
			return knownStdlibMethodReturnCppType(className, methodName, HxFunctionDecl.getReturnTypeHint(fn), scope);
		final owner = scope == null ? null : scope.classByName.get(ownerName);
		if (owner != null && isUtestResultAggregationHelper(fn, owner))
			return utestResultAggregationReturnType(ownerName, method);
		return owner == null ? cppReturnTypeHint(HxFunctionDecl.getReturnTypeHint(fn),
			scope) : inferredFunctionReturnCppType(fn, owner, scope.classByName, lookupForScope(scope));
	}

	static function inheritedClassMethodCppReturnType(className:String, methodName:String, wantStatic:Bool, scope:CppRenderScope):String {
		if (wantStatic || scope == null || className == null || className.length == 0)
			return "";
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return "";
		final baseName = baseTypeName(cls);
		if (baseName == null || baseName.length == 0 || baseName == className)
			return "";
		return classMethodCppReturnType(baseName, methodName, false, scope);
	}

	static function missingInterfaceMethodReturnCppType(className:String, methodName:String):String {
		return CppRuntimeSupport.missingMethodReturnType(sanitizeTypePath(typeBaseName(className == null ? "" : className)),
			sanitizeIdentifier(methodName == null ? "" : methodName));
	}

	static function classMethodDecl(className:String, methodName:String, wantStatic:Bool, scope:CppRenderScope):Null<HxFunctionDecl> {
		if (scope == null || className == null || className.length == 0)
			return null;
		final cls = scope.classByName.get(className);
		if (cls == null)
			return null;
		return classMethodDeclIn(cls, methodName, wantStatic);
	}

	static function classMethodDeclIn(cls:HxClassDecl, methodName:String, wantStatic:Bool):Null<HxFunctionDecl> {
		final cleanMethodName = sanitizeIdentifier(methodName);
		for (fn in HxClassDecl.getFunctions(cls))
			if ((HxFunctionDecl.getName(fn) == methodName || sanitizeIdentifier(HxFunctionDecl.getName(fn)) == cleanMethodName)
				&& HxFunctionDecl.getName(fn) != "new"
				&& HxFunctionDecl.getIsStatic(fn) == wantStatic)
				return fn;
		return null;
	}

	static function ownerMethodDeclIn(cls:HxClassDecl, methodName:String):Null<HxFunctionDecl> {
		final cleanMethodName = sanitizeIdentifier(methodName);
		for (fn in HxClassDecl.getFunctions(cls))
			if ((HxFunctionDecl.getName(fn) == methodName || sanitizeIdentifier(HxFunctionDecl.getName(fn)) == cleanMethodName)
				&& HxFunctionDecl.getName(fn) != "new")
				return fn;
		return null;
	}

	static function currentOwnerMethodCppReturnType(methodName:String, scope:CppRenderScope):String {
		final owner = currentOrInheritedOwnerMethodOwner(methodName, scope);
		final fn = owner == null ? null : ownerMethodDeclIn(owner, methodName);
		return fn == null ? "" : inferredFunctionReturnCppType(fn, owner, scope.classByName, lookupForScope(scope));
	}

	static function currentOwnerMethod(methodName:String, scope:CppRenderScope):Null<HxFunctionDecl> {
		if (scope == null || scope.owner == null)
			return null;
		final ownerMethod = ownerMethodDeclIn(scope.owner, methodName);
		if (ownerMethod != null)
			return ownerMethod;
		final className = sanitizeTypePath(HxClassDecl.getName(scope.owner));
		final cls = scope.classByName.get(className);
		if (cls == null)
			return null;
		return ownerMethodDeclIn(cls, methodName);
	}

	static function currentOrInheritedOwnerMethod(methodName:String, scope:CppRenderScope):Null<HxFunctionDecl> {
		final owner = currentOrInheritedOwnerMethodOwner(methodName, scope);
		return owner == null ? null : ownerMethodDeclIn(owner, methodName);
	}

	static function currentOrInheritedOwnerMethodOwner(methodName:String, scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null || scope.owner == null)
			return null;
		var current = sanitizeTypePath(HxClassDecl.getName(scope.owner));
		final seen = new haxe.ds.StringMap<Bool>();
		while (current.length > 0 && !seen.exists(current)) {
			seen.set(current, true);
			final cls = scope.classByName.exists(current) ? scope.classByName.get(current) : (current == sanitizeTypePath(HxClassDecl.getName(scope.owner)) ? scope.owner : null);
			if (cls == null)
				return null;
			if (ownerMethodDeclIn(cls, methodName) != null)
				return cls;
			final next = baseTypeName(cls);
			current = next == null ? "" : sanitizeTypePath(typeBaseName(next));
		}
		return null;
	}

	static function callableOrSameOwnerReturnCppType(name:String, ?scope:CppRenderScope):String {
		if (scope == null)
			return "";
		final localName = sanitizeIdentifier(name);
		final localType = scope.localTypes.get(localName);
		if (localType != null && localType.length > 0)
			return cppFunctionReturnTypeFromCppType(localType);
		return currentOwnerMethodCppReturnType(name, scope);
	}

	static function staticReceiverClassName(receiver:HxExpr, ?scope:CppRenderScope):Null<String> {
		final typePath = staticReceiverTypePath(receiver);
		if (typePath == null)
			return null;
		final clean = sanitizeTypePath(typeBaseName(typePath));
		if (scopeHasClass(scope, clean) && (!isCppCoreExternClass(clean) || isCppPreludeStaticClass(clean)))
			return clean;
		return isKnownCppStaticSupportReceiver(clean) ? clean : null;
	}

	static function isKnownCppStaticSupportReceiver(className:String):Bool {
		return switch (sanitizeTypePath(typeBaseName(className == null ? "" : className))) {
			case "Bytes" | "Md5":
				true;
			case _:
				false;
		};
	}

	static function isStringToolsStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "StringTools";
	}

	static function isStringStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "String";
	}

	static function isReflectStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "Reflect";
	}

	static function isLambdaStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "Lambda";
	}

	static function isStdStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "Std";
	}

	static function isCppConstPointerStaticReceiver(receiver:HxExpr):Bool {
		final typePath = staticReceiverTypePath(receiver);
		return typePath != null && sanitizeTypePath(typeBaseName(typePath)) == "ConstPointer";
	}

	static function isStringToolsIntrinsicCall(receiver:HxExpr, method:String):Bool {
		if (!isStringToolsStaticReceiver(receiver))
			return false;
		return method == "replace" || method == "fastCodeAt" || method == "unsafeCodeAt" || isStringToolsTrimMethod(method);
	}

	static function staticReceiverTypePath(receiver:HxExpr):Null<String> {
		return switch (receiver) {
			case EIdent(typeName):
				typeName;
			case EField(obj, field): final base = staticReceiverTypePath(obj); base == null || base.length == 0 ? null : base + "." + field;
			case _:
				null;
		};
	}

	static function staticFieldExpr(receiver:HxExpr, field:String, ?scope:CppRenderScope):Null<String> {
		final owner = staticReceiverClassName(receiver, scope);
		if (owner == null || classFieldCppType(owner, field, scope).length == 0)
			return null;
		return owner + "::" + sanitizeIdentifier(field);
	}

	static function isCppCoreExternClass(name:String):Bool {
		final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
		return clean == "Math" || clean == "NativeArray" || clean == "EnumValue" || clean == "Http" || clean == "Pointer" || clean == "ConstPointer"
			|| clean == "RawConstPointer" || clean == "Reference" || clean == "Star" || clean == "AutoCast" || clean == "ArrayBase"
			|| isCppPreludeStaticClass(clean) || isBytesDataTypeName(clean) || isCppPrimitiveIntrinsicClass(clean);
	}

	static function isAnySupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) == "Any";
	}

	static function isNativeStackTraceSupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) == "NativeStackTrace";
	}

	static function isCppPreludeStaticClass(name:String):Bool {
		return switch (sanitizeTypePath(typeBaseName(name == null ? "" : name))) {
			case "Timer" | "Lock" | "Mutex" | "MainEvent" | "MainLoop" | "EntryPoint":
				true;
			case _:
				false;
		}
	}

	static function isBytesDataTypeName(name:String):Bool {
		return sanitizeTypePath(typeBaseName(name == null ? "" : name)) == "BytesData";
	}

	static function isCppPrimitiveIntrinsicClass(name:String):Bool {
		final clean = sanitizeTypePath(typeBaseName(name == null ? "" : name));
		return clean == "Int64" || clean == "__Int64" || clean == "___Int64";
	}

	static function isCppNativeArrayReceiver(expr:HxExpr):Bool {
		return switch (expr) {
			case EIdent("NativeArray"):
				true;
			case EField(EIdent("cpp"), "NativeArray"):
				true;
			case _:
				false;
		};
	}

	static function isInt64StaticReceiver(expr:HxExpr):Bool {
		return switch (expr) {
			case EIdent("Int64"):
				true;
			case EField(EIdent("haxe"), "Int64"):
				true;
			case _:
				false;
		};
	}

	static function isInt64HelperReceiver(expr:HxExpr):Bool {
		return switch (expr) {
			case EIdent("Int64Helper"):
				true;
			case EField(EIdent("haxe"), "Int64Helper"):
				true;
			case _:
				false;
		};
	}

	static function scopeHasClass(?scope:CppRenderScope, className:String):Bool {
		return scope != null && className != null && scope.classNames.exists(className);
	}

	static function cppLocalTypeHint(typeHint:String, init:Null<HxExpr>, ?scope:CppRenderScope):String {
		final explicit = StringTools.trim(typeHint == null ? "" : typeHint);
		if (explicit.length > 0)
			return cppTypeHint(explicit, scope);
		return init == null ? "" : inferExprCppType(init, scope);
	}

	static function cppLocalDeclaredType(name:String, typeHint:String, init:Null<HxExpr>, ?scope:CppRenderScope, ?declaredLocalName:String):String {
		final explicit = StringTools.trim(typeHint == null ? "" : typeHint);
		final local = sanitizeIdentifier(name);
		final overrideType = if (scope == null) null; else if (declaredLocalName != null
			&& scope.localTypeOverrides.exists(declaredLocalName)) scope.localTypeOverrides.get(declaredLocalName); else scope.localTypeOverrides.get(local);
		if (explicit.length > 0 && !isDynamicLikeTypeHint(explicit)) {
			final hinted = cppLocalTypeHint(typeHint, init, scope);
			return overrideType != null && isCppFunctionType(hinted) && isCppFunctionType(overrideType) ? overrideType : hinted;
		}
		return overrideType != null && overrideType.length > 0 ? overrideType : cppLocalTypeHint(typeHint, init, scope);
	}

	static function isUnhintedNoInitLocal(typeHint:String, init:Null<HxExpr>):Bool {
		return init == null && StringTools.trim(typeHint == null ? "" : typeHint).length == 0;
	}

	static function isUnhintedEmptyArray(typeHint:String, init:Null<HxExpr>):Bool {
		if (StringTools.trim(typeHint == null ? "" : typeHint).length > 0)
			return false;
		return switch (init) {
			case EArrayDecl(values):
				values.length == 0;
			case _:
				false;
		};
	}

	static function isUnhintedNullLocal(typeHint:String, init:Null<HxExpr>):Bool {
		if (StringTools.trim(typeHint == null ? "" : typeHint).length > 0)
			return false;
		return switch (init) {
			case ENull:
				true;
			case _:
				false;
		};
	}

	static function inferExprCppType(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case EIdent(_):
				exprCppType(expr, scope);
			case ECall(EField(EIdent("Type"), method), args):
				typeIntrinsicReturnCppType(method, args);
			case ECall(EField(receiver, "fromCharCode"), args) if (isStringStaticReceiver(receiver) && args.length == 1):
				"std::string";
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				"std::string";
			case ECall(EField(receiver, "parseInt"), args) if (isStdStaticReceiver(receiver) && args.length == 1):
				"std::optional<int>";
			case ECall(EField(receiver, "downcast"), args) if (isStdStaticReceiver(receiver) && args.length == 2):
				"std::string";
			case ECall(EField(receiver, "isOfType"), args) if (isStdStaticReceiver(receiver) && args.length == 2):
				"bool";
			case ENew(typePath, _) if (isStdArrayTypePath(typePath)):
				isArrayLikeTypeHint(typePath) ? cppTypeHint(typePath, scope) : stdArrayDefaultVectorType(scope);
			case ENew(typePath, _):
				cppNewExprType(typePath, scope);
			case ECall(EField(EIdent("NativeArray"), "create"), _):
				nativeArrayVectorType(scope);
			case ECall(EField(receiver, "create"), _) if (isCppNativeArrayReceiver(receiver)):
				nativeArrayVectorType(scope);
			case ECall(EField(receiver, method), args) if (int64StaticOrHelperCallReturnCppType(receiver, method, args.length).length > 0):
				int64StaticOrHelperCallReturnCppType(receiver, method, args.length);
			case ECall(EField(receiver, method), args) if (int64InstanceOrExtensionCallReturnCppType(receiver, method, args, scope).length > 0):
				int64InstanceOrExtensionCallReturnCppType(receiver, method, args, scope);
			case ECall(EIdent("__hxhx_int_literal"), [_, EString(_)]):
				"long long";
			case ECall(EIdent(name), args)
				if (int64ImportedStaticCallReturnCppType(name, args.length).length > 0
					&& currentOrInheritedOwnerMethodOwner(name, scope) == null):
				int64ImportedStaticCallReturnCppType(name, args.length);
			case ECall(EField(EIdent("Math"), method), _):
				mathReturnCppType(method);
			case ECall(EField(receiver, "compare"), _) if (isReflectStaticReceiver(receiver)):
				"int";
			case ECall(EField(receiver, "field"), args) if (isReflectStaticReceiver(receiver) && args.length == 2):
				"std::any";
			case ECall(EField(receiver, "callMethod"), args) if (isReflectStaticReceiver(receiver) && args.length == 3):
				"std::any";
			case ECall(EField(receiver, "isFunction"), args) if (isReflectStaticReceiver(receiver) && args.length == 1):
				"bool";
			case ECall(EField(EArrayDecl(elements), "toString"), args) if (args.length == 0 && isMapLiteralElements(elements)):
				"std::string";
			case ECall(ECall(loadCallee, loadArgs), _) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				"std::any";
			case ECall(loadCallee, loadArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				"std::any";
			case ECall(EIdent("__hxhx_optional_lambda"), args) if (args.length >= 1):
				inferExprCppType(args[0], scope);
			case ECall(EField(receiver, "callMacroApi"), args) if (isContextStaticReceiver(receiver) && args.length >= 1):
				"std::any";
			case ECall(EIdent("callMacroApi"), args) if (scopeOwnerIsContext(scope) && args.length >= 1):
				"std::any";
			case ECall(EField(receiver, "array"), args) if (isLambdaStaticReceiver(receiver) && args.length == 1):
				lambdaArrayResultCppType(args[0], scope);
			case ECall(EField(receiver, "isEnumValue"), _) if (isReflectStaticReceiver(receiver)):
				"bool";
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				inferExprCppType(args[2], scope);
			case ECall(EIdent("__hxhx_parenthesized"), args) if (args.length == 1):
				inferExprCppType(args[0], scope);
			case ECall(EEnumValue(_), args) if (args != null && args.length > 0):
				CppMacroExpr.CPP_TYPE;
			case ECall(EIdent(name), _) if (sameOwnerCallReturnsErasedDynamicValue(name, scope)):
				"std::any";
			case ECall(EIdent(name), args) if (bytesFastGetExpr(name, args, scope) != null):
				"int";
			case ECall(EIdent(name), _):
				callableOrSameOwnerReturnCppType(name, scope);
			case ECall(EField(receiver, method), _) if (isHelperMacrosStringShimReceiver(receiver, method)):
				"std::string";
			case ECall(EField(_, method), _) if (method == "__URLEncode" || method == "__URLDecode"):
				"std::string";
			case ECall(EField(EField(EIdent("haxe"), "SysTools"), method), _) if (method == "quoteUnixArg" || method == "quoteWinArg"):
				"std::string";
			case ECall(EField(EIdent("__global__"), method), _):
				globalIntrinsicReturnCppType(method);
			case ECall(EField(EIdent("StringTools"), method), _) if (isStringToolsTrimMethod(method)):
				"std::string";
			case ECall(EField(receiver, method), _) if (isCppStringExpr(receiver, scope)):
				stringReceiverMethodReturnCppType(method, scope);
			case EField(receiver, "value") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"__hxhx_dynamic_value";
			case EField(receiver, "message") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"std::string";
			case EField(receiver, "stack") if (isCppExceptionValueType(exprCppType(receiver, scope))):
				"std::vector<std::string>";
			case ECall(EField(_, "flatten"), [ECall(EField(_, "map"), [_, mapper])]):
				cppFunctionReturnTypeFromCppType(exprCppType(mapper, scope));
			case ECall(EField(EIdent(typeName), "create"), _) if (scopeHasClass(scope, sanitizeTypePath(typeBaseName(typeName)))):
				cppTypeHint(typeName, scope);
			case ECall(EField(receiver, method), args):
				var receiverType:Null<String> = null;
				function fieldReceiverCppType():String {
					if (receiverType == null)
						receiverType = exprCppType(receiver, scope);
					return receiverType;
				}
				final timingEnabled = traceCppScopeStmtTimingEnabled(scope);
				function traceFieldInferPhase(phase:String, start:Float, typeName:String):String {
					if (timingEnabled)
						traceCppScopeStmtTimingPhase(scope,
							"phase=field_infer_"
							+ phase
							+ " seconds="
							+ Std.string(Sys.time() - start)
							+ " method="
							+ sanitizeIdentifier(method)
							+ " receiver="
							+ exprKind(receiver)
							+ " type="
							+ traceCppSnippet(typeName));
					return typeName;
				}
				final knownStart = timingEnabled ? Sys.time() : 0.0;
				final knownReturn = knownFieldCallReturnCppTypeWithReceiverCppType(receiver, method, args, fieldReceiverCppType, scope);
				traceFieldInferPhase("known", knownStart, knownReturn);
				final primitiveStart = timingEnabled ? Sys.time() : 0.0;
				final primitiveAbstractReturn = knownReturn.length > 0 ? knownReturn : primitiveBackedAbstractMethodReturnCppTypeWithReceiverCppType(receiver,
					method, fieldReceiverCppType, scope);
				traceFieldInferPhase("primitive", primitiveStart, primitiveAbstractReturn);
				if (primitiveAbstractReturn.length > 0) primitiveAbstractReturn; else {
					final staticStart = timingEnabled ? Sys.time() : 0.0;
					final staticOwner = staticReceiverClassName(receiver, scope);
					traceFieldInferPhase("static_owner", staticStart, staticOwner == null ? "" : staticOwner);
					if (staticOwner != null) {
						final returnStart = timingEnabled ? Sys.time() : 0.0;
						traceFieldInferPhase("static_return", returnStart, classMethodCppReturnType(staticOwner, method, true, scope));
					} else {
						final receiverTypeStart = timingEnabled ? Sys.time() : 0.0;
						final resolvedReceiverType = fieldReceiverCppType();
						traceFieldInferPhase("receiver_type", receiverTypeStart, resolvedReceiverType);
						final ownerStart = timingEnabled ? Sys.time() : 0.0;
						final ownerType = classNameFromCppExprType(resolvedReceiverType, scope);
						traceFieldInferPhase("owner_type", ownerStart, ownerType == null ? "" : ownerType);
						final returnStart = timingEnabled ? Sys.time() : 0.0;
						ownerType == null ? "" : traceFieldInferPhase("instance_return", returnStart,
							classMethodCppReturnType(ownerType, method, false, scope));
					}
				}
			case ECall(ELambda(lambdaArgs, body), args):
				lambdaCallReturnCppType(lambdaArgs, body, args, scope);
			case EBinop("=", left, _):
				assignmentExpectedCppType(left, scope);
			case EBinop(op, left, right) if (primitiveStringAbstractBinaryOpCppType(op, left, right, scope).length > 0):
				primitiveStringAbstractBinaryOpCppType(op, left, right, scope);
			case EBinop(op, left, right) if (classBackedAbstractBinaryOpCppType(op, left, right, scope).length > 0):
				classBackedAbstractBinaryOpCppType(op, left, right, scope);
			case EString(_) | EEnumValue(_) | EMacroType(_):
				"std::string";
			case EField(EIdent("Error"), _):
				"std::string";
			case EField(_, _):
				exprCppType(expr, scope);
			case EMacroExpr(_, _):
				CppMacroExpr.CPP_TYPE;
			case EInt(_):
				"int";
			case EFloat(_):
				"double";
			case EBool(_):
				"bool";
			case EArrayDecl(elements):
				"std::vector<" + arrayElementType(elements, scope) + ">";
			case EArrayComprehension(name, iterable, _, yieldExpr):
				"std::vector<" + arrayComprehensionElementType(name, iterable, yieldExpr, scope) + ">";
			case EArrayAccess(array, _) if (isCppStringExpr(array, scope)):
				"int";
			case EArrayAccess(array, _):
				cppVectorElementType(exprCppType(array, scope));
			case EAnon(fieldNames, fieldValues):
				anonStruct(fieldNames, fieldValues, scope).name;
			case EUnop("-", inner):
				inferExprCppType(inner, scope);
			case EUnop("post++", inner) | EUnop("post--", inner):
				inferExprCppType(inner, scope);
			case EUnop("!", _):
				"bool";
			case EBinop(op, _, _) if (isBoolBinaryOp(op)):
				"bool";
			case EBinop(op, left, right) if (isArithmeticBinaryOp(op) && (isCppDoubleExpr(left, scope) || isCppDoubleExpr(right, scope))):
				"double";
			case EBinop("+", left, right) if (isCppStringExpr(left, scope) || isCppStringExpr(right, scope)):
				"std::string";
			case EBinop(op, left, right) if (isIntegerArithmeticBinaryOp(op)
				&& (isCppInt64Expr(left, scope) || isCppInt64Expr(right, scope))):
				"long long";
			case EBinop(op, _, _) if (isIntegerArithmeticBinaryOp(op)):
				"int";
			case EBinop("+", left, right) if (isCppIntExpr(left, scope) || isCppIntExpr(right, scope)):
				"int";
			case ETernary(_, thenExpr, elseExpr):
				final thenType = inferExprCppType(thenExpr, scope);
				final elseType = inferExprCppType(elseExpr, scope);
				if (thenType.length > 0 && thenType == elseType) thenType; else "";
			case ECast(inner, _) | EUntyped(inner):
				inferExprCppType(inner, scope);
			case _:
				"";
		};
	}

	static function stringMethodReturnCppType(method:String):String {
		return switch (method) {
			case "split":
				"std::vector<std::string>";
			case "lastIndexOf":
				"int";
			case "charCodeAt" | "cca":
				"int";
			case "charAt" | "substring" | "substr" | "replace" | "toUpperCase" | "toLowerCase":
				"std::string";
			case _:
				"";
		};
	}

	static function stringReceiverMethodReturnCppType(method:String, ?scope:CppRenderScope):String {
		final nativeReturn = stringMethodReturnCppType(method);
		if (nativeReturn.length > 0)
			return nativeReturn;
		return staticStringExtensionOwner(method, scope) == null ? "" : "std::string";
	}

	static function iteratorCppTypeForVector(vectorType:String):String {
		final elementType = cppVectorElementType(vectorType);
		return "std::shared_ptr<__hxhx_iterator<" + (elementType.length == 0 ? "std::string" : elementType) + ">>";
	}

	static function knownFieldCallReturnCppType(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		return knownFieldCallReturnCppTypeWithReceiverCppType(receiver, method, args, function() return exprCppType(receiver, scope), scope);
	}

	static function knownFieldCallReturnCppTypeWithReceiverCppType(receiver:HxExpr, method:String, args:Array<HxExpr>, receiverCppType:Void->String,
			?scope:CppRenderScope):String {
		final arity = args == null ? 0 : args.length;
		if (isReflectStaticReceiver(receiver)) {
			switch (method) {
				case "getProperty" if (arity == 2):
					return exprCppType(args[0], scope) == "std::any" ? "std::any" : "";
				case "hasField" if (arity == 2):
					return exprCppType(args[0], scope) == "std::any" ? "bool" : "";
				case _:
			}
		}
		return switch (method) {
			case "get" if (arity == 1):
				final receiverType = receiverCppType();
				final valueType = mapValueCppType(receiverType);
				valueType.length > 0 ? "std::optional<" + valueType + ">" : "";
			case "keys" if (arity == 0):
				final receiverType = receiverCppType();
				final keyType = mapKeyCppType(receiverType);
				keyType.length > 0 ? "std::shared_ptr<__hxhx_iterator<" + keyType + ">>" : "";
			case "iterator" if (arity == 0):
				final receiverType = receiverCppType();
				final mapValueType = mapValueCppType(receiverType);
				if (mapValueType.length > 0) "std::shared_ptr<__hxhx_iterator<"
					+ mapValueType
					+ ">>"; else if (isCppVectorType(receiverType)) iteratorCppTypeForVector(receiverType); else "";
			case "map" | "join" | "copy" | "pop":
				final receiverType = receiverCppType();
				if (!isCppVectorType(receiverType)) ""; else switch (method) {
					case "map":
						"std::vector<std::string>";
					case "join":
						"std::string";
					case "copy":
						receiverType;
					case "pop":
						cppVectorElementType(receiverType);
					case _:
						"";
				}
			case "next":
				final iteratorElement = cppIteratorElementType(receiverCppType());
				iteratorElement.length > 0 ? iteratorElement : "";
			case "hasNext":
				cppIteratorElementType(receiverCppType()).length > 0 ? "bool" : "";
			case _:
				"";
		};
	}

	static function renderUnsupportedNumericLiteral(raw:String):Null<String> {
		if (raw == null || raw.length == 0)
			return null;
		var i = 0;
		if (raw.charCodeAt(0) == "-".code) {
			if (raw.length == 1)
				return null;
			i = 1;
		}
		while (i < raw.length) {
			final c = raw.charCodeAt(i);
			if (c < "0".code || c > "9".code)
				return null;
			i++;
		}
		return raw;
	}

	static function renderTryCatchRaw(raw:String):String {
		final exceptionStackMessage = parseExceptionStackTryRaw(raw);
		if (exceptionStackMessage != null) {
			return "([&]() { try { throw std::runtime_error(std::string("
				+ quoteString(exceptionStackMessage)
				+ ")); return CallStack(); } catch (...) { return CallStack(); } })()";
		}
		final exceptionValueMessage = parseExceptionCatchValueTryRaw(raw);
		if (exceptionValueMessage != null) {
			return "([&]() { try { throw std::runtime_error(std::string("
				+ quoteString(exceptionValueMessage)
				+ ")); return std::string(); } catch (const std::exception& e) { return std::string(e.what()); } catch (...) { return std::string(); } })()";
		}
		final simpleCallCatchValue = parseSimpleCallCatchValueRaw(raw);
		if (simpleCallCatchValue != null) {
			return "([&]() { try { return "
				+ simpleCallCatchValue
				+ "(); } catch (const std::exception& e) { return std::string(e.what()); } catch (...) { return std::string(); } })()";
		}
		final joinCatch = parseArrayJoinCatchStringRaw(raw);
		if (joinCatch != null) {
			return "([&]() { try { return __hxhx_join(" + joinCatch.receiver + ", " + quoteString(joinCatch.separator)
				+ "); } catch (...) { return std::string(" + quoteString(joinCatch.fallback) + "); } })()";
		}
		final fieldReadCatch = parseFieldReadCatchStringRaw(raw);
		if (fieldReadCatch != null) {
			return "([&]() { try { return " + fieldReadCatch.receiver + "." + fieldReadCatch.field + "; } catch (...) { return std::string("
				+ quoteString(fieldReadCatch.fallback) + "); } })()";
		}
		final stringProbe = parseTryStringProbeRaw(raw);
		if (stringProbe != null) {
			return "([&]() { try { return "
				+ stringProbe.expr
				+ "; } catch (...) { return std::string("
				+ quoteString(stringProbe.fallback)
				+ "); } })()";
		}
		final typeofSafetyProbe = parseTypeofSafetyProbeRaw(raw);
		if (typeofSafetyProbe != null) {
			return "([&]() { try { (void)__hxhx_type_name(" + typeofSafetyProbe[0] + "); return std::string(" + quoteString(typeofSafetyProbe[1])
				+ "); } catch (...) { return std::string(" + quoteString(typeofSafetyProbe[2]) + "); } })()";
		}
		final macroErrorProbe = parseTypeofMacroErrorProbeRaw(raw);
		if (macroErrorProbe != null) {
			return "([&]() { try { (void)__hxhx_type_name("
				+ macroErrorProbe
				+ "); return std::string(); } catch (const std::exception& e) { return std::string(e.what()); } catch (...) { return std::string(); } })()";
		}
		final exceptionMessageProbe = parseTypeofExceptionMessageProbeRaw(raw);
		if (exceptionMessageProbe != null) {
			return "([&]() { try { (void)__hxhx_type_name("
				+ exceptionMessageProbe[0]
				+ "); return std::string("
				+ quoteString(exceptionMessageProbe[1])
				+ "); } catch (const std::exception& e) { return std::string(e.what()); } catch (...) { return std::string(); } })()";
		}
		final fileContentContextErrorPath = parseFileContentContextErrorTryRaw(raw);
		if (fileContentContextErrorPath != null) {
			final readExpr = "__hxhx_read_file(" + fileContentContextErrorPath + ")";
			final stdExceptionCatch = "catch (const std::exception& e) { throw std::runtime_error(std::string(e.what())); }";
			final unknownCatch = "catch (...) { throw std::runtime_error(std::string(" + quoteString("Unable to read file") + ")); }";
			return "([&]() { try { return " + readExpr + "; } " + stdExceptionCatch + " " + unknownCatch + " })()";
		}
		final platformMinPath = parseHxcppAndroidPlatformMinTryRaw(raw);
		if (platformMinPath != null) {
			return "([&]() { try { return __hxhx_json_min_field_from_file("
				+ platformMinPath
				+ "); } catch (...) { std::cout << "
				+ quoteString("Unable to determine minimum supported Android platform")
				+ " << std::endl; return 0; } })()";
		}
		final opaqueEnumSwitchProbe = renderOpaqueEnumSwitchProbeRaw(raw);
		if (opaqueEnumSwitchProbe != null)
			return opaqueEnumSwitchProbe;
		final opaqueStringMap = renderOpaqueStringMapRaw(raw);
		if (opaqueStringMap != null)
			return opaqueStringMap;
		final opaqueObject = renderOpaqueObjectLocalRaw(raw);
		if (opaqueObject != null)
			return opaqueObject;
		final opaqueTypedLocalRef = renderOpaqueTypedLocalRefRaw(raw);
		if (opaqueTypedLocalRef != null)
			return opaqueTypedLocalRef;
		final opaqueTypedLocalInit = renderOpaqueTypedLocalInitRaw(raw);
		if (opaqueTypedLocalInit != null)
			return opaqueTypedLocalInit;
		throw "C++ source backend MVP unsupported expression: ETryCatchRaw(" + summarizeRaw(raw) + ")";
	}

	static function parseExceptionStackTryRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{throw(.+);\}catch\(e:Exception\)\{e\.stack;\}$/;
		if (!pattern.match(compact))
			return null;
		final quoted = ~/"([^"]*)"/;
		return quoted.match(pattern.matched(1)) ? quoted.matched(1) : "";
	}

	static function parseExceptionCatchValueTryRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{throw(.+);\}catch\(e\)\{e;\}$/;
		if (!pattern.match(compact))
			return null;
		final quoted = ~/"([^"]*)"/;
		return quoted.match(pattern.matched(1)) ? quoted.matched(1) : "";
	}

	static function parseSimpleCallCatchValueRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\(\);\}catch\(e(:[^)]*)?\)\{e;\}$/;
		return pattern.match(compact) ? sanitizeIdentifier(pattern.matched(1)) : null;
	}

	static function parseArrayJoinCatchStringRaw(raw:String):Null<{receiver:String, separator:String, fallback:String}> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\.join\("([^"]*)"\);\}catch\(e(:[^)]*)?\)\{"([^"]*)";\}$/;
		return pattern.match(compact) ? {
			receiver: sanitizeIdentifier(pattern.matched(1)),
			separator: pattern.matched(2),
			fallback: pattern.matched(4)
		} : null;
	}

	static function parseFieldReadCatchStringRaw(raw:String):Null<CppFieldReadCatchString> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*);\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		return pattern.match(compact) ? {
			receiver: sanitizeIdentifier(pattern.matched(1)),
			field: sanitizeIdentifier(pattern.matched(2)),
			fallback: pattern.matched(4)
		} : null;
	}

	static function parseTryStringProbeRaw(raw:String):Null<CppTryStringProbe> {
		final compact = compactRawText(raw);
		final classNamePattern = ~/^try\{Type\.getClassName\(([A-Za-z_][A-Za-z0-9_]*)\);\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		if (classNamePattern.match(compact))
			return {
				expr: "__hxhx_type_name(" + sanitizeIdentifier(classNamePattern.matched(1)) + ")",
				fallback: classNamePattern.matched(3)
			};
		final enumNamePattern = ~/^try\{Type\.getEnumName\(([A-Za-z_][A-Za-z0-9_]*)\);\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		if (enumNamePattern.match(compact))
			return {
				expr: "__hxhx_type_name(" + sanitizeIdentifier(enumNamePattern.matched(1)) + ")",
				fallback: enumNamePattern.matched(3)
			};
		final typeofPattern = ~/^try\{Std\.string\(Type\.typeof\(([A-Za-z_][A-Za-z0-9_]*)\)\);\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		if (typeofPattern.match(compact))
			return {
				expr: "__hxhx_type_name(" + sanitizeIdentifier(typeofPattern.matched(1)) + ")",
				fallback: typeofPattern.matched(3)
			};
		final stdStringPattern = ~/^try\{Std\.string\(([A-Za-z_][A-Za-z0-9_]*)\);\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		if (stdStringPattern.match(compact))
			return {
				expr: "std::string(" + sanitizeIdentifier(stdStringPattern.matched(1)) + ")",
				fallback: stdStringPattern.matched(3)
			};
		return null;
	}

	static function parseTypeofSafetyProbeRaw(raw:String):Null<Array<String>> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{typeof\(([A-Za-z_][A-Za-z0-9_]*)\);"([^"]*)";\}catch\(e(:[^)]*)?\)\{"([^"]*)";?\}$/;
		return pattern.match(compact) ? [sanitizeIdentifier(pattern.matched(1)), pattern.matched(2), pattern.matched(4)] : null;
	}

	static function parseTypeofMacroErrorProbeRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{typeof\(([A-Za-z_][A-Za-z0-9_]*)\);null;\}catch\(e:haxe\.macro\.Expr\.Error\)\{var[A-Za-z_][A-Za-z0-9_]*=e\.message;if\(e\.childErrors!=null\)for\(cine\.childErrors\)[A-Za-z_][A-Za-z0-9_]*\+=""\+c\.message;[A-Za-z_][A-Za-z0-9_]*;\}$/;
		return pattern.match(compact) ? sanitizeIdentifier(pattern.matched(1)) : null;
	}

	static function parseTypeofExceptionMessageProbeRaw(raw:String):Null<Array<String>> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{typeof\(([A-Za-z_][A-Za-z0-9_]*)\);"([^"]*)";\}catch\(e:haxe\.Exception\)\{Std\.string\(e\.message\);\}$/;
		return pattern.match(compact) ? [sanitizeIdentifier(pattern.matched(1)), pattern.matched(2)] : null;
	}

	static function parseFileContentContextErrorTryRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{sys\.io\.File\.getContent\(Context\.resolvePath\(([A-Za-z_][A-Za-z0-9_]*)\)\);\}catch\(e(:[^)]*)?\)\{Context\.error\(Std\.string\(e\),Context\.currentPos\(\)\);\}$/;
		return pattern.match(compact) ? sanitizeIdentifier(pattern.matched(1)) : null;
	}

	static function parseHxcppAndroidPlatformMinTryRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^try\{haxe\.Json\.parse\(sys\.io\.File\.getContent\(([A-Za-z_][A-Za-z0-9_]*)\)\)\.min;\}catch\(e(:[^)]*)?\)\{Log\.warn\("UnabletodetermineminimumsupportedAndroidplatform:"\+e\.toString\(\)\);null;\}$/;
		return pattern.match(compact) ? sanitizeIdentifier(pattern.matched(1)) : null;
	}

	static function renderOpaqueEnumSwitchProbeRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final prefix = "opaque_block_expr:{switch(";
		if (!StringTools.startsWith(compact, prefix))
			return null;
		final separator = "){case";
		final separatorIndex = compact.indexOf(separator, prefix.length);
		if (separatorIndex <= prefix.length)
			return null;
		final value = compact.substr(prefix.length, separatorIndex - prefix.length);
		if (!isSimpleIdentifierText(value))
			return null;
		var enumEnd = separatorIndex + separator.length;
		while (enumEnd < compact.length && isIdentifierCharAt(compact, enumEnd, enumEnd > separatorIndex + separator.length))
			enumEnd++;
		final enumCase = compact.substring(separatorIndex + separator.length, enumEnd);
		if (enumCase.length == 0)
			return null;
		final trailing = compact.substr(enumEnd);
		if (trailing.length > 0 && trailing.charAt(0) != ")" && trailing.charAt(0) != ":" && trailing.charAt(0) != "}")
			return null;
		return "([&]() { return std::string(" + value + ") == std::string(" + quoteString(enumCase) + "); })()";
	}

	static function renderOpaqueObjectLocalRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^opaque_block_expr:\{var[A-Za-z_][A-Za-z0-9_]*:\{[^}]+\}=\{([^}]+)\};\}$/;
		if (!pattern.match(compact))
			return null;
		final declarations = [];
		final values = [];
		final fieldPattern = ~/^([A-Za-z_][A-Za-z0-9_]*):("[^"]*"|-?[0-9.]+)$/;
		for (fieldInit in pattern.matched(1).split(",")) {
			if (!fieldPattern.match(fieldInit))
				return null;
			final field = sanitizeIdentifier(fieldPattern.matched(1));
			final value = fieldPattern.matched(2);
			final fieldType = StringTools.startsWith(value, "\"") ? "std::string" : (value.indexOf(".") >= 0 ? "double" : "int");
			declarations.push(fieldType + " " + field + ";");
			values.push(value);
		}
		if (values.length == 0)
			return null;
		return "([&]() { struct __hxhx_opaque_block { "
			+ declarations.join(" ")
			+ " }; return __hxhx_opaque_block{"
			+ values.join(", ")
			+ "}; })()";
	}

	static function renderOpaqueStringMapRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*)=newhaxe\.ds\.StringMap\(\);(.+)\1;\}$/;
		if (!pattern.match(compact))
			return null;
		final local = sanitizeIdentifier(pattern.matched(1));
		final body = pattern.matched(2);
		final statements = new Array<String>();
		final setPattern = ~/^([A-Za-z_][A-Za-z0-9_]*)\.set\("((\\.|[^"])*)","((\\.|[^"])*)"\)$/;
		for (stmt in body.split(";")) {
			if (stmt.length == 0)
				continue;
			if (!setPattern.match(stmt) || sanitizeIdentifier(setPattern.matched(1)) != local)
				return null;
			statements.push(local
				+ "["
				+ quoteString(unescapeRawStringSegment(setPattern.matched(2)))
				+ "] = "
				+ quoteString(unescapeRawStringSegment(setPattern.matched(4)))
				+ ";");
		}
		if (statements.length == 0)
			return null;
		return "([&]() { std::map<std::string, std::string> " + local + "; " + statements.join(" ") + " return " + local + "; })()";
	}

	static function renderOpaqueTypedLocalRefRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):([^;{}]+);\1;\}$/;
		if (!pattern.match(compact))
			return null;
		final local = sanitizeIdentifier(pattern.matched(1));
		final typeName = cppTypeHint(pattern.matched(2));
		return "([&]() { " + typeName + " " + local + " = " + cppDefaultValue(typeName) + "; return " + local + "; })()";
	}

	static function renderOpaqueTypedLocalInitRaw(raw:String):Null<String> {
		final compact = compactRawText(raw);
		final pattern = ~/^opaque_block_expr:\{var([A-Za-z_][A-Za-z0-9_]*):([^=;{}]+)=([A-Za-z_][A-Za-z0-9_]*|"[^"]*"|-?[0-9.]+);\}$/;
		if (!pattern.match(compact))
			return null;
		final local = sanitizeIdentifier(pattern.matched(1));
		final typeName = cppTypeHint(pattern.matched(2));
		return "([&]() { " + typeName + " " + local + " = " + renderOpaqueSimpleValue(pattern.matched(3)) + "; return 0; })()";
	}

	static function renderOpaqueSimpleValue(rawValue:String):String {
		final numericPattern = ~/^-?[0-9.]+$/;
		if (StringTools.startsWith(rawValue, "\"") || numericPattern.match(rawValue))
			return rawValue;
		return sanitizeIdentifier(rawValue);
	}

	static function unescapeRawStringSegment(value:String):String {
		return StringTools.replace(StringTools.replace(StringTools.replace(value, "\\\\", "\\"), "\\\"", "\""), "\\'", "'");
	}

	static function isTypeExpr(left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		final typeName = typePathText(right);
		if (typeName == null)
			return "false";
		return "__hxhx_is_type(" + renderExpr(left, scope) + ", " + quoteString(typeName) + ")";
	}

	static function classValueComparisonExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		final typePath = typePathText(expr);
		if (typePath == null || typePath.length == 0)
			return null;
		final baseName = sanitizeTypePath(typeBaseName(typePath));
		if (baseName.length == 0 || !startsWithUppercaseTypeName(typePath))
			return null;
		if (exprNameHasLocalStorage(typePath, scope) || exprNameHasLocalStorage(baseName, scope))
			return null;
		return "std::string(" + quoteString(baseName) + ")";
	}

	static function encodingEnumComparisonExpr(op:String, left:HxExpr, right:HxExpr, ?scope:CppRenderScope):Null<String> {
		final leftEncoding = exprCppType(left, scope) == "std::shared_ptr<Encoding>";
		final rightEncoding = exprCppType(right, scope) == "std::shared_ptr<Encoding>";
		final leftCtor = encodingEnumCtorName(left);
		final rightCtor = encodingEnumCtorName(right);
		if (leftEncoding && rightCtor != null)
			return encodingEnumComparisonFor(left, rightCtor, op, scope);
		if (rightEncoding && leftCtor != null)
			return encodingEnumComparisonFor(right, leftCtor, op, scope);
		return null;
	}

	static function encodingEnumComparisonFor(value:HxExpr, ctor:String, op:String, ?scope:CppRenderScope):Null<String> {
		final rendered = renderExpr(value, scope);
		return switch (ctor) {
			case "UTF8":
				"(" + rendered + " " + op + " nullptr)";
			case "RawNative":
				"(" + rendered + " " + (op == "==" ? "!=" : "==") + " nullptr)";
			case _:
				null;
		};
	}

	static function encodingEnumCtorName(expr:HxExpr):Null<String> {
		return switch (expr) {
			case EIdent(name) if (name == "UTF8" || name == "RawNative"):
				name;
			case EField(_, "UTF8"):
				"UTF8";
			case EField(_, "RawNative"):
				"RawNative";
			case _:
				null;
		};
	}

	static function typePathText(expr:HxExpr):Null<String> {
		return switch (expr) {
			case EString(value):
				value;
			case EIdent(name):
				name;
			case EField(owner, field):
				final prefix = typePathText(owner);
				prefix == null ? field : prefix + "." + field;
			case EUnsupported(raw) if (isTypePathText(raw)):
				raw;
			case _:
				null;
		};
	}

	static function typeDescriptorArgExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final typePath = typePathText(expr);
		if (typePath != null && typePath.length > 0) {
			final baseName = sanitizeTypePath(typeBaseName(typePath));
			if (baseName.length > 0
				&& startsWithUppercaseTypeName(baseName)
				&& !exprNameHasLocalStorage(typePath, scope)
				&& !exprNameHasLocalStorage(baseName, scope))
				return "std::string(" + quoteString(typePath) + ")";
		}
		return renderExpr(expr, scope);
	}

	static function classReferencePathText(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		final typePath = typePathText(expr);
		if (typePath == null || typePath.length == 0)
			return null;
		final baseName = sanitizeTypePath(typeBaseName(typePath));
		if (baseName.length == 0 || !startsWithUppercaseTypeName(baseName))
			return null;
		if (exprNameHasLocalStorage(typePath, scope) || exprNameHasLocalStorage(baseName, scope))
			return null;
		return scopeHasClass(scope, baseName) ? typePath : null;
	}

	static function isTypePathText(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		for (i in 0...value.length) {
			final c = value.charCodeAt(i);
			final ok = c == ".".code || c == "_".code || (c >= "0".code && c <= "9".code) || (c >= "A".code && c <= "Z".code)
				|| (c >= "a".code && c <= "z".code);
			if (!ok)
				return false;
		}
		return true;
	}

	static function compactRawText(raw:String):String {
		if (raw == null)
			return "";
		return StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(raw, " ", ""), "\n", ""), "\t", ""), "\r", "");
	}

	static function isSimpleIdentifierText(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		for (i in 0...value.length)
			if (!isIdentifierCharAt(value, i, i > 0))
				return false;
		return true;
	}

	static function isIdentifierCharAt(value:String, index:Int, allowDigit:Bool):Bool {
		final c = value.charAt(index);
		return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || (allowDigit && c >= "0" && c <= "9");
	}

	static function summarizeRaw(raw:String):String {
		if (raw == null)
			return "";
		final compact = compactRawText(raw);
		return compact.length <= 220 ? compact : compact.substr(0, 217) + "...";
	}

	static function renderUnsupportedRecoveryLiteral(raw:String):Null<String> {
		if (raw == null)
			return null;
		if (raw == "=")
			return "0";
		return renderUnsupportedNumericLiteral(raw);
	}

	static function enumCtorExpr(name:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final tag = "std::string(" + quoteString(name) + ")";
		if (args == null || args.length == 0)
			return tag;
		return "__hxhx_macro_enum("
			+ quoteString(name)
			+ ", std::vector<__HxMacroExpr>{"
			+ [for (arg in args) enumPayloadExpr(arg, scope)].join(", ") + "})";
	}

	static function enumPayloadExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case EEnumValue(name):
				"__hxhx_macro_enum(" + quoteString(name) + ")";
			case ECall(EEnumValue(name), args):
				if (args == null || args.length == 0) "__hxhx_macro_enum(" + quoteString(name) + ")"; else "__hxhx_macro_enum("
					+ quoteString(name)
					+ ", std::vector<__HxMacroExpr>{"
					+ [for (arg in args) enumPayloadExpr(arg, scope)].join(", ") + "})";
			case EString(value):
				"__hxhx_macro_string(" + quoteString(value) + ")";
			case EMacroExpr(inner, wrappers):
				CppMacroExpr.macroExpr(inner, wrappers);
			case _:
				"__hxhx_macro_value(" + renderExpr(expr, scope) + ")";
		};
	}

	static function enumCtorExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case EEnumValue(name):
				enumCtorValueForExpectedType(name, [], expectedType, scope);
			case ECall(EEnumValue(name), args):
				enumCtorValueForExpectedType(name, args, expectedType, scope);
			case _:
				null;
		};
	}

	static function enumCtorValueForExpectedType(name:String, args:Array<HxExpr>, expectedType:String, ?scope:CppRenderScope):Null<String> {
		final carrierType = classNameFromCppExprType(expectedType, scope);
		if (carrierType == null || carrierType.length == 0)
			return null;
		if (carrierType == "EnumValue")
			return enumValuePtrExpr(name, args, scope);
		if (args == null || args.length == 0)
			return "std::make_shared<" + carrierType + ">()";
		final parts = ["([&]() {"];
		for (i in 0...args.length)
			parts.push(" auto __hxhx_enum_arg_" + i + " = " + renderExpr(args[i], scope) + ";");
		for (i in 0...args.length)
			parts.push(" (void)__hxhx_enum_arg_" + i + ";");
		parts.push(" return std::make_shared<" + carrierType + ">(); })()");
		return parts.join("");
	}

	static function enumValuePtrExpr(name:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final payload = args == null
			|| args.length == 0 ? "{}" : "std::vector<std::string>{" + [for (arg in args) stringExpr(arg, scope)].join(", ") + "}";
		return "std::make_shared<EnumValue>(std::string(" + quoteString(name) + "), 0, " + payload + ")";
	}

	static function pointerCtorExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				pointerCtorExprForExpectedType(inner, expectedType, scope);
			case ECall(EField(receiver, "raw_ptr"), args) if (args.length == 0 && exprCppType(receiver, scope) == "std::string"):
				final carrier = pointerCarrierType(expectedType, "RawConstPointer");
				carrier == null ? null : "std::make_shared<"
				+ carrier
				+ ">("
				+ renderExpr(receiver, scope)
				+ ".c_str())";
			case ECall(EField(receiver, "fromPointer"), args) if (args.length == 1 && isCppConstPointerStaticReceiver(receiver)):
				final carrier = pointerCarrierType(expectedType, "ConstPointer");
				carrier == null ? null : "std::make_shared<"
				+ carrier
				+ ">("
				+ renderExpr(args[0], scope)
				+ ")";
			case _:
				null;
		};
	}

	static function typePathPlaceholderExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (!isCppTypePathReferenceType(expectedType))
			return null;
		return switch (expr) {
			case EAnon(_, _) | ECall(ELambda(_, _), _):
				cppDefaultValue(expectedType, scope);
			case _:
				null;
		};
	}

	static function classReferenceArgExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		final expectedClass = classNameFromCppType(expectedType);
		if (expectedClass == null || sanitizeTypePath(typeBaseName(expectedClass)) != "Class")
			return null;
		final classReferencePath = classReferencePathText(expr, scope);
		return classReferencePath == null ? null : "Type::resolveClass(" + quoteString(classReferencePath) + ")";
	}

	static function structuralTypedefValueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		final cls = structuralTypedefClassForCppType(expectedType, scope);
		if (cls == null)
			return null;
		return switch (expr) {
			case ENull:
				expectedType + "()";
			case EAnon(fieldNames, fieldValues):
				final args = new Array<String>();
				for (field in HxClassDecl.getFields(cls)) {
					if (HxFieldDecl.getIsStatic(field))
						continue;
					final index = fieldNames.indexOf(HxFieldDecl.getName(field));
					final fieldType = knownStdlibFieldCppType(sanitizeTypePath(HxClassDecl.getName(cls)), HxFieldDecl.getName(field),
						HxFieldDecl.getTypeHint(field), HxFieldDecl.getInit(field), scope);
					args.push(index >= 0
						&& index < fieldValues.length ? valueExprForExpectedType(fieldValues[index], fieldType, scope) : cppDefaultValue(fieldType, scope));
				}
				expectedType + "(" + args.join(", ") + ")";
			case _:
				final actualType = exprCppType(expr, scope);
				if (actualType == expectedType) null; else if (isCppReferenceType(actualType)) expectedType + "(*" + renderExpr(expr,
					scope) + ")"; else expectedType + "(" + renderExpr(expr, scope) + ")";
		};
	}

	static function anonStructValueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || expectedType == null || !scope.anonStructs.exists(expectedType))
			return null;
		final struct = scope.anonStructs.get(expectedType);
		return switch (expr) {
			case EAnon(fieldNames, fieldValues):
				final args = new Array<String>();
				for (i in 0...struct.fieldNames.length) {
					final fieldType = i < struct.fieldTypes.length ? struct.fieldTypes[i] : "";
					final index = fieldNames.indexOf(struct.fieldNames[i]);
					args.push(index >= 0
						&& index < fieldValues.length ? valueExprForExpectedType(fieldValues[index], fieldType, scope) : cppDefaultValue(fieldType, scope));
				}
				expectedType + "(" + args.join(", ") + ")";
			case _:
				null;
		};
	}

	static function posInfosValueExprForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (expectedType != "PosInfos")
			return null;
		return switch (expr) {
			case EAnon(fieldNames, fieldValues) if (isPosInfosAnon(fieldNames, fieldValues)):
				"PosInfos(" + posInfosCtorArgs(fieldNames, fieldValues, scope).join(", ") + ")";
			case _:
				null;
		};
	}

	static function pointerCarrierType(expectedType:String, baseName:String):Null<String> {
		final carrier = classNameFromCppType(expectedType);
		if (carrier == null || carrier.length == 0)
			return null;
		final base = sanitizeTypePath(typeBaseName(carrier));
		return base == baseName ? carrier : null;
	}

	static function assignmentRhsExpr(left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		final expectedType = assignmentExpectedCppType(left, scope);
		if (expectedType == "std::shared_ptr<PosInfos>")
			return posInfosSharedPtrExpr(right, scope);
		if (isCppFunctionType(expectedType))
			return valueExprForExpectedType(right, expectedType, scope);
		if (isCppVectorType(expectedType)) {
			switch (right) {
				case ENull:
					return cppDefaultValue(expectedType, scope);
				case _:
					return valueExprForExpectedType(right, expectedType, scope);
			}
		}
		if (isCppReferenceType(expectedType))
			return valueExprForExpectedType(right, expectedType, scope);
		if (structuralTypedefClassForCppType(expectedType, scope) != null)
			return valueExprForExpectedType(right, expectedType, scope);
		return renderExpr(right, scope);
	}

	static function assignmentExpr(left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		final setter = propertySetterAssignmentExpr(left, right, scope);
		return setter != null ? setter : assignmentLhsExpr(left, scope) + " = " + assignmentRhsExpr(left, right, scope);
	}

	static function propertySetterAssignmentExpr(left:HxExpr, right:HxExpr, ?scope:CppRenderScope):Null<String> {
		return switch (left) {
			case EField(EThis, field) if (scopeOwnerIsHxhxAbstract(scope) && hasInstanceField(scope.owner, field)):
				null;
			case EField(receiver, field):
				final receiverType = exprCppType(receiver, scope);
				final setter = "set_" + sanitizeIdentifier(field);
				final className = instanceMethodReceiverClassName(receiverType, scope);
				if (className == null
					|| !classHasInstanceMethod(className, setter,
						scope)) null; else renderExpr(receiver, scope)
					+ fieldAccessOp(receiver, scope)
					+ setter
					+ "("
					+ renderFieldCallArgs(receiverType, setter, [right], scope).join(", ")
					+ ")";
			case _:
				null;
		};
	}

	static function abstractThisAnonAssignmentLines(fieldNames:Array<String>, fieldValues:Array<HxExpr>, indent:String,
			?scope:CppRenderScope):Null<Array<String>> {
		if (scope == null || scope.owner == null || !scopeOwnerIsHxhxAbstract(scope))
			return null;
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...count)
			if (!hasInstanceField(scope.owner, fieldNames[i]))
				return null;
		final out = new Array<String>();
		for (i in 0...count) {
			final fieldName = sanitizeIdentifier(fieldNames[i]);
			final expectedType = constructorFieldCppType(scope, fieldName);
			final rhs = expectedType == null
				|| expectedType.length == 0 ? renderExpr(fieldValues[i], scope) : valueExprForExpectedType(fieldValues[i], expectedType, scope);
			out.push(indent + "this->" + fieldName + " = " + rhs + ";");
		}
		return out;
	}

	static function assignmentExpectedCppType(left:HxExpr, ?scope:CppRenderScope):String {
		final fieldType = assignmentExpectedFieldCppType(left, scope);
		if (fieldType != null && fieldType.length > 0)
			return fieldType;
		final abstractUnderlying = assignmentExpectedAbstractUnderlyingCppType(left, scope);
		if (abstractUnderlying.length > 0)
			return abstractUnderlying;
		final leftType = exprCppType(left, scope);
		final optionalInner = cppOptionalInnerType(leftType);
		return optionalInner.length > 0 ? optionalInner : leftType;
	}

	static function assignmentExpectedAbstractUnderlyingCppType(left:HxExpr, ?scope:CppRenderScope):String {
		if (scope == null || scope.owner == null)
			return "";
		return switch (left) {
			case EThis:
				final underlying = abstractUnderlyingTypeHint(scope.owner);
				underlying == null ? "" : cppTypeHint(underlying, scope, {names: scope.classNames, byName: scope.classByName});
			case _:
				"";
		}
	}

	static function assignmentExpectedFieldCppType(left:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null || scope.owner == null)
			return null;
		final fieldName = switch (left) {
			case EIdent(name):
				sanitizeIdentifier(name);
			case EField(EThis, name):
				sanitizeIdentifier(name);
			case _:
				return null;
		};
		return constructorFieldCppType(scope, fieldName);
	}

	static function assignmentLhsExpr(left:HxExpr, ?scope:CppRenderScope):String {
		return switch (left) {
			case EIdent(name) if (exprHasOptionalType(left, scope)):
				sanitizeIdentifier(name);
			case EField(receiver, field):
				final known = staticFieldExpr(receiver, field, scope);
				if (known != null) known; else {
					final typePath = staticReceiverTypePath(receiver);
					if (typePath != null
						&& typePath.length > 0
						&& !exprNameHasLocalStorage(typePath, scope)
						&& startsWithUppercaseTypeName(typePath))
						sanitizeTypePath(typeBaseName(typePath)) + "::" + sanitizeIdentifier(field);
					else
						renderExpr(left, scope);
				}
			case _:
				renderExpr(left, scope);
		}
	}

	static function exprNameHasLocalStorage(name:String, ?scope:CppRenderScope):Bool {
		return scope != null && name != null && scope.localTypes.exists(sanitizeIdentifier(name));
	}

	static function startsWithUppercaseTypeName(typePath:String):Bool {
		final clean = sanitizeTypePath(typeBaseName(typePath == null ? "" : typePath));
		if (clean.length == 0)
			return false;
		final first = clean.charCodeAt(0);
		return first >= "A".code && first <= "Z".code;
	}

	static function posInfosSharedPtrExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return switch (expr) {
			case EAnon(fieldNames, fieldValues) if (isPosInfosAnon(fieldNames, fieldValues)):
				"std::make_shared<PosInfos>(" + posInfosCtorArgs(fieldNames, fieldValues, scope).join(", ") + ")";
			case _:
				renderExpr(expr, scope);
		};
	}

	static function stringExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final macroApiCall = macroApiCallExprForExpected(expr, "std::string", scope);
		if (macroApiCall != null)
			return macroApiCall;
		final enumCtor = enumMetadataCtorStringExpr(expr, scope);
		if (enumCtor != null)
			return enumCtor;
		switch (expr) {
			case ECall(_, _) | EField(_, _):
				if (exprCppType(expr, scope) == "std::string")
					return renderExpr(expr, scope);
			case _:
		}
		final primitiveAbstractString = primitiveBackedAbstractToStringExpr(expr, scope);
		if (primitiveAbstractString != null)
			return primitiveAbstractString;
		final classBackedAbstractString = classBackedAbstractToStringExpr(expr, scope);
		if (classBackedAbstractString != null)
			return classBackedAbstractString;
		if (classNameFromCppExprType(exprCppType(expr, scope), scope) != null)
			return "__hxhx_type_name(" + renderExpr(expr, scope) + ")";
		final classReferencePath = classReferencePathText(expr, scope);
		if (classReferencePath != null)
			return "std::string(" + quoteString(classReferencePath) + ")";
		return switch (expr) {
			case EString(value):
				"std::string(" + quoteString(value) + ")";
			case EEnumValue(name):
				"std::string(" + quoteString(name) + ")";
			case EField(EIdent("Error"), field):
				"std::string(" + quoteString(field) + ")";
			case EMacroExpr(inner, wrappers):
				CppMacroExpr.macroExpr(inner, wrappers);
			case EMacroType(typeText):
				macroTypeExpr(typeText);
			case ECast(inner, _) | EUntyped(inner):
				stringExpr(inner, scope);
			case EBool(_):
				"std::string(" + renderExpr(expr, scope) + " ? \"true\" : \"false\")";
			case _ if (exprCppType(expr, scope) == "bool" || inferExprCppType(expr, scope) == "bool"):
				"std::string(" + renderExpr(expr, scope) + " ? \"true\" : \"false\")";
			case EInt(_) | EFloat(_):
				"std::to_string(" + renderExpr(expr, scope) + ")";
			case ECall(EField(_, method), _) if (method == "__URLEncode" || method == "__URLDecode"):
				renderExpr(expr, scope);
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				stringExpr(args[0], scope);
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				stringExpr(args[2], scope);
			case ECall(EIdent("__hxhx_throw"), args) if (args.length == 1):
				"__hxhx_throw_as<std::string>(" + renderExpr(args[0], scope) + ")";
			case _ if (isCppExceptionValueType(exprCppType(expr, scope)) || isCppDynamicValueType(exprCppType(expr, scope))):
				"__hxhx_stringify(" + renderExpr(expr, scope) + ")";
			case EArrayDecl(_):
				"__hxhx_stringify(" + renderExpr(expr, scope) + ")";
			case ETernary(cond, thenExpr, elseExpr) if (inferExprCppType(expr, scope) == "std::string"):
				"("
				+ conditionExpr(cond, scope)
				+ " ? "
				+ stringExpr(thenExpr, scope)
				+ " : "
				+ stringExpr(elseExpr, scope)
				+ ")";
			case ECall(ELambda(_, _), _) if (inferExprCppType(expr, scope) == "std::string"):
				renderExpr(expr, scope);
			case EBinop(_, _, _) if (inferExprCppType(expr, scope) == "std::string"):
				renderExpr(expr, scope);
			case ECall(EField(_, "indexOf"), args) if (args.length == 1 || args.length == 2):
				"std::to_string(" + renderExpr(expr, scope) + ")";
			case ECall(EIdent(_), _) if (exprCppType(expr, scope) == "std::string"):
				renderExpr(expr, scope);
			case ECall(EField(_, _), _) if (exprCppType(expr, scope) == "std::string"):
				renderExpr(expr, scope);
			case ENew(typePath, _) if (primitiveBackedAbstractCppTypeForTypeHint(typePath, scope) == "std::string"):
				renderExpr(expr, scope);
			case ECall(EIdent(_), _) | ECall(EField(_, _), _):
				callStringExpr(expr, scope);
			case EField(_, "length"):
				"std::to_string(" + renderExpr(expr, scope) + ")";
			case EField(_, _) if (exprCppType(expr, scope) == "std::string"):
				renderExpr(expr, scope);
			case EArrayAccess(_, _):
				"std::string(" + renderExpr(expr, scope) + ")";
			case EBinop("+", left, right) if (isCppStringExpr(left, scope) || isCppStringExpr(right, scope)):
				"("
				+ stringExpr(left, scope)
				+ " + "
				+ stringExpr(right, scope)
				+ ")";
			case ESwitch(_, _, _) if (switchExprResultType(switchExprBranches(expr)) == "std::string"):
				renderExpr(expr, scope);
			case ETernary(cond, thenExpr, elseExpr) if (isStringLike(thenExpr) && isStringLike(elseExpr)):
				"("
				+ conditionExpr(cond, scope)
				+ " ? "
				+ stringExpr(thenExpr, scope)
				+ " : "
				+ stringExpr(elseExpr, scope)
				+ ")";
			case EIdent(name):
				final local = localCppName(name, scope);
				final typeName = exprCppType(expr, scope);
				if (typeName == CppMacroExpr.CPP_TYPE) "__hxhx_macro_to_string("
					+ local
					+ ")"; else if (typeName == "std::string") "std::string(" + local + ")"; else if (isCppExceptionValueType(typeName)
					|| isCppDynamicValueType(typeName)) "__hxhx_stringify("
					+ local
					+ ")"; else if (typeName == "bool") "std::string(" + local + " ? \"true\" : \"false\")"; else if (typeName == "int"
					|| typeName == "double" || typeName == "float" || typeName == "long long") "std::to_string("
					+ local
					+ ")"; else "__hxhx_stringify(" + local + ")";
			case ENull:
				"std::string()";
			case _:
				"std::to_string(" + renderExpr(expr, scope) + ")";
		};
	}

	static function stringReceiverExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		return isStringLike(expr) ? stringExpr(expr, scope) : renderExpr(expr, scope);
	}

	/**
		Lower the `haxe.macro.Context.load(name, arity)(...)` shape used by
		upstream macro helpers to a typed C++ support call.

		This is intentionally compile-safe callable plumbing, not a C++ macro
		runtime. The helper returns target defaults so Gate3 source can keep
		advancing until native macro execution owns the real behavior.
	**/
	static function macroApiCallExprForExpected(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case ECall(ECall(loadCallee, loadArgs), callArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				macroApiLoadCallExpr(expectedType, loadArgs, callArgs, scope);
			case ECall(loadCallee, loadArgs) if (isMacroApiLoadCallee(loadCallee) && loadArgs.length == 2):
				macroApiLoadCallExpr(expectedType, loadArgs, [], scope);
			case ECall(EField(receiver, "callMacroApi"), args) if (isContextStaticReceiver(receiver) && args.length >= 1):
				macroApiDirectCallExpr(expectedType, args, scope);
			case ECall(EIdent("callMacroApi"), args) if (scopeOwnerIsMacroApiHost(scope) && args.length >= 1):
				macroApiDirectCallExpr(expectedType, args, scope);
			case _:
				null;
		};
	}

	static function macroApiLoadCallExpr(expectedType:String, loadArgs:Array<HxExpr>, callArgs:Array<HxExpr>, ?scope:CppRenderScope):String {
		final rendered = [stringExpr(loadArgs[0], scope), renderExpr(loadArgs[1], scope)];
		for (arg in callArgs)
			rendered.push(renderExpr(arg, scope));
		return "__hxhx_call_macro_api<" + macroApiResultType(expectedType) + ">(" + rendered.join(", ") + ")";
	}

	static function macroApiDirectCallExpr(expectedType:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final rendered = [stringExpr(args[0], scope)];
		for (i in 1...args.length)
			rendered.push(renderExpr(args[i], scope));
		return "__hxhx_call_macro_api<" + macroApiResultType(expectedType) + ">(" + rendered.join(", ") + ")";
	}

	static function macroApiResultType(expectedType:String):String {
		final typeName = StringTools.trim(expectedType == null ? "" : expectedType);
		if (typeName.length == 0 || typeName == "auto")
			return "std::any";
		return switch (typeName) {
			case "std::shared_ptr<Null>":
				"std::any";
			case _:
				typeName;
		};
	}

	static function isMacroApiLoadCallee(callee:HxExpr):Bool {
		return switch (callee) {
			case EIdent("load"):
				true;
			case EField(receiver, "load") if (isContextStaticReceiver(receiver)):
				true;
			case _:
				false;
		};
	}

	static function isContextStaticReceiver(receiver:HxExpr):Bool {
		final path = staticReceiverTypePath(receiver);
		return path != null && sanitizeTypePath(typeBaseName(path)) == "Context";
	}

	static function scopeOwnerIsContext(?scope:CppRenderScope):Bool {
		return scope != null && scope.owner != null && sanitizeTypePath(typeBaseName(HxClassDecl.getName(scope.owner))) == "Context";
	}

	static function scopeOwnerIsMacroApiHost(?scope:CppRenderScope):Bool {
		if (scope == null || scope.owner == null)
			return false;
		return switch (sanitizeTypePath(typeBaseName(HxClassDecl.getName(scope.owner)))) {
			case "Context" | "Compiler":
				true;
			case _:
				false;
		};
	}

	/**
		Stringify the temporary enum metadata shape used by scanned helper enums.

		These values are not a general anonymous-object runtime for C++; they are the
		Stage3 bring-up representation for enum constructor identity. When a `Dynamic`
		constructor result is currently lowered as `std::string`, preserve the existing
		C++ MVP contract by returning the constructor tag instead of asking
		`std::to_string` to format an aggregate.
	**/
	static function enumMetadataCtorStringExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case EAnon(fieldNames, fieldValues):
				final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
				for (i in 0...count)
					if (fieldNames[i] == "__hx_ctor")
						return stringExpr(fieldValues[i], scope);
				null;
			case _:
				null;
		};
	}

	/**
		Lower the expression-position switch subset currently needed by the C++ gate.

		The result is an immediately-invoked lambda so the emitted code can appear in
		places like `var x = switch (...) { ... }`. This is intentionally narrower
		than full Haxe pattern matching: simple scalar patterns become comparisons,
		wildcard/bind patterns become the default branch, and complex pattern shapes
		do not match until they get explicit C++ semantics.

		When the caller knows the expected C++ result type, thread that type into the
		lambda return and fallback. Without the explicit result, C++ deduces mixed
		branches like `Ref<T>`/`null`/synthetic fallback as incompatible lambda
		returns before the surrounding method return type can help.
	**/
	static function switchExpr(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>, ?scope:CppRenderScope, ?expectedType:String):String {
		final typeName = switchExprExpectedResultType(exprs, expectedType, scope);
		final switchValue = "__hxhx_switch";
		final scrutineeExpr = isStringLike(scrutinee) ? stringExpr(scrutinee, scope) : renderExpr(scrutinee, scope);
		final out = [
			"([&]() -> " + typeName + " {",
			"  auto " + switchValue + " = " + scrutineeExpr + ";"
		];
		var defaultExpr:Null<HxExpr> = null;
		var defaultPattern:Null<HxSwitchPattern> = null;
		var emitted = 0;
		final count = patterns.length < exprs.length ? patterns.length : exprs.length;
		for (i in 0...count) {
			final pattern = patterns[i];
			if (switchPatternIsDefault(pattern)) {
				if (defaultExpr == null) {
					defaultExpr = exprs[i];
					defaultPattern = pattern;
				}
				continue;
			}
			final cond = switchPatternCond(pattern, switchValue);
			if (switchPatternShouldSkipKnownFalseBranch(pattern, cond))
				continue;
			out.push("  " + (emitted == 0 ? "if" : "else if") + " (" + cond + ") {");
			for (line in switchPatternBindingLines(pattern, switchValue, "    ", scope, typeName, exprs[i]))
				out.push(line);
			out.push("    return " + switchBranchExpr(exprs[i], typeName, scope) + ";");
			out.push("  }");
			emitted++;
		}
		if (defaultExpr != null) {
			out.push("  " + (emitted == 0 ? "{" : "else {"));
			for (line in switchPatternBindingLines(defaultPattern, switchValue, "    ", scope, typeName, defaultExpr))
				out.push(line);
			out.push("    return " + switchBranchExpr(defaultExpr, typeName, scope) + ";");
			out.push("  }");
		}
		out.push("  return " + switchFallbackExpr(typeName, scope) + ";");
		out.push("})()");
		return out.join("\n");
	}

	static function switchExprBranches(expr:HxExpr):Array<HxExpr> {
		return switch (expr) {
			case ESwitch(_, _, exprs):
				exprs;
			case _:
				[];
		};
	}

	static function switchBranchExpr(expr:HxExpr, typeName:String, ?scope:CppRenderScope):String {
		if (typeName == "std::nullptr_t")
			return "([&]() { " + renderExpr(expr, scope) + "; return nullptr; })()";
		return typeName == "std::string" ? stringExpr(expr, scope) : valueExprForExpectedType(expr, typeName, scope);
	}

	static function switchExprExpectedResultType(exprs:Array<HxExpr>, ?expectedType:String, ?scope:CppRenderScope):String {
		final typeName = StringTools.trim(expectedType == null ? "" : expectedType);
		if (typeName.length > 0 && typeName != "auto")
			return typeName;
		return switchExprResultType(exprs, scope);
	}

	static function switchExprResultType(exprs:Array<HxExpr>, ?scope:CppRenderScope):String {
		for (expr in exprs)
			if (isStringLike(expr))
				return "std::string";
		for (expr in exprs)
			switch (expr) {
				case EFloat(_):
					return "double";
				case _:
			}
		for (expr in exprs)
			switch (expr) {
				case EBool(_):
					return "bool";
				case _:
			}
		for (expr in exprs)
			switch (expr) {
				case ENew(typePath, _):
					final typeName = cppTypeHint(typePath, scope);
					if (typeName.length > 0)
						return typeName;
				case _:
			}
		return "int";
	}

	static function switchFallbackExpr(typeName:String, ?scope:CppRenderScope):String {
		return switch (typeName) {
			case "std::string":
				"std::string()";
			case "double":
				"0.0";
			case "bool":
				"false";
			case "std::nullptr_t":
				"nullptr";
			case _:
				cppDefaultValue(typeName, scope);
		};
	}

	static function switchPatternIsDefault(pattern:HxSwitchPattern):Bool {
		return switch (pattern) {
			case PWildcard | PBind(_):
				true;
			case _:
				false;
		};
	}

	static function switchPatternKind(pattern:HxSwitchPattern):String {
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
			case PIntCompareGuard(_, _, _, _): "PIntCompareGuard";
			case PParsedIntSwitchGuard(_, _, _, _): "PParsedIntSwitchGuard";
			case PUnsupportedGuard(_): "PUnsupportedGuard";
			case PBind(_): "PBind";
			case POr(_): "POr";
		};
	}

	static function switchPatternCond(pattern:HxSwitchPattern, switchValue:String):String {
		return switch (pattern) {
			case PNull:
				switchValue + " == nullptr";
			case PWildcard | PBind(_):
				"true";
			case PBool(value):
				switchValue + " == " + (value ? "true" : "false");
			case PString(value):
				switchValue + " == std::string(" + quoteString(value) + ")";
			case PInt(value):
				switchValue + " == " + Std.string(value);
			case PEnumValue(name):
				"__hxhx_enum_eq(" + switchValue + ", " + quoteString(name) + ")";
			case PCapture(_, inner):
				switchPatternCond(inner, switchValue);
			case PUnsupportedGuard(_):
				"false";
			case POr(patterns):
				if (patterns == null || patterns.length == 0) {
					"false";
				} else {
					"(" + [
						for (p in patterns)
							"(" + switchPatternCond(p, switchValue) + ")"
					].join(" || ") + ")";
				}
			case PEnumExtract(name, args):
				switchEnumExtractPatternCond(name, args, switchValue);
			case PObject(fieldNames, fieldPatterns):
				switchObjectPatternCond(fieldNames, fieldPatterns, switchValue);
			case PArray(_) | PExtractor(_, _) | PLengthGuard(_, _, _) | PStartsWithGuard(_, _, _) | PIntEqualsGuard(_, _, _) | PIntCompareGuard(_, _, _, _) |
				PParsedIntSwitchGuard(_, _, _, _):
				"false";
		};
	}

	static function switchEnumExtractPatternCond(name:String, args:Array<HxSwitchPattern>, switchValue:String):String {
		final parts = ["__hxhx_macro_ctor(" + switchValue + ", " + quoteString(name) + ")"];
		if (args != null) {
			for (i in 0...args.length) {
				final argValue = "__hxhx_macro_param(" + switchValue + ", " + Std.string(i) + ")";
				parts.push("(" + switchPatternCond(args[i], argValue) + ")");
			}
		}
		return "(" + parts.join(" && ") + ")";
	}

	static function switchPatternCondIsKnownFalse(cond:String):Bool {
		final compact = cond == null ? "" : removeTypeHintWhitespace(cond);
		if (compact == "false" || compact == "(false)")
			return true;
		return compact.indexOf("&&false") >= 0 || compact.indexOf("&&(false)") >= 0 || compact.indexOf("false&&") >= 0 || compact.indexOf("(false)&&") >= 0;
	}

	static function switchPatternShouldSkipKnownFalseBranch(pattern:HxSwitchPattern, cond:String):Bool {
		if (!switchPatternCondIsKnownFalse(cond))
			return false;
		return switch (pattern) {
			case PEnumExtract(_, _):
				true;
			case PCapture(_, inner):
				switchPatternShouldSkipKnownFalseBranch(inner, cond);
			case _:
				false;
		};
	}

	static function switchObjectPatternCond(fieldNames:Array<String>, fieldPatterns:Array<HxSwitchPattern>, switchValue:String):String {
		if (fieldNames == null || fieldPatterns == null)
			return "false";
		final parts = new Array<String>();
		final count = fieldNames.length < fieldPatterns.length ? fieldNames.length : fieldPatterns.length;
		for (i in 0...count) {
			final fieldValue = switchObjectPatternFieldValue(fieldNames[i], switchValue);
			if (fieldValue == null)
				return "false";
			parts.push("(" + switchPatternCond(fieldPatterns[i], fieldValue) + ")");
		}
		return parts.length == 0 ? "true" : "(" + parts.join(" && ") + ")";
	}

	static function switchObjectPatternFieldValue(fieldName:String, switchValue:String):Null<String> {
		return switch (fieldName) {
			case "expr":
				"__hxhx_macro_expr_field(" + switchValue + ")";
			case _:
				null;
		};
	}

	/**
		Declare C++ locals for pattern names before a branch body is rendered.

		Why:
		- The C++ MVP already parses switch patterns with binders such as
		  `Module(m)` and then renders branch bodies that reference `m`.
		- Even when a complex pattern is still semantically non-matching in this
		  MVP, C++ type-checks the branch body and fails if those names are absent.

		What/How:
		- Bind every captured name to the current switch value, or to an indexed
		  element for exact-length array patterns.
		- If a non-macro enum payload binder is returned directly from a switch with
		  a known expected result type, bind it as a typed default value so C++ can
		  type-check the branch until real enum payload extraction owns semantics.
		  Macro-expression extraction keeps the real `__hxhx_macro_param` value.
		- This intentionally does not claim full enum/array/object destructuring
		  semantics. Real extraction from `__hx_params` or target runtime enum
		  values should land as a separate behavior-owned seam.
	**/
	static function switchPatternBindingLines(pattern:HxSwitchPattern, switchValue:String, indent:String, ?scope:CppRenderScope, ?expectedType:String,
			?branchExpr:HxExpr):Array<String> {
		final out = new Array<String>();
		function bind(name:String, value:String):Void {
			if (name != null && name.length > 0 && name != "_") {
				final local = sanitizeIdentifier(name);
				final typeName = switchPatternValueIsMacroExtraction(value) ? "" : switchPatternExpectedBindingType(name, expectedType, branchExpr);
				if (typeName.length > 0)
					out.push(indent + typeName + " " + local + " = " + cppDefaultValue(typeName, scope) + ";");
				else
					out.push(indent + "auto " + local + " = " + value + ";");
			}
		}
		function walk(p:HxSwitchPattern, value:String):Void {
			if (p == null)
				return;
			switch (p) {
				case PBind(name):
					bind(name, value);
				case PCapture(name, inner):
					bind(name, value);
					walk(inner, value);
				case PEnumExtract(name, args):
					if (args != null && switchPatternIsMacroExprCtor(name)) {
						for (i in 0...args.length)
							walk(args[i], "__hxhx_macro_param(" + value + ", " + Std.string(i) + ")");
					} else if (args != null) {
						for (arg in args)
							walk(arg, value);
					}
				case PObject(fieldNames, fieldPatterns):
					if (fieldNames != null && fieldPatterns != null) {
						final count = fieldNames.length < fieldPatterns.length ? fieldNames.length : fieldPatterns.length;
						for (i in 0...count) {
							final fieldValue = switchObjectPatternFieldValue(fieldNames[i], value);
							if (fieldValue != null)
								walk(fieldPatterns[i], fieldValue);
						}
					}
				case PArray(items):
					if (items != null)
						for (i in 0...items.length)
							walk(items[i], "(" + value + "[" + Std.string(i) + "])");
				case PExtractor(_, resultPattern):
					walk(resultPattern, value);
				case PLengthGuard(inner, _, _), PStartsWithGuard(inner, _, _), PIntEqualsGuard(inner, _, _), PIntCompareGuard(inner, _, _, _),
					PParsedIntSwitchGuard(inner, _, _, _), PUnsupportedGuard(inner):
					walk(inner, value);
				case POr(patterns):
					if (patterns != null && patterns.length > 0)
						walk(patterns[0], value);
				case _:
			}
		}
		walk(pattern, switchValue);
		return out;
	}

	static function switchPatternValueIsMacroExtraction(value:String):Bool {
		return value != null && StringTools.startsWith(StringTools.trim(value), "__hxhx_macro_");
	}

	static function switchPatternExpectedBindingType(name:String, ?expectedType:String, ?branchExpr:HxExpr):String {
		final typeName = StringTools.trim(expectedType == null ? "" : expectedType);
		if (typeName.length == 0 || typeName == "auto" || branchExpr == null)
			return "";
		return exprIsIdentifier(branchExpr, name) ? typeName : "";
	}

	static function exprIsIdentifier(expr:HxExpr, name:String):Bool {
		return switch (expr) {
			case EIdent(id):
				sanitizeIdentifier(id) == sanitizeIdentifier(name);
			case ECast(inner, _) | EUntyped(inner):
				exprIsIdentifier(inner, name);
			case _:
				false;
		};
	}

	static function switchPatternIsMacroExprCtor(name:String):Bool {
		return switch (name) {
			case "EConst" | "EParenthesis" | "EUntyped" | "EField" | "EArray" | "EArrayDecl" | "EBinop" | "EUnop" | "ECall" | "CString" | "CInt" | "CFloat" |
				"CIdent" | "OpIn" | "OpArrow" | "DoubleQuotes":
				true;
			case _:
				false;
		};
	}

	static function indexOfExpr(receiver:HxExpr, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final source = renderExpr(receiver, scope);
		final receiverType = exprCppType(receiver, scope);
		final needle = receiverType == "std::vector<int>" ? renderExpr(args[0], scope) : stringExpr(args[0], scope);
		final start = args.length == 2 ? renderExpr(args[1], scope) : "0";
		return "__hxhx_index_of(" + source + ", " + needle + ", " + start + ")";
	}

	static function int64StaticCallExpr(method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		return switch (normalizeInt64Method(method)) {
			case "ofInt" if (args.length == 1):
				"static_cast<long long>(" + renderExpr(args[0], scope) + ")";
			case "make" if (args.length == 2):
				"((static_cast<long long>("
				+ renderExpr(args[0], scope)
				+ ") << 32) | static_cast<unsigned int>("
				+ renderExpr(args[1], scope)
				+ "))";
			case "add" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " + " + renderExpr(args[1], scope) + ")";
			case "sub" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " - " + renderExpr(args[1], scope) + ")";
			case "mul" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " * " + renderExpr(args[1], scope) + ")";
			case "div" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " / " + renderExpr(args[1], scope) + ")";
			case "mod" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " % " + renderExpr(args[1], scope) + ")";
			case "divMod" if (args.length == 2):
				int64DivModExpr(args[0], args[1], scope);
			case "and" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " & " + renderExpr(args[1], scope) + ")";
			case "or" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " | " + renderExpr(args[1], scope) + ")";
			case "xor" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " ^ " + renderExpr(args[1], scope) + ")";
			case "shl" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " << " + renderExpr(args[1], scope) + ")";
			case "shr" if (args.length == 2):
				"(" + renderExpr(args[0], scope) + " >> " + renderExpr(args[1], scope) + ")";
			case "ushr" if (args.length == 2):
				"(static_cast<unsigned long long>("
				+ renderExpr(args[0], scope)
				+ ") >> "
				+ renderExpr(args[1], scope)
				+ ")";
			case "neg" if (args.length == 1):
				"(-" + renderExpr(args[0], scope) + ")";
			case "isNeg" if (args.length == 1):
				"(" + renderExpr(args[0], scope) + " < 0)";
			case "compare" if (args.length == 2):
				int64CompareExpr(args[0], args[1], false, scope);
			case "ucompare" if (args.length == 2):
				int64CompareExpr(args[0], args[1], true, scope);
			case "toStr" if (args.length == 1):
				"std::to_string(" + renderExpr(args[0], scope) + ")";
			case "parseString" if (args.length == 1):
				"Int64Helper::parseString(" + stringExpr(args[0], scope) + ")";
			case "fromFloat" if (args.length == 1):
				"Int64Helper::fromFloat(" + renderExpr(args[0], scope) + ")";
			case _:
				throw "C++ source backend MVP unsupported Int64 static call: " + method;
		};
	}

	static function int64ImportedStaticCallExpr(method:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final clean = normalizeInt64Method(method);
		if (int64StaticCallReturnCppType(clean, args.length).length == 0)
			return null;
		return int64StaticCallExpr(clean, args, scope);
	}

	static function int64InstanceOrExtensionCallExpr(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final clean = normalizeInt64Method(method);
		if (clean == "ofInt" && args.length == 0 && isCppIntExpr(receiver, scope))
			return "static_cast<long long>(" + renderExpr(receiver, scope) + ")";
		if (!isCppInt64Expr(receiver, scope))
			return null;
		final self = renderExpr(receiver, scope);
		return switch (clean) {
			case "toInt" if (args.length == 0):
				"__hxhx_int64_to_int(" + self + ")";
			case "toStr" if (args.length == 0):
				"std::to_string(" + self + ")";
			case "compare" if (args.length == 1):
				int64CompareExpr(receiver, args[0], false, scope);
			case "ucompare" if (args.length == 1):
				int64CompareExpr(receiver, args[0], true, scope);
			case "eq" if (args.length == 1):
				"(" + self + " == " + renderExpr(args[0], scope) + ")";
			case "neq" if (args.length == 1):
				"(" + self + " != " + renderExpr(args[0], scope) + ")";
			case "add" if (args.length == 1):
				"(" + self + " + " + renderExpr(args[0], scope) + ")";
			case "sub" if (args.length == 1):
				"(" + self + " - " + renderExpr(args[0], scope) + ")";
			case "mul" if (args.length == 1):
				"(" + self + " * " + renderExpr(args[0], scope) + ")";
			case "div" if (args.length == 1):
				"(" + self + " / " + renderExpr(args[0], scope) + ")";
			case "mod" if (args.length == 1):
				"(" + self + " % " + renderExpr(args[0], scope) + ")";
			case "divMod" if (args.length == 1):
				int64DivModExpr(receiver, args[0], scope);
			case "shl" if (args.length == 1):
				"(" + self + " << " + renderExpr(args[0], scope) + ")";
			case "shr" if (args.length == 1):
				"(" + self + " >> " + renderExpr(args[0], scope) + ")";
			case "ushr" if (args.length == 1):
				"(static_cast<unsigned long long>(" + self + ") >> " + renderExpr(args[0], scope) + ")";
			case "and" if (args.length == 1):
				"(" + self + " & " + renderExpr(args[0], scope) + ")";
			case "or" if (args.length == 1):
				"(" + self + " | " + renderExpr(args[0], scope) + ")";
			case "xor" if (args.length == 1):
				"(" + self + " ^ " + renderExpr(args[0], scope) + ")";
			case "neg" if (args.length == 0):
				"(-" + self + ")";
			case "isZero" if (args.length == 0):
				"(" + self + " == 0)";
			case "isNeg" if (args.length == 0):
				"(" + self + " < 0)";
			case _:
				null;
		};
	}

	static function int64InstanceOrExtensionCallReturnCppType(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final clean = normalizeInt64Method(method);
		if (clean == "ofInt" && args.length == 0 && isCppIntExpr(receiver, scope))
			return "long long";
		if (!isCppInt64Expr(receiver, scope))
			return "";
		return switch (clean) {
			case "toInt" if (args.length == 0):
				"int";
			case "toStr" if (args.length == 0):
				"std::string";
			case "compare" | "ucompare" if (args.length == 1):
				"int";
			case "eq" | "neq" if (args.length == 1):
				"bool";
			case "add" | "sub" | "mul" | "div" | "mod" | "shl" | "shr" | "ushr" | "and" | "or" | "xor" if (args.length == 1):
				"long long";
			case "divMod" if (args.length == 1):
				int64DivModStruct().name;
			case "neg" if (args.length == 0):
				"long long";
			case "isZero" | "isNeg" if (args.length == 0):
				"bool";
			case _:
				"";
		};
	}

	static function int64StaticCallNeedsHelper(method:String):Bool {
		final clean = normalizeInt64Method(method);
		return clean == "parseString" || clean == "fromFloat";
	}

	static function int64StaticCallReturnsInt(method:String):Bool {
		final clean = normalizeInt64Method(method);
		return clean == "compare" || clean == "ucompare";
	}

	static function int64ImportedStaticCallReturnCppType(method:String, argCount:Int):String {
		return int64StaticCallReturnCppType(normalizeInt64Method(method), argCount);
	}

	static function int64StaticOrHelperCallReturnCppType(receiver:HxExpr, method:String, argCount:Int):String {
		final clean = normalizeInt64Method(method);
		if (isInt64StaticReceiver(receiver))
			return int64StaticCallReturnCppType(clean, argCount);
		if (isInt64HelperReceiver(receiver)) {
			return switch (clean) {
				case "parseString" | "fromFloat" if (argCount == 1):
					"long long";
				case _:
					"";
			};
		}
		return "";
	}

	static function int64StaticCallReturnCppType(method:String, argCount:Int):String {
		return switch (method) {
			case "ofInt" | "parseString" | "fromFloat" | "neg" if (argCount == 1):
				"long long";
			case "make" | "add" | "sub" | "mul" | "div" | "mod" | "and" | "or" | "xor" | "shl" | "shr" | "ushr" if (argCount == 2):
				"long long";
			case "divMod" if (argCount == 2):
				int64DivModStruct().name;
			case "toStr" if (argCount == 1):
				"std::string";
			case "isNeg" if (argCount == 1):
				"bool";
			case "compare" | "ucompare" if (argCount == 2):
				"int";
			case _:
				"";
		};
	}

	static function isCppInt64Expr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		if (exprCppType(expr, scope) == "long long")
			return true;
		if (cppOptionalInnerType(exprCppType(expr, scope)) == "long long")
			return true;
		return switch (expr) {
			case ECall(EIdent("__hxhx_expr_meta"), args) if (args.length >= 3):
				isCppInt64Expr(args[2], scope);
			case ECall(EIdent("__hxhx_parenthesized"), args) if (args.length == 1):
				isCppInt64Expr(args[0], scope);
			case ECall(callee, args):
				switch (callee) {
					case EIdent("__hxhx_int_literal"):
						switch (args) {
							case [_, EString(suffix)]: suffix == "i64" || suffix == "u64";
							case _:
								false;
						}
					case EField(receiver, method): int64StaticOrHelperCallReturnCppType(receiver, method,
							args.length) == "long long" || int64InstanceOrExtensionCallReturnCppType(receiver, method, args, scope) == "long long";
					case EIdent(name): int64ImportedStaticCallReturnCppType(name,
							args.length) == "long long" && currentOrInheritedOwnerMethodOwner(name, scope) == null;
					case _:
						false;
				}
			case EUnop("-", inner) | EUnop("neg", inner) | EUnop("post++", inner) | EUnop("post--", inner) | ECast(inner, _) | EUntyped(inner):
				isCppInt64Expr(inner, scope);
			case EField(_, field) if (field == "quotient" || field == "modulus"):
				true;
			case EBinop(op, left, right) if (isIntegerArithmeticBinaryOp(op)): isCppInt64Expr(left, scope) || isCppInt64Expr(right, scope);
			case ETernary(_, thenExpr, elseExpr): isCppInt64Expr(thenExpr, scope) && isCppInt64Expr(elseExpr, scope);
			case _:
				false;
		};
	}

	static function normalizeInt64Method(method:String):String {
		return switch (sanitizeIdentifier(method)) {
			case "and_":
				"and";
			case "or_":
				"or";
			case "xor_":
				"xor";
			case other:
				other;
		};
	}

	static function int64DivModStruct():CppAnonStruct {
		return {
			name: anonStructName(["quotient", "modulus"], ["long long", "long long"]),
			fieldNames: ["quotient", "modulus"],
			fieldTypes: ["long long", "long long"]
		};
	}

	static function int64DivModExpr(dividend:HxExpr, divisor:HxExpr, ?scope:CppRenderScope):String {
		final struct = int64DivModStruct();
		final left = renderExpr(dividend, scope);
		final right = renderExpr(divisor, scope);
		return struct.name + "{(" + left + " / " + right + "), (" + left + " % " + right + ")}";
	}

	static function int64CompareExpr(leftExpr:HxExpr, rightExpr:HxExpr, unsigned:Bool, ?scope:CppRenderScope):String {
		var left = renderExpr(leftExpr, scope);
		var right = renderExpr(rightExpr, scope);
		if (unsigned) {
			left = "static_cast<unsigned long long>(" + left + ")";
			right = "static_cast<unsigned long long>(" + right + ")";
		}
		return "((" + left + " < " + right + ") ? -1 : ((" + left + " > " + right + ") ? 1 : 0))";
	}

	static function isStringToolsTrimMethod(method:String):Bool {
		return method == "ltrim" || method == "rtrim" || method == "trim";
	}

	static function stringToolsTrimCallExpr(method:String, value:HxExpr, ?scope:CppRenderScope):String {
		return switch (method) {
			case "ltrim":
				"__hxhx_ltrim(" + stringExpr(value, scope) + ")";
			case "rtrim":
				"__hxhx_rtrim(" + stringExpr(value, scope) + ")";
			case "trim":
				"__hxhx_trim(" + stringExpr(value, scope) + ")";
			case _:
				throw "C++ source backend MVP unsupported StringTools trim call: " + method;
		};
	}

	static function rangeExpr(start:HxExpr, end:HxExpr, ?scope:CppRenderScope):String {
		return "([&]() { std::vector<int> __hxhx_range_out; int __hxhx_range_start = "
			+ renderExpr(start, scope)
			+ "; int __hxhx_range_end = "
			+ renderExpr(end, scope)
			+
			"; for (int __hxhx_range_i = __hxhx_range_start; __hxhx_range_i < __hxhx_range_end; ++__hxhx_range_i) __hxhx_range_out.push_back(__hxhx_range_i); return __hxhx_range_out; })()";
	}

	/**
		Lower Haxe unsigned right shift for the current C++ MVP integer subset.

		Haxe `>>>` shifts after treating the left operand as an unsigned 32-bit
		value. C++ has no separate unsigned-shift operator, so the target-owned
		intrinsic is an unsigned cast followed by C++ `>>`.
	**/
	static function unsignedRightShiftExpr(left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		return "(static_cast<unsigned int>(" + renderExpr(left, scope) + ") >> " + renderExpr(right, scope) + ")";
	}

	static function isCppDoubleExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return switch (expr) {
			case EFloat(_):
				true;
			case _: exprCppType(expr, scope) == "double" || inferExprCppType(expr, scope) == "double";
		};
	}

	static function isCppIntExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return switch (expr) {
			case EInt(_):
				true;
			case _: exprCppType(expr, scope) == "int" || inferExprCppType(expr, scope) == "int";
		};
	}

	static function isCppOptionalIntExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return cppOptionalInnerType(exprCppType(expr, scope)) == "int" || cppOptionalInnerType(inferExprCppType(expr, scope)) == "int";
	}

	static function numericOperandExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final rendered = renderExpr(expr, scope);
		if (!isCppOptionalIntExpr(expr, scope))
			return rendered;
		return StringTools.endsWith(rendered, ".value()") ? rendered : rendered + ".value_or(0)";
	}

	static function isCppBoolExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return switch (expr) {
			case EBool(_):
				true;
			case _: exprCppType(expr, scope) == "bool" || inferExprCppType(expr, scope) == "bool";
		};
	}

	static function isCppStringExpr(expr:HxExpr, ?scope:CppRenderScope):Bool {
		return isStringLike(expr) || exprCppType(expr, scope) == "std::string" || inferExprCppType(expr, scope) == "std::string";
	}

	static function superMethodCallExpr(method:String, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		final owner = scope == null ? null : scope.owner;
		final baseType = owner == null ? null : baseTypeName(owner);
		if (baseType == null)
			throw "C++ source backend MVP unsupported expression: ESuper";
		return baseType + "::" + sanitizeIdentifier(method) + "(" + [for (arg in args) renderExpr(arg, scope)].join(", ") + ")";
	}

	static function superExpr(?scope:CppRenderScope):String {
		final owner = scope == null ? null : scope.owner;
		final baseType = owner == null ? null : baseTypeName(owner);
		if (baseType == null)
			throw "C++ source backend MVP unsupported expression: ESuper";
		return "(*this)";
	}

	static function lambdaExpr(args:Array<String>, body:HxExpr, ?scope:CppRenderScope):String {
		final params = [for (arg in args) "auto " + sanitizeIdentifier(arg)];
		return "[&](" + params.join(", ") + ") { return " + renderExpr(body, scope) + "; }";
	}

	static function forInExpr(iterable:HxExpr, bodyExpr:HxExpr, continuation:HxExpr, ?scope:CppRenderScope):String {
		return switch (bodyExpr) {
			case ELambda(args, body) if (args.length == 1):
				final local = sanitizeIdentifier(args[0]);
				final iteratorElementType = iteratorProtocolElementType(iterable, scope);
				final loopElementType = iteratorElementType.length > 0 ? iteratorElementType : iterableElementType(iterable, scope);
				final out = ["([&]() -> " + forInExprResultType(continuation, scope) + " {"];
				if (iteratorElementType.length > 0) {
					final iteratorLocal = "__hxhx_iter_" + local;
					final access = isCppReferenceType(exprCppType(iterable, scope)) ? "->" : ".";
					out.push("  auto " + iteratorLocal + " = " + renderExpr(iterable, scope) + ";");
					out.push("  while (" + iteratorLocal + access + "hasNext()) {");
					out.push("    auto " + local + " = " + iteratorLocal + access + "next();");
				} else
					switch (iterable) {
						case ERange(start, end):
							out.push("  for (int " + local + " = " + renderExpr(start, scope) + "; " + local + " < " + renderExpr(end, scope) + "; " + local
								+ "++) {");
						case _:
							out.push("  for (auto " + local + " : " + renderExpr(iterable, scope) + ") {");
					}
				withScopedLocal(scope, local, loopElementType, () -> {
					for (line in exprAsStatementLines(body, "    ", scope))
						out.push(line);
				});
				out.push("  }");
				for (line in forInContinuationLines(continuation, "  ", scope))
					out.push(line);
				out.push("})()");
				out.join("\n");
			case _:
				directCallExpr("__hxhx_for_in", [iterable, bodyExpr, continuation], scope);
		};
	}

	static function forInExprResultType(continuation:HxExpr, ?scope:CppRenderScope):String {
		return switch (continuation) {
			case ENull:
				"std::nullptr_t";
			case _ if (exprReturnsVoid(continuation, scope)):
				"std::nullptr_t";
			case _:
				final explicit = exprCppType(continuation, scope);
				if (explicit.length > 0 && explicit != "void") explicit; else {
					final inferred = inferExprCppType(continuation, scope);
					inferred.length > 0
					&& inferred != "void" ? inferred : "auto";
				}
		};
	}

	static function forInContinuationLines(continuation:HxExpr, indent:String, ?scope:CppRenderScope):Array<String> {
		return switch (continuation) {
			case ENull:
				[indent + "return nullptr;"];
			case _ if (exprReturnsVoid(continuation, scope)):
				exprAsStatementLines(continuation, indent, scope).concat([indent + "return nullptr;"]);
			case _:
				[indent + "return " + renderExpr(continuation, scope) + ";"];
		};
	}

	static function exprAsStatementLines(expr:HxExpr, indent:String, ?scope:CppRenderScope):Array<String> {
		return switch (expr) {
			case ECall(EIdent("__hxhx_for_in"), [iterable, bodyExpr, continuation]):
				[indent + forInExpr(iterable, bodyExpr, continuation, scope) + ";"];
			case ESwitch(scrutinee, patterns, exprs):
				[indent + switchExpr(scrutinee, patterns, exprs, scope, "std::nullptr_t") + ";"];
			case _:
				[indent + renderExpr(expr, scope) + ";"];
		};
	}

	static function voidSequenceLambdaCallExpr(lambdaArgs:Array<String>, body:HxExpr, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		if (args.length == 0 || lambdaArgs.length != args.length)
			return null;
		for (argName in lambdaArgs)
			if (!StringTools.startsWith(sanitizeIdentifier(argName), "__hxhx_lambda_seq_"))
				return null;
		for (arg in args)
			if (!exprReturnsVoid(arg, scope))
				return null;
		final statements = new Array<String>();
		for (arg in args)
			statements.push(renderExpr(arg, scope) + ";");
		return switch (body) {
			case ENull:
				"([&]() { " + statements.join(" ") + " return nullptr; })()";
			case _:
				"([&]() { " + statements.join(" ") + " return " + renderExpr(body, scope) + "; })()";
		};
	}

	static function exprReturnsVoid(expr:HxExpr, ?scope:CppRenderScope):Bool {
		final explicit = exprCppType(expr, scope);
		if (explicit == "void")
			return true;
		if (inferExprCppType(expr, scope) == "void")
			return true;
		return switch (expr) {
			case ECall(ELambda(_, body), _):
				exprReturnsVoid(body, scope);
			case _:
				knownVoidSequenceCall(expr);
		};
	}

	static function knownVoidSequenceCall(expr:HxExpr):Bool {
		return switch (expr) {
			case ECall(EIdent(name), _):
				knownVoidSequenceCallName(name);
			case ECall(EField(_, method), _):
				knownVoidSequenceCallName(method);
			case _:
				false;
		};
	}

	static function knownVoidSequenceCallName(name:String):Bool {
		return switch (sanitizeIdentifier(name == null ? "" : name)) {
			case "eq" | "feq" | "aeq" | "t" | "f" | "assert" | "exc" | "unspec" | "allow" | "noAssert" | "hf" | "nhf" | "hsf" | "nhsf":
				true;
			case _:
				false;
		};
	}

	static function optionalLambdaExprForExpectedFunction(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		return switch (expr) {
			case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(lambdaArgs, body), EArrayDecl(_)]):
				lambdaExprForExpectedFunction(lambdaArgs, body, expectedType, scope);
			case ECall(EIdent("__hxhx_optional_lambda"), [
				ECall(EIdent("__hxhx_rest_lambda"), [ELambda(lambdaArgs, body), EInt(_)]),
				EArrayDecl(_)
			]):
				lambdaExprForExpectedFunction(lambdaArgs, body, expectedType, scope);
			case _:
				null;
		};
	}

	static function boundMethodValueExprForExpectedFunction(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		return boundMethodValueExprWithExpectedType(expr, expectedType, scope);
	}

	static function lambdaExprForExpectedFunction(args:Array<String>, body:HxExpr, expectedType:String, ?scope:CppRenderScope):String {
		return lambdaExprWithArgTypes(args, body, CppTypeModel.cppFunctionArgTypesFromCppType(expectedType), scope,
			cppFunctionReturnTypeFromCppType(expectedType));
	}

	static function lambdaExprWithArgTypes(args:Array<String>, body:HxExpr, argTypes:Array<String>, ?scope:CppRenderScope, ?expectedReturnType:String):String {
		final names = [for (arg in args) sanitizeIdentifier(arg)];
		final params = [
			for (i in 0...names.length) {
				final typeName = i < argTypes.length && argTypes[i].length > 0 ? argTypes[i] : "auto";
				typeName + " " + names[i];
			}
		];
		final returnType = StringTools.trim(expectedReturnType == null ? "" : expectedReturnType);
		final explicitReturn = returnType.length > 0 && returnType != "auto";
		final suffix = explicitReturn ? " -> " + returnType : "";
		if (scope == null)
			return returnType == "void" ? "[&](" + params.join(", ") + ")" + suffix + " { " + renderExpr(body, scope) + "; }" : "[&]("
				+ params.join(", ")
				+ ")"
				+ suffix
				+ " { return "
				+ (explicitReturn ? valueExprForExpectedType(body, returnType, scope) : renderExpr(body, scope))
				+ "; }";
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalNames = copyStringMap(scope.localNames);
		for (i in 0...names.length) {
			scope.localNames.set(names[i], names[i]);
			if (i < argTypes.length && argTypes[i].length > 0)
				scope.localTypes.set(names[i], argTypes[i]);
		}
		final renderedBody = returnType == "void" ? renderExpr(body,
			scope) : explicitReturn ? valueExprForExpectedType(body, returnType, scope) : renderExpr(body, scope);
		scope.localTypes = savedLocalTypes;
		scope.localNames = savedLocalNames;
		if (returnType == "void")
			return "[&](" + params.join(", ") + ")" + suffix + " { " + renderedBody + "; }";
		return "[&](" + params.join(", ") + ")" + suffix + " { return " + renderedBody + "; }";
	}

	static function instanceMethodValueExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		return switch (expr) {
			case EField(receiver, method):
				final ownerType = switch (receiver) {
					case EThis:
						scope.owner == null ? null : sanitizeTypePath(HxClassDecl.getName(scope.owner));
					case _:
						classNameFromCppExprType(exprCppType(receiver, scope), scope);
				}
				if (ownerType == null || ownerType.length == 0)
					return null;
				final fn = classMethodDecl(ownerType, method, false, scope);
				if (fn == null)
					return null;
				final names = [
					for (arg in HxFunctionDecl.getArgs(fn))
						sanitizeIdentifier(HxFunctionArg.getName(arg))
				];
				final params = [for (name in names) "auto " + name];
				final target = switch (receiver) {
					case EThis:
						"this->";
					case _:
						renderExpr(receiver, scope) + fieldAccessOp(receiver, scope);
				}
				"[&]("
				+ params.join(", ")
				+ ") { return "
				+ target
				+ sanitizeIdentifier(method)
				+ "("
				+ names.join(", ")
				+ "); }";
			case _:
				null;
		};
	}

	static function methodValueExprForExpectedFunction(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || !isCppFunctionType(expectedType))
			return null;
		return switch (expr) {
			case EIdent(name):
				final fn = currentOwnerMethod(name, scope);
				if (fn == null) null; else typedMethodValueLambda(HxFunctionDecl.getIsStatic(fn) ? "" : "this->", sanitizeIdentifier(name), fn, expectedType);
			case EField(receiver, method):
				final ownerType = instanceMethodReceiverClassName(exprCppType(receiver, scope), scope);
				if (ownerType == null || ownerType.length == 0) null; else {
					final fn = classMethodDecl(ownerType, method, false, scope);
					if (fn == null)
						null;
					else {
						final target = switch (receiver) {
							case EThis:
								"this->";
							case _:
								renderExpr(receiver, scope) + fieldAccessOp(receiver, scope);
						}
						typedMethodValueLambda(target, sanitizeIdentifier(method), fn, expectedType);
					}
				}
			case _:
				null;
		};
	}

	static function boundMethodValueExpr(expr:HxExpr, ?scope:CppRenderScope):Null<String> {
		return boundMethodValueExprWithExpectedType(expr, "", scope);
	}

	static function boundMethodValueExprWithExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		return switch (expr) {
			case ECall(EField(receiver, "bind"), boundArgs):
				final binding = methodBindingInfo(receiver, scope);
				if (binding == null) null; else renderBoundMethodValueLambda(binding.targetPrefix, binding.methodName, binding.fn, boundArgs, expectedType,
					scope);
			case _:
				null;
		};
	}

	static function methodBindingInfo(receiver:HxExpr, scope:CppRenderScope):Null<{targetPrefix:String, methodName:String, fn:HxFunctionDecl}> {
		return switch (receiver) {
			case EIdent(name):
				final fn = currentOwnerMethod(name, scope);
				if (fn == null) null; else {
					targetPrefix: HxFunctionDecl.getIsStatic(fn) ? "" : "this->",
					methodName: sanitizeIdentifier(name),
					fn: fn
				};
			case EField(target, method):
				final ownerType = instanceMethodReceiverClassName(exprCppType(target, scope), scope);
				if (ownerType == null || ownerType.length == 0) null; else {
					final fn = classMethodDecl(ownerType, method, false, scope);
					if (fn == null)
						null;
					else {
						final targetPrefix = switch (target) {
							case EThis:
								"this->";
							case _:
								renderExpr(target, scope) + fieldAccessOp(target, scope);
						}
						{
							targetPrefix: targetPrefix,
							methodName: sanitizeIdentifier(method),
							fn: fn
						};
					}
				}
			case _:
				null;
		};
	}

	static function renderBoundMethodValueLambda(targetPrefix:String, methodName:String, fn:HxFunctionDecl, boundArgs:Array<HxExpr>, expectedType:String,
			?scope:CppRenderScope):String {
		final fnArgs = HxFunctionDecl.getArgs(fn);
		final boundCount = boundArgs == null ? 0 : boundArgs.length;
		final expectedArgs = isCppFunctionType(expectedType) ? CppTypeModel.cppFunctionArgTypesFromCppType(expectedType) : [];
		final names = new Array<String>();
		final params = new Array<String>();
		for (i in boundCount...fnArgs.length) {
			final name = sanitizeIdentifier(HxFunctionArg.getName(fnArgs[i]));
			names.push(name);
			final paramIndex = i - boundCount;
			final typeName = paramIndex < expectedArgs.length && expectedArgs[paramIndex].length > 0 ? expectedArgs[paramIndex] : "auto";
			params.push(typeName + " " + name);
		}
		final callArgs = new Array<String>();
		for (i in 0...boundCount)
			callArgs.push(renderExpr(boundArgs[i], scope));
		for (name in names)
			callArgs.push(name);
		final returnType = isCppFunctionType(expectedType) ? cppFunctionReturnTypeFromCppType(expectedType) : "";
		final call = targetPrefix + methodName + "(" + callArgs.join(", ") + ")";
		final body = returnType == "void" ? call + ";" : "return " + call + ";";
		final lambda = "[&](" + params.join(", ") + ") { " + body + " }";
		return isCppFunctionType(expectedType) ? expectedType + "(" + lambda + ")" : lambda;
	}

	static function typedMethodValueLambda(targetPrefix:String, methodName:String, fn:HxFunctionDecl, expectedType:String):String {
		final expectedArgs = CppTypeModel.cppFunctionArgTypesFromCppType(expectedType);
		final fnArgs = HxFunctionDecl.getArgs(fn);
		final names = [
			for (i in 0...fnArgs.length)
				sanitizeIdentifier(HxFunctionArg.getName(fnArgs[i]))
		];
		final params = [
			for (i in 0...names.length) {
				final typeName = i < expectedArgs.length && expectedArgs[i].length > 0 ? expectedArgs[i] : "auto";
				typeName + " " + names[i];
			}
		];
		final call = targetPrefix + methodName + "(" + names.join(", ") + ")";
		final returnType = cppFunctionReturnTypeFromCppType(expectedType);
		final body = returnType == "void" ? call + ";" : "return " + call + ";";
		return expectedType + "([&](" + params.join(", ") + ") { " + body + " })";
	}

	static function macroExpr(expr:HxExpr, wrappers:Array<String>):String {
		return "std::string(" + quoteString(macroExprText(expr, wrappers)) + ")";
	}

	/**
		Lower C++ MVP `macro :Type` quotes to stable printable text.

		C++ does not yet have a target-owned recursive `haxe.macro.ComplexType`
		runtime. Emitting a string mirrors this backend's existing `macro expr`
		quote MVP and supports printer-style upstream probes without generating a
		fake macro runtime class in the emitter.
	**/
	static function macroTypeExpr(typeText:String):String {
		return "std::string(" + quoteString(macroTypeText(typeText)) + ")";
	}

	static function macroTypeText(typeText:String):String {
		var text = StringTools.trim(typeText == null ? "" : typeText);
		if (StringTools.startsWith(text, ":"))
			text = StringTools.trim(text.substr(1));
		return collapseSpaces(StringTools.replace(text, "->", " -> "));
	}

	static function collapseSpaces(value:String):String {
		final out = new StringBuf();
		var pendingSpace = false;
		for (i in 0...value.length) {
			final c = value.charCodeAt(i);
			final isSpace = c == " ".code || c == "\n".code || c == "\t".code || c == "\r".code;
			if (isSpace) {
				pendingSpace = out.length > 0;
			} else {
				if (pendingSpace)
					out.add(" ");
				out.addChar(c);
				pendingSpace = false;
			}
		}
		return out.toString();
	}

	static function macroExprText(expr:HxExpr, wrappers:Array<String>):String {
		var text = macroExprDefText(expr);
		if (wrappers != null) {
			var i = wrappers.length;
			while (i > 0) {
				i--;
				text = switch (wrappers[i]) {
					case "parenthesis":
						"EParenthesis(" + text + ")";
					case "untyped":
						"EUntyped(" + text + ")";
					case other:
						other + "(" + text + ")";
				}
			}
		}
		return text;
	}

	static function macroExprDefText(expr:HxExpr):String {
		return switch (expr) {
			case EString(value):
				"EConst(CString(" + value + "))";
			case EInt(value):
				"EConst(CInt(" + Std.string(value) + "))";
			case EFloat(value):
				"EConst(CFloat(" + Std.string(value) + "))";
			case ENull:
				"EConst(CIdent(null))";
			case EIdent(name):
				"EConst(CIdent(" + name + "))";
			case EField(receiver, field):
				"EField(" + macroExprText(receiver, []) + "," + field + ")";
			case EArrayAccess(receiver, index):
				"EArray(" + macroExprText(receiver, []) + "," + macroExprText(index, []) + ")";
			case EArrayDecl(values):
				"EArrayDecl([" + [for (value in values) macroExprText(value, [])].join(",") + "])";
			case EBinop("in", left, right):
				"EBinop(OpIn," + macroExprText(left, []) + "," + macroExprText(right, []) + ")";
			case EBinop("=>", left, right):
				"EBinop(OpArrow," + macroExprText(left, []) + "," + macroExprText(right, []) + ")";
			case EBinop(op, left, right):
				"EBinop(" + op + "," + macroExprText(left, []) + "," + macroExprText(right, []) + ")";
			case EUnop(op, inner):
				"EUnop(" + op + "," + macroExprText(inner, []) + ")";
			case ECall(callee, args):
				"ECall("
				+ macroExprText(callee, [])
				+ ",["
				+ [for (arg in args) macroExprText(arg, [])].join(",") + "])";
			case EUntyped(inner):
				"EUntyped(" + macroExprText(inner, []) + ")";
			case EMacroExpr(inner, innerWrappers):
				macroExprText(inner, innerWrappers);
			case _:
				"EUnsupported(" + exprKind(expr) + ")";
		};
	}

	static function anonExpr(fieldNames:Array<String>, fieldValues:Array<HxExpr>, ?scope:CppRenderScope):String {
		final struct = anonStruct(fieldNames, fieldValues, scope);
		final values = [
			for (i in 0...struct.fieldNames.length)
				valueExprForExpectedType(fieldValues[i], struct.fieldTypes[i], scope)
		];
		return struct.name + "{" + values.join(", ") + "}";
	}

	static function arrayExpr(elements:Array<HxExpr>, ?scope:CppRenderScope):String {
		final typeName = arrayElementType(elements, scope);
		return arrayExprWithElementType(elements, typeName, scope);
	}

	static function mapLiteralToStringExpr(elements:Array<HxExpr>, ?scope:CppRenderScope):String {
		final typeName = mapLiteralPairCppType(elements, scope);
		return "__hxhx_map_literal_to_string(" + arrayExprWithElementType(elements, typeName, scope) + ")";
	}

	static function isMapLiteralElements(elements:Array<HxExpr>):Bool {
		if (elements == null || elements.length == 0)
			return false;
		for (element in elements) {
			switch (element) {
				case EBinop("=>", _, _):
				case _:
					return false;
			}
		}
		return true;
	}

	static function mapLiteralPairCppType(elements:Array<HxExpr>, ?scope:CppRenderScope):String {
		return switch (elements[0]) {
			case EBinop("=>", key, value):
				"std::pair<"
				+ mapLiteralOperandCppType(key, scope)
				+ ", "
				+ mapLiteralOperandCppType(value, scope)
				+ ">";
			case _:
				"std::pair<std::string, std::string>";
		};
	}

	static function mapLiteralOperandCppType(expr:HxExpr, ?scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		if (explicit.length > 0)
			return explicit;
		final inferred = inferExprCppType(expr, scope);
		if (inferred.length > 0)
			return inferred;
		return isStringLike(expr) ? "std::string" : "std::any";
	}

	static function arrayExprWithElementType(elements:Array<HxExpr>, typeName:String, ?scope:CppRenderScope):String {
		final values = [
			for (element in elements)
				typeName == "std::string" ? stringExpr(element, scope) : renderExpr(element, scope)
		];
		return "std::vector<" + typeName + ">{" + values.join(", ") + "}";
	}

	/**
		Lower the C++ MVP subset of Haxe array comprehensions.

		The result stays expression-position friendly by using an immediately-invoked
		lambda that captures surrounding locals by reference, appends yielded values to
		a `std::vector<T>`, and returns that vector. This deliberately models only the
		backend-owned iterable shapes we can currently render, not the full Haxe
		iterator protocol.
	**/
	static function arrayComprehensionExpr(name:String, iterable:HxExpr, guardExpr:Null<HxExpr>, yieldExpr:HxExpr, ?scope:CppRenderScope):String {
		final local = sanitizeIdentifier(name);
		final hadPreviousLocal = scope != null && scope.localTypes.exists(local);
		final previousLocalType = hadPreviousLocal ? scope.localTypes.get(local) : "";
		final loopElementType = iterableElementType(iterable, scope);
		if (scope != null && loopElementType.length > 0)
			scope.localTypes.set(local, loopElementType);
		final typeName = comprehensionElementType(yieldExpr, scope);
		final out = ["([&]() {", "  std::vector<" + typeName + "> __hxhx_comp_out;"];
		switch (iterable) {
			case ERange(start, end):
				out.push("  for (int "
					+ local
					+ " = "
					+ renderExpr(start, scope)
					+ "; "
					+ local
					+ " < "
					+ renderExpr(end, scope)
					+ "; "
					+ local
					+ "++) {");
			case _:
				out.push("  for (auto " + local + " : " + renderExpr(iterable, scope) + ") {");
		}
		if (guardExpr == null) {
			addComprehensionYieldLines(out, "    ", yieldExpr, scope);
		} else {
			out.push("    if " + cStyleConditionExpr(guardExpr, scope) + " {");
			addComprehensionYieldLines(out, "      ", yieldExpr, scope);
			out.push("    }");
		}
		out.push("  }");
		out.push("  return __hxhx_comp_out;");
		out.push("})()");
		if (scope != null) {
			if (hadPreviousLocal)
				scope.localTypes.set(local, previousLocalType);
			else
				scope.localTypes.remove(local);
		}
		return out.join("\n");
	}

	static function addComprehensionYieldLines(out:Array<String>, indent:String, yieldExpr:HxExpr, ?scope:CppRenderScope):Void {
		switch (yieldExpr) {
			case ECall(EIdent("__hxhx_for_in"), [innerIterable, ELambda([innerName], innerYield), _]):
				final local = sanitizeIdentifier(innerName);
				final renderedIterable = renderExpr(innerIterable, scope);
				final loopElementType = iterableElementType(innerIterable, scope);
				out.push(indent + "for (auto " + local + " : " + renderedIterable + ") {");
				withScopedLocal(scope, local, loopElementType, () -> addComprehensionYieldLines(out, indent + "  ", innerYield, scope));
				out.push(indent + "}");
			case _:
				out.push(indent + "__hxhx_comp_out.push_back(" + renderExpr(yieldExpr, scope) + ");");
		}
	}

	static function arrayElementType(elements:Array<HxExpr>, ?scope:CppRenderScope):String {
		if (isMapLiteralElements(elements))
			return mapLiteralPairCppType(elements, scope);
		for (element in elements) {
			final inferred = inferExprCppType(element, scope);
			if (inferred.length > 0)
				return inferred;
		}
		for (element in elements)
			if (isStringLike(element))
				return "std::string";
		for (element in elements)
			switch (element) {
				case EFloat(_):
					return "double";
				case _: // keep scanning
			}
		for (element in elements)
			switch (element) {
				case EBool(_):
					return "bool";
				case _: // keep scanning
			}
		return "int";
	}

	static function isCppPairType(typeName:String):Bool {
		final clean = StringTools.trim(typeName == null ? "" : typeName);
		return StringTools.startsWith(clean, "std::pair<") && StringTools.endsWith(clean, ">");
	}

	static function cppPairTypeArgs(typeName:String):Array<String> {
		final clean = StringTools.trim(typeName == null ? "" : typeName);
		if (!isCppPairType(clean))
			return [];
		final inner = clean.substr("std::pair<".length, clean.length - "std::pair<".length - 1);
		return splitTopLevelComma(inner).map(arg -> StringTools.trim(arg)).filter(arg -> arg.length > 0);
	}

	static function iterableElementType(iterable:HxExpr, ?scope:CppRenderScope):String {
		final iteratorElement = iteratorProtocolElementType(iterable, scope);
		if (iteratorElement.length > 0)
			return iteratorElement;
		return switch (iterable) {
			case ERange(_, _):
				"int";
			case _:
				cppIterableElementType(exprCppType(iterable, scope), scope);
		};
	}

	static function iteratorProtocolElementType(iterable:HxExpr, ?scope:CppRenderScope):String {
		final iteratorElement = cppIteratorElementType(exprCppType(iterable, scope));
		if (iteratorElement.length > 0)
			return iteratorElement;
		final className = classNameFromCppExprType(exprCppType(iterable, scope), scope);
		if (className == null)
			return "";
		if (!classHasInstanceMethod(className, "hasNext", scope) || !classHasInstanceMethod(className, "next", scope))
			return "";
		final nextType = classMethodCppReturnType(className, "next", false, scope);
		return nextType.length > 0 && nextType != "auto" ? nextType : "auto";
	}

	static function classHasInstanceMethod(className:String, methodName:String, ?scope:CppRenderScope):Bool {
		if (scope == null || className == null || className.length == 0)
			return false;
		final cls = scope.classByName.get(className);
		if (cls == null)
			return false;
		for (fn in HxClassDecl.getFunctions(cls))
			if (HxFunctionDecl.getName(fn) == methodName && !HxFunctionDecl.getIsStatic(fn))
				return true;
		final cleanMethod = sanitizeIdentifier(methodName);
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field))
				continue;
			final cleanField = sanitizeIdentifier(HxFieldDecl.getName(field));
			if (cleanMethod == "get_" + cleanField && HxFieldDecl.getPropertyGet(field) == "get")
				return true;
			if (cleanMethod == "set_" + cleanField && HxFieldDecl.getPropertySet(field) == "set")
				return true;
		}
		return false;
	}

	static function cppIterableElementType(typeName:String, ?scope:CppRenderScope):String {
		if (isCppVectorType(typeName))
			return cppVectorElementType(typeName);
		final listElement = listElementCppType(typeName);
		if (listElement.length > 0)
			return listElement;
		if (typeName == "Array")
			return "std::string";
		return "";
	}

	static function comprehensionElementType(expr:HxExpr, ?scope:CppRenderScope):String {
		switch (expr) {
			case ECall(EIdent("__hxhx_for_in"), [innerIterable, ELambda([innerName], innerYield), _]):
				final local = sanitizeIdentifier(innerName);
				final loopElementType = iterableElementType(innerIterable, scope);
				var nestedType = "";
				withScopedLocal(scope, local, loopElementType, () -> nestedType = comprehensionElementType(innerYield, scope));
				if (nestedType.length > 0)
					return nestedType;
			case _:
		}
		final inferred = inferExprCppType(expr, scope);
		if (inferred.length > 0)
			return inferred;
		if (isStringLike(expr))
			return "std::string";
		return switch (expr) {
			case EFloat(_):
				"double";
			case EBool(_):
				"bool";
			case _:
				"int";
		};
	}

	static function arrayComprehensionElementType(name:String, iterable:HxExpr, yieldExpr:HxExpr, ?scope:CppRenderScope):String {
		final local = sanitizeIdentifier(name);
		final loopElementType = iterableElementType(iterable, scope);
		var elementType = "";
		withScopedLocal(scope, local, loopElementType, () -> elementType = comprehensionElementType(yieldExpr, scope));
		return elementType.length > 0 ? elementType : "int";
	}

	static function isStringLike(expr:HxExpr):Bool {
		return switch (expr) {
			case EString(_) | EEnumValue(_) | EMacroType(_):
				true;
			case ECall(EEnumValue(_), args) if (args == null || args.length == 0):
				true;
			case ECall(EField(EIdent("Std"), "string"), args) if (args.length == 1):
				true;
			case EBinop("+", left, right): isStringLike(left) || isStringLike(right);
			case ETernary(_, thenExpr, elseExpr): isStringLike(thenExpr) && isStringLike(elseExpr);
			case _:
				false;
		};
	}

	static function isSimpleBinaryOp(op:String):Bool {
		return op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">"
			|| op == ">=" || op == "||" || op == "&&" || op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>";
	}

	static function isArithmeticBinaryOp(op:String):Bool {
		return op == "+" || op == "-" || op == "*" || op == "/" || op == "%";
	}

	static function isBoolBinaryOp(op:String):Bool {
		return op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "||" || op == "&&" || op == "is";
	}

	static function isSimpleCompoundAssignmentOp(op:String):Bool {
		return op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%=" || op == "&=" || op == "|=" || op == "^=" || op == "<<=" || op == ">>=";
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
			case SReturn(_, _): "SReturn";
			case SReturnVoid(_): "SReturnVoid";
			case SExpr(expr, _): "SExpr(" + exprKind(expr) + ")";
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
			case EIdent(name): "EIdent(" + name + ")";
			case EField(receiver, field): "EField(" + exprKind(receiver) + "." + field + ")";
			case ECall(callee, _): "ECall(" + exprKind(callee) + ")";
			case EMacroExpr(_, _): "EMacroExpr";
			case EMacroType(_): "EMacroType";
			case ELambda(_, _): "ELambda";
			case EArrayComprehension(_, _, _): "EArrayComprehension";
			case EArrayDecl(_): "EArrayDecl";
			case EArrayAccess(_, _): "EArrayAccess";
			case ERange(_, _): "ERange";
			case EAnon(_, _): "EAnon";
			case EUnop(op, _): "EUnop(" + op + ")";
			case EBinop(op, _, _): "EBinop(" + op + ")";
			case ETernary(_, _, _): "ETernary";
			case ESwitchRaw(_): "ESwitchRaw";
			case ESwitch(_, _, _): "ESwitch";
			case ETryCatchRaw(_): "ETryCatchRaw";
			case ENew(typePath, _): "ENew(" + typePath + ")";
			case ECast(_, _): "ECast";
			case EUntyped(_): "EUntyped";
			case EUnsupported(reason): "EUnsupported(" + reason + ")";
		};
	}

	static function quoteString(value:String):String {
		var out = "\"";
		for (i in 0...value.length) {
			final code = value.charCodeAt(i);
			out += switch (code) {
				case 34: "\\\"";
				case 92: "\\\\";
				case 10: "\\n";
				case 13: "\\r";
				case 9: "\\t";
				case _: String.fromCharCode(code);
			};
		}
		return out + "\"";
	}

	static function sanitizeIdentifier(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charAt(i);
			final ok = (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || (i > 0 && c >= "0" && c <= "9");
			out.add(ok ? c : "_");
		}
		final s = out.toString();
		final first = s.charAt(0);
		if (first >= "0" && first <= "9")
			return "_" + s;
		return switch (s) {
			case "and" | "and_eq" | "auto" | "bitand" | "bitor" | "bool" | "break" | "case" | "catch" | "class" | "compl" | "const" | "continue" | "delete" |
				"do" | "double" | "else" | "false" | "float" | "for" | "if" | "int" | "long" | "namespace" | "new" | "not" | "not_eq" | "nullptr" | "or" |
				"or_eq" | "private" | "public" | "return" | "short" | "static" | "std" | "struct" | "switch" | "this" | "throw" | "true" | "try" | "void" |
				"while" | "xor" | "xor_eq":
				s
				+ "_";
			case _:
				s;
		};
	}

	static function executablePath(outputDir:String, className:String):String {
		return Path.join([outputDir, className]);
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

	static function commandExists(name:String):Bool {
		return Sys.command("sh", ["-c", "command -v " + name + " >/dev/null 2>&1"]) == 0;
	}

	static function cppCompilerCommand():Null<String> {
		for (candidate in ["c++", "g++", "clang++"])
			if (commandExists(candidate))
				return candidate;
		return null;
	}

	static function sanitizeTypePath(path:String):String {
		if (path == null || path.length == 0)
			return "_";
		return sanitizeIdentifier(StringTools.replace(path, ".", "_"));
	}

	static function scopeOwnerIsArrayBackedAbstract(?scope:CppRenderScope):Bool {
		return scope != null && scope.owner != null && CppTypeModel.isArrayBackedAbstractClass(scope.owner);
	}

	static function isArrayBackedAbstractClass(cls:HxClassDecl):Bool {
		return CppTypeModel.isArrayBackedAbstractClass(cls);
	}

	static function isRestSupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(HxClassDecl.getName(cls)) == "Rest" && genericClassTemplateParams(cls).length > 0;
	}

	static function isStdVectorHelperClass(cls:HxClassDecl):Bool {
		return CppTypeModel.isStdVectorHelperClass(cls);
	}

	static function isStdVectorHelperName(name:String):Bool {
		return sanitizeTypePath(typeBaseName(name == null ? "" : name)) == "Vector";
	}

	static function isPrimitiveBackedAbstractClass(cls:HxClassDecl):Bool {
		return CppTypeModel.isPrimitiveBackedAbstractClass(cls);
	}

	static function isStdArrayHelperClass(cls:HxClassDecl):Bool {
		return CppTypeModel.isStdArrayHelperClass(cls);
	}

	static function isPosInfosSupportClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(HxClassDecl.getName(cls)) == "PosInfos";
	}

	static function posInfosFieldCppType(className:String, fieldName:String):String {
		if (sanitizeTypePath(className) != "PosInfos")
			return "";
		return switch (fieldName) {
			case "fileName" | "className" | "methodName":
				"std::string";
			case "lineNumber":
				"int";
			case "customParams":
				"std::vector<std::string>";
			case _:
				"";
		};
	}

	static function lambdaCallReturnCppType(lambdaArgs:Array<String>, body:HxExpr, args:Array<HxExpr>, ?scope:CppRenderScope):String {
		if (lambdaArgs == null || lambdaArgs.length == 0)
			return inferExprCppType(body, scope);
		var result = "";
		function visit(index:Int):Void {
			if (index >= lambdaArgs.length || index >= args.length) {
				result = inferExprCppType(body, scope);
				return;
			}
			final local = sanitizeIdentifier(lambdaArgs[index]);
			var typeName = exprCppType(args[index], scope);
			if (typeName.length == 0)
				typeName = inferExprCppType(args[index], scope);
			withScopedLocal(scope, local, typeName, () -> visit(index + 1));
		}
		visit(0);
		return result;
	}

	static function isPosInfosAnon(fieldNames:Array<String>, fieldValues:Array<HxExpr>):Bool {
		if (fieldNames == null || fieldValues == null || fieldNames.length != 4 || fieldValues.length != 4)
			return false;
		for (name in ["fileName", "lineNumber", "className", "methodName"])
			if (fieldNames.indexOf(name) < 0)
				return false;
		return true;
	}

	static function posInfosCtorArgs(fieldNames:Array<String>, fieldValues:Array<HxExpr>, ?scope:CppRenderScope):Array<String> {
		return [
			posInfosFieldExpr("fileName", fieldNames, fieldValues, scope),
			posInfosFieldExpr("lineNumber", fieldNames, fieldValues, scope),
			posInfosFieldExpr("className", fieldNames, fieldValues, scope),
			posInfosFieldExpr("methodName", fieldNames, fieldValues, scope)
		];
	}

	static function posInfosFieldExpr(name:String, fieldNames:Array<String>, fieldValues:Array<HxExpr>, ?scope:CppRenderScope):String {
		final index = fieldNames.indexOf(name);
		if (index < 0 || index >= fieldValues.length)
			return name == "lineNumber" ? "0" : "std::string()";
		return name == "lineNumber" ? renderExpr(fieldValues[index], scope) : stringExpr(fieldValues[index], scope);
	}

	static function abstractUnderlyingTypeHint(cls:HxClassDecl):Null<String> {
		return CppTypeModel.abstractUnderlyingTypeHint(cls);
	}

	static function scopeOwnerIsHxhxAbstract(scope:CppRenderScope):Bool {
		if (scope == null || scope.owner == null)
			return false;
		for (meta in HxClassDecl.getMetadata(scope.owner))
			if (StringTools.trim(meta) == "__hxhx_abstract")
				return true;
		return false;
	}

	static function hasInstanceField(cls:HxClassDecl, name:String):Bool {
		if (cls == null)
			return false;
		for (field in HxClassDecl.getFields(cls))
			if (!HxFieldDecl.getIsStatic(field) && HxFieldDecl.getName(field) == name)
				return true;
		return false;
	}

	static function structuralTypedefClassForCppType(typeName:String, ?scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null || typeName == null || typeName.length == 0)
			return null;
		final cls = CppTypeModel.structuralTypedefValueClassForTypeHint(typeName, scope,
			{names: scope.classNames, byName: scope.classByName, all: scope.allClasses});
		if (cls == null || HxClassDecl.getFields(cls).length == 0)
			return null;
		return cls;
	}

	static function arrayBackedAbstractValueCppType(cls:HxClassDecl, classLookup:CppClassLookup):String {
		if (genericClassTemplateParams(cls).length > 0)
			return CppTypeModel.arrayBackedAbstractValueCppType(cls, classLookup);
		final underlying = removeTypeHintWhitespace(abstractUnderlyingTypeHint(cls));
		final scope = renderScope(cls, classLookup, "auto");
		if (StringTools.startsWith(underlying, "Array<") && StringTools.endsWith(underlying, ">"))
			return cppTypeHint(underlying, scope, classLookup);
		if (StringTools.startsWith(underlying, "VectorData<") && StringTools.endsWith(underlying, ">"))
			return "std::vector<" + cppTypeHint(genericTypeHintArg(underlying), scope, classLookup) + ">";
		return "std::vector<std::string>";
	}

	static function primitiveAbstractUnderlyingCppType(cls:HxClassDecl):Null<String> {
		return CppTypeModel.primitiveAbstractUnderlyingCppType(cls);
	}

	static function primitiveTypeHintCppType(typeHint:String):Null<String> {
		return CppTypeModel.primitiveTypeHintCppType(typeHint);
	}

	static function knownPrimitiveBackedAbstractCppType(typeHint:String):Null<String> {
		return CppTypeModel.knownPrimitiveBackedAbstractCppType(typeHint);
	}

	static function primitiveBackedAbstractCppTypeForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		return CppTypeModel.primitiveBackedAbstractCppTypeForTypeHint(typeHint, scope, classLookup);
	}

	static function arrayBackedAbstractNameForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		return CppTypeModel.arrayBackedAbstractNameForTypeHint(typeHint, scope, classLookup);
	}

	static function lookupClassForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		return CppTypeModel.lookupClassForTypeHint(typeHint, scope, classLookup);
	}

	static function isArrayLikeTypeHint(typeHint:String):Bool {
		return CppTypeModel.isArrayLikeTypeHint(typeHint);
	}

	static function isStdArrayTypePath(typeHint:String):Bool {
		return CppTypeModel.isStdArrayTypePath(typeHint);
	}

	static function isIterableTypeHint(typeHint:String):Bool {
		return CppTypeModel.isIterableTypeHint(typeHint);
	}

	static function genericTypeHintArg(typeHint:String):String {
		return CppTypeModel.genericTypeHintArg(typeHint);
	}

	static function genericTypeHintArgs(typeHint:String):Array<String> {
		return CppTypeModel.genericTypeHintArgs(typeHint);
	}

	static function cppTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (CppTypeModel.isStaleNullPointerTypeHint(hint))
			return "std::any";
		final nullArg = CppTypeModel.nullTypeHintArg(hint);
		if (nullArg != null)
			return cppNullableTypeHint(nullArg, scope, classLookup);
		if (CppTypeModel.isBareNullTypeHint(hint))
			return "std::any";
		final primitiveAbstractType = primitiveBackedAbstractCppTypeForTypeHint(hint, scope, classLookup);
		if (primitiveAbstractType != null)
			return primitiveAbstractType;
		final abstractName = arrayBackedAbstractNameForTypeHint(hint, scope, classLookup);
		if (abstractName != null)
			return abstractName;
		if (scope != null && scope.owner != null && isGenericTypeParamHint(hint, scope.owner))
			return cppTypeParamName(genericTypeParamName(hint), scope);
		if (isStructuralTypeHint(hint)) {
			final struct = structuralTypeHintStruct(hint, scope, classLookup);
			if (struct != null)
				return struct.name;
		}
		final structuralTypedef = renderedStructuralTypedefTypeName(hint, scope, classLookup);
		if (structuralTypedef != null)
			return structuralTypedef;
		final renderedCpp = renderedCppContainerTypeName(hint, scope, classLookup);
		if (renderedCpp != null)
			return renderedCpp;
		final scopedGenericClass = scopedRawGenericClassTypeName(hint, scope);
		if (scopedGenericClass != null)
			return "std::shared_ptr<" + scopedGenericClass + ">";
		if (CppTypeModel.isIteratorTypeHint(hint))
			return "std::shared_ptr<__hxhx_iterator<" + cppTypeHint(genericTypeHintArg(hint), scope, classLookup) + ">>";
		if (isArrayLikeTypeHint(hint) || isIterableTypeHint(hint))
			return "std::vector<" + cppTypeHint(genericTypeHintArg(hint), scope, classLookup) + ">";
		if (isFunctionTypeHint(hint))
			return cppFunctionTypeHint(hint, scope, classLookup);
		if (isCppPointerTypeHint(hint))
			return CppTypeModel.cppTypeHint(hint, scope, classLookup);
		final args = genericTypeHintArgs(hint);
		if (args.length > 0) {
			final cls = lookupClassForTypeHint(hint, scope, classLookup);
			final rendered = cls == null ? "" : renderedClassName(cls, lookupForScope(scope, classLookup));
			final hintBase = sanitizeTypePath(typeBaseName(hint));
			final base = cls != null
				&& rendered.length > 0
				&& CppTypeModel.structuralTypedefValueClassForTypeHint(hint, scope, lookupForScope(scope, classLookup)) == null ? rendered : hintBase;
			if (scopeHasClass(scope, base)) {
				if (genericClassTypeParamsForName(base, scope).length > 0)
					return "std::shared_ptr<" + cppClassTemplateTypeName(hint, scope, classLookup) + ">";
				if (isEnumCarrierClassName(base, scope))
					return CppMacroExpr.CPP_TYPE;
				return "std::shared_ptr<" + base + ">";
			}
		}
		final cls = lookupClassForTypeHint(hint, scope, classLookup);
		if (cls != null) {
			final rendered = renderedClassName(cls, lookupForScope(scope, classLookup));
			if (rendered != sanitizeTypePath(typeBaseName(hint))
				&& CppTypeModel.structuralTypedefValueClassForTypeHint(hint, scope, lookupForScope(scope, classLookup)) == null)
				return "std::shared_ptr<" + rendered + ">";
		}
		return CppTypeModel.cppTypeHint(hint, scope, classLookup);
	}

	static function renderedStructuralTypedefTypeName(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final lookup = lookupForScope(scope, classLookup);
		final cls = CppTypeModel.structuralTypedefValueClassForTypeHint(typeHint, scope, lookup);
		if (cls == null)
			return null;
		return cppClassTemplateTypeName(typeHint, scope, lookup);
	}

	static function renderedCppContainerTypeName(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		for (prefix in ["std::shared_ptr", "std::vector", "std::optional"]) {
			final inner = templateInnerForPrefix(hint, prefix);
			if (inner != null)
				return prefix + "<" + renderedCppTypeInner(inner, scope, classLookup) + ">";
		}
		return null;
	}

	static function renderedCppTypeInner(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final container = renderedCppContainerTypeName(hint, scope, classLookup);
		if (container != null)
			return container;
		final args = genericTypeHintArgs(hint);
		final lookup = lookupForScope(scope, classLookup);
		final cls = lookupClassForTypeHint(hint, scope, lookup);
		if (cls == null)
			return hint;
		if (args.length > 0)
			return cppClassTemplateTypeName(hint, scope, lookup);
		return renderedClassName(cls, lookup);
	}

	static function templateInnerForPrefix(typeHint:String, prefix:String):Null<String> {
		final open = prefix.length;
		if (!StringTools.startsWith(typeHint, prefix + "<") || !StringTools.endsWith(typeHint, ">"))
			return null;
		return typeHint.substr(open + 1, typeHint.length - open - 2);
	}

	static function isEnumCarrierClassName(className:String, ?scope:CppRenderScope):Bool {
		if (scope == null || className == null || className.length == 0)
			return false;
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return false;
		for (field in HxClassDecl.getFields(cls))
			if (HxFieldDecl.getIsStatic(field) && sanitizeIdentifier(HxFieldDecl.getName(field)) == "__hx_is_enum")
				return true;
		return false;
	}

	static function dynamicGenericWildcardCppTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final args = genericTypeHintArgs(hint);
		if (args.length == 0)
			return "";
		if (isArrayLikeTypeHint(hint) || isIterableTypeHint(hint) || CppTypeModel.isIteratorTypeHint(hint))
			return "";
		final base = sanitizeTypePath(typeBaseName(hint));
		if (!scopeHasClass(scope, base) || genericClassTypeParamsForName(base, scope).length == 0)
			return "";
		var hasWildcard = false;
		final renderedArgs = [
			for (arg in args) {
				if (isDynamicLikeTypeHint(arg)) {
					hasWildcard = true;
					cppTypeParamName("TDynamic", scope);
				} else {
					final nested = dynamicGenericWildcardCppTypeHint(arg, scope, classLookup);
					nested.length > 0 ? nested : cppTypeHint(arg, scope, classLookup);
				}
			}
		];
		return hasWildcard ? "std::shared_ptr<" + base + "<" + renderedArgs.join(", ") + ">>" : "";
	}

	static function functionTypePartHint(part:String):String {
		return CppTypeModel.functionArgTypePartType(part);
	}

	static function cppReturnTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final raw = StringTools.trim(typeHint == null ? "" : typeHint);
		if (CppTypeModel.isStaleNullPointerTypeHint(raw))
			return "std::any";
		if (CppTypeModel.isBareNullTypeHint(raw))
			return "std::any";
		final hint = CppTypeModel.unwrapNullTypeHint(raw);
		if (isStructuralTypeHint(hint))
			return "auto";
		final scopedGenericClass = scopedRawGenericClassTypeName(hint, scope);
		if (scopedGenericClass != null)
			return "std::shared_ptr<" + scopedGenericClass + ">";
		return cppTypeHint(raw, scope, classLookup);
	}

	static function isCppPointerTypeHint(typeHint:String):Bool {
		return switch (sanitizeTypePath(typeBaseName(typeHint == null ? "" : typeHint))) {
			case "RawConstPointer" | "ConstPointer" | "RawPointer" | "Pointer":
				true;
			case _:
				false;
		};
	}

	static function scopedRawGenericClassTypeName(typeHint:String, ?scope:CppRenderScope):Null<String> {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0 || hint.indexOf("<") >= 0 || scope == null)
			return null;
		final className = sanitizeTypePath(typeBaseName(hint));
		final templateArgs = scopedTemplateArgsForClass(className, scope);
		return templateArgs.length == 0 ? null : className + "<" + templateArgs.join(", ") + ">";
	}

	static function typeIntrinsicReturnCppType(method:String, args:Array<HxExpr>):String {
		return switch (method) {
			case "getClass" | "getSuperClass" if (args.length == 1):
				"std::shared_ptr<Class>";
			case "resolveClass" if (args.length == 1):
				"std::shared_ptr<Class>";
			case "getEnum" if (args.length == 1):
				"std::shared_ptr<Enum>";
			case "resolveEnum" if (args.length == 1):
				"std::shared_ptr<Enum>";
			case "createEnum" | "createEnumIndex" if (args.length == 2 || args.length == 3):
				"std::shared_ptr<EnumValue>";
			case "enumEq" if (args.length == 2):
				"bool";
			case "getClassName" | "getEnumName" | "typeof" if (args.length == 1):
				"std::string";
			case "getClassFields" | "getInstanceFields" | "getEnumConstructs" if (args.length == 1):
				"std::vector<std::string>";
			case _:
				"";
		};
	}

	static function isDynamicLikeTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return hint == "Dynamic" || hint == "Any" || CppTypeModel.isGenericDynamicLikeTypeHint(hint);
	}

	static function copyStringMap(values:haxe.ds.StringMap<String>):haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		if (values != null)
			for (key in values.keys())
				out.set(key, values.get(key));
		return out;
	}

	static function copyNestedStringMap(values:haxe.ds.StringMap<haxe.ds.StringMap<String>>):haxe.ds.StringMap<haxe.ds.StringMap<String>> {
		final out = new haxe.ds.StringMap<haxe.ds.StringMap<String>>();
		if (values != null)
			for (key in values.keys())
				out.set(key, copyStringMap(values.get(key)));
		return out;
	}

	static function restoreNestedStringMap(target:haxe.ds.StringMap<haxe.ds.StringMap<String>>, saved:haxe.ds.StringMap<haxe.ds.StringMap<String>>):Void {
		final stale = [for (key in target.keys()) if (!saved.exists(key)) key];
		for (key in stale)
			target.remove(key);
		for (key in saved.keys())
			target.set(key, copyStringMap(saved.get(key)));
	}

	static function copyBoolMap(values:haxe.ds.StringMap<Bool>):haxe.ds.StringMap<Bool> {
		final out = new haxe.ds.StringMap<Bool>();
		if (values != null)
			for (key in values.keys())
				out.set(key, values.get(key));
		return out;
	}

	static function boolMapHasEntries(values:haxe.ds.StringMap<Bool>):Bool {
		return values != null && values.iterator().hasNext();
	}

	static function countStringMap<T>(values:haxe.ds.StringMap<T>):Int {
		if (values == null)
			return 0;
		var count = 0;
		for (_ in values.keys())
			count++;
		return count;
	}

	static function summarizeStringValueMap(values:haxe.ds.StringMap<String>, limit:Int = 8):String {
		if (values == null)
			return "";
		final entries = new Array<String>();
		for (key in values.keys())
			entries.push(key + ":" + values.get(key));
		entries.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		if (entries.length <= limit)
			return entries.join(",");
		final kept = entries.slice(0, limit);
		kept.push("...+" + Std.string(entries.length - limit));
		return kept.join(",");
	}

	static function stringMapStableKey(values:haxe.ds.StringMap<String>):String {
		if (values == null)
			return "";
		final entries = new Array<String>();
		for (key in values.keys())
			entries.push(key + ":" + values.get(key));
		entries.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		return entries.join(",");
	}

	static function summarizeBoolValueMap(values:haxe.ds.StringMap<Bool>, limit:Int = 8):String {
		if (values == null)
			return "";
		final entries = new Array<String>();
		for (key in values.keys())
			entries.push(key + ":" + (values.get(key) ? "true" : "false"));
		entries.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		if (entries.length <= limit)
			return entries.join(",");
		final kept = entries.slice(0, limit);
		kept.push("...+" + Std.string(entries.length - limit));
		return kept.join(",");
	}

	static function copyIntMap(values:haxe.ds.StringMap<Int>):haxe.ds.StringMap<Int> {
		final out = new haxe.ds.StringMap<Int>();
		if (values != null)
			for (key in values.keys())
				out.set(key, values.get(key));
		return out;
	}

	static function setAssignedArgTypeOverride(scope:CppRenderScope, local:String, typeName:String):Void {
		if (scope == null || local == null || local.length == 0 || typeName == null || typeName.length == 0)
			return;
		final existing = scope.argTypeOverrides.get(local);
		final selected = existing != null && existing.length > 0 && existing != typeName ? "std::any" : typeName;
		scope.argTypeOverrides.set(local, selected);
		scope.localTypes.set(local, selected);
	}

	static function isTypeErasedValueHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Type")
			return false;
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return (method == "getClass" || method == "getEnum") && HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function isTypeToolsTraversalHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "TypeTools")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "map" | "iter":
				HxFunctionDecl.getArgs(fn).length == 2;
			case _:
				false;
		};
	}

	static function isUtestCallbackHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (ownerName) {
			case "Notifier": method == "remove" && HxFunctionDecl.getArgs(fn).length == 1;
			case "ResultStats": method == "unwire" && HxFunctionDecl.getArgs(fn).length == 1;
			case _:
				false;
		};
	}

	static function isUtestResultAggregationHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (ownerName) {
			case "ClassResult":
				switch (method) {
					case "get" | "exists" | "methodNames":
						true;
					case _:
						false;
				}
			case "PackageResult":
				switch (method) {
					case "addResult" | "existsPackage" | "existsClass" | "getPackage" | "getClass" | "classNames" | "packageNames" | "createFixture" |
						"getOrCreateClass" | "getOrCreatePackage":
						true;
					case _:
						false;
				}
			case "ResultAggregator":
				switch (method) {
					case "getOrCreateClass" | "createFixture" | "progress":
						true;
					case _:
						false;
				}
			case "PlainTextReport":
				switch (method) {
					case "setHandler" | "start" | "addHeader" | "getResults" | "complete" | "hasHeader" | "skipResult":
						true;
					case _:
						false;
				}
			case _:
				false;
		};
	}

	static function isCppLibReportHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null)
			return false;
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		return switch (ownerName) {
			case "Lib":
				switch (method) {
					case "load" | "unloadAllLibraries" | "_loadPrime" | "loadLazy" | "do_rethrow" | "rethrow" | "stringReference" | "pushDllSearchPath" |
						"getDllExtension" | "getBinDirectory" | "bytesReference" | "print" | "haxeToNeko" | "nekoToHaxe" | "println" | "setFloatFormat":
						true;
					case _:
						false;
				}
			case "Report":
				method == "create";
			case "ReportTools": method == "hasHeader" || method == "skipResult" || method == "hasOutput";
			case _:
				false;
		};
	}

	static function isCppReportSupportClass(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		return switch (sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls)))) {
			case "Report" | "PrintReport":
				true;
			case _:
				false;
		};
	}

	static function renderCppReportSupportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return switch (sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls)))) {
			case "Report":
				renderCppReportClass(cls, classLookup);
			case "PrintReport":
				renderCppPrintReportClass(cls, classLookup);
			case _:
				[];
		};
	}

	static function renderCppReportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final out = [
			"struct Report {",
			"  std::shared_ptr<Runner> runner = nullptr;",
			"  std::string displayHeader = std::string();",
			"  std::string displaySuccessResults = std::string();",
			"  Report() {}",
			"  Report(std::shared_ptr<Runner> runner) : runner(runner) {}"
		];
		for (fn in HxClassDecl.getFunctions(cls))
			if (HxFunctionDecl.getName(fn) != "new")
				for (line in renderHelperMethod(fn, cls, classLookup))
					out.push(line);
		out.push("};");
		return out;
	}

	static function renderCppPrintReportClass(cls:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final out = [
			"struct PrintReport : public PlainTextReport {",
			"  PrintReport(std::shared_ptr<Runner> runner) : PlainTextReport(runner, [](std::shared_ptr<PlainTextReport> report) { (void)report; }) {",
			"    this->newline = \"\\n\";",
			"    this->indent = \"  \";",
			"  }"
		];
		for (fn in HxClassDecl.getFunctions(cls)) {
			final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
			if (method == "new")
				continue;
			switch (method) {
				case "_handler":
					out.push("  void _handler(std::shared_ptr<PlainTextReport> report) {");
					out.push("    (void)report;");
					out.push("  }");
				case "_trace" | "_print":
					final scope = renderScope(cls, classLookup, "void");
					prepareFunctionSignatureScope(scope, fn);
					out.push("  void " + method + "(" + renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope) + ") {");
					for (arg in HxFunctionDecl.getArgs(fn))
						out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
					out.push("  }");
				case _:
					for (line in renderHelperMethod(fn, cls, classLookup))
						out.push(line);
			}
		}
		out.push("};");
		return out;
	}

	static function isTypeToolsFindFieldHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "TypeTools")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "findField" && HxFunctionDecl.getArgs(fn).length >= 2;
	}

	static function isExprToolsHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || !HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "ExprTools")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "toString" | "getValue":
				HxFunctionDecl.getArgs(fn).length == 1;
			case "iter" | "map":
				HxFunctionDecl.getArgs(fn).length == 2;
			case _:
				false;
		};
	}

	static function isPrinterComplexTypeHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printComplexType" && HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function renderPrinterComplexTypeHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterFieldHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printField" && HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function renderPrinterFieldHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterTypeParamFunctionHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "printTypeParamDecl" | "printFunctionArg" | "printFunction":
				HxFunctionDecl.getArgs(fn).length >= 1;
			case _:
				false;
		};
	}

	static function renderPrinterTypeParamFunctionHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterVarObjectExprHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return switch (sanitizeIdentifier(HxFunctionDecl.getName(fn))) {
			case "printVar" | "printObjectFieldKey" | "printObjectField" | "printExpr":
				HxFunctionDecl.getArgs(fn).length == 1;
			case _:
				false;
		};
	}

	static function renderPrinterVarObjectExprHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printExpr" ? renderPrinterNeutralVoidHelper(fn, owner,
			classLookup) : renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterTypeDefinitionHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printTypeDefinition" && HxFunctionDecl.getArgs(fn).length >= 1;
	}

	static function renderPrinterTypeDefinitionHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterFieldDelimiterHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printFieldWithDelimiter" && HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function renderPrinterFieldDelimiterHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function isPrinterExprPositionsHelper(fn:HxFunctionDecl, owner:HxClassDecl):Bool {
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return false;
		if (sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner))) != "Printer")
			return false;
		return sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "printExprWithPositions" && HxFunctionDecl.getArgs(fn).length == 1;
	}

	static function renderPrinterExprPositionsHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		return renderPrinterNeutralStringHelper(fn, owner, classLookup);
	}

	static function renderPrinterNeutralStringHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final scope = renderScope(owner, classLookup, "std::string");
		prepareFunctionSignatureScope(scope, fn);
		final out = ["  std::string "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {"];
		for (arg in HxFunctionDecl.getArgs(fn))
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		out.push("    return std::string();");
		out.push("  }");
		return out;
	}

	static function renderPrinterNeutralVoidHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final scope = renderScope(owner, classLookup, "void");
		prepareFunctionSignatureScope(scope, fn);
		final out = ["  void "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {"];
		for (arg in HxFunctionDecl.getArgs(fn))
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		out.push("  }");
		return out;
	}

	static function renderTypeToolsFindFieldHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final out = ["  static "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "("
			+ renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope)
			+ ") {"];
		for (arg in HxFunctionDecl.getArgs(fn))
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (returnType != "void")
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		out.push("  }");
		return out;
	}

	static function renderTypeToolsTraversalHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final firstArg = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final secondArg = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {",
			"    (void)" + secondArg + ";"
		];
		if (method == "map" && returnType != "void") {
			out.push("    return " + firstArg + ";");
		} else {
			out.push("    (void)" + firstArg + ";");
			if (returnType != "void")
				out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function renderExprToolsHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = method == "getValue" ? "std::any" : cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = [
			"  static " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"
		];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (method == "map" && returnType != "void") {
			out.push("    return " + sanitizeIdentifier(HxFunctionArg.getName(args[0])) + ";");
		} else if (returnType != "void") {
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function renderUtestCallbackHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final out = ["  " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (method == "remove" && returnType != "void") {
			out.push("    return " + sanitizeIdentifier(HxFunctionArg.getName(args[0])) + ";");
		} else if (returnType != "void") {
			out.push("    return " + cppDefaultValue(returnType, scope) + ";");
		}
		out.push("  }");
		return out;
	}

	static function renderUtestResultAggregationHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = utestResultAggregationReturnType(ownerName, method);
		final templateArg = utestResultAggregationTemplateArg(ownerName, method, HxFunctionDecl.getArgs(fn));
		if (templateArg != null)
			return renderUtestTemplatedNeutralHelper(fn, owner, classLookup, returnType, templateArg);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  " + returnType + " " + method + "(" + renderFunctionArgs(args, scope) + ") {"];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (returnType == "std::vector<std::string>") {
			out.push("    return std::vector<std::string>();");
		} else if (returnType == "bool") {
			out.push("    return false;");
		} else if (returnType == "std::string") {
			out.push("    return std::string();");
		} else if (returnType != "void") {
			final refArg = findFunctionArgByName(args, "ref");
			if (method == "getOrCreatePackage" && refArg != null) {
				out.push("    return " + sanitizeIdentifier(HxFunctionArg.getName(refArg)) + ";");
			} else {
				out.push("    return nullptr;");
			}
		}
		out.push("  }");
		return out;
	}

	static function utestResultAggregationReturnType(ownerName:String, method:String):String {
		return switch (sanitizeTypePath(typeBaseName(ownerName == null ? "" : ownerName)) + "." + sanitizeIdentifier(method == null ? "" : method)) {
			case "ClassResult.get":
				"std::shared_ptr<FixtureResult>";
			case "ClassResult.exists" | "PackageResult.existsPackage" | "PackageResult.existsClass":
				"bool";
			case "ClassResult.methodNames" | "PackageResult.classNames" | "PackageResult.packageNames":
				"std::vector<std::string>";
			case "PackageResult.getPackage" | "PackageResult.getOrCreatePackage":
				"std::shared_ptr<PackageResult>";
			case "PackageResult.getClass" | "PackageResult.getOrCreateClass" | "ResultAggregator.getOrCreateClass":
				"std::shared_ptr<ClassResult>";
			case "PackageResult.createFixture" | "ResultAggregator.createFixture":
				"std::shared_ptr<FixtureResult>";
			case "PlainTextReport.getResults":
				"std::string";
			case "PlainTextReport.hasHeader" | "PlainTextReport.skipResult":
				"bool";
			case _:
				"void";
		};
	}

	static function utestResultAggregationTemplateArg(ownerName:String, method:String, args:Array<HxFunctionArg>):Null<String> {
		if (args.length != 1)
			return null;
		return switch (ownerName + "." + method) {
			case "ResultAggregator.progress":
				"TProgress";
			case "PlainTextReport.start":
				"TStart";
			case _:
				null;
		};
	}

	static function renderUtestTemplatedNeutralHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup, returnType:String,
			templateArg:String):Array<String> {
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final argName = sanitizeIdentifier(HxFunctionArg.getName(HxFunctionDecl.getArgs(fn)[0]));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final out = [
			"  template<typename " + templateArg + ">",
			"  " + returnType + " " + method + "(" + templateArg + " " + argName + ") {",
			"    (void)" + argName + ";"
		];
		if (returnType == "std::string")
			out.push("    return std::string();");
		else if (returnType == "bool")
			out.push("    return false;");
		else if (returnType != "void")
			out.push("    return nullptr;");
		out.push("  }");
		return out;
	}

	static function renderCppLibReportHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final returnType = switch (ownerName + "." + method) {
			case "Lib.unloadAllLibraries":
				"int";
			case "Lib.bytesReference":
				"std::shared_ptr<Bytes>";
			case "Lib.print" | "Lib.println" | "Lib.setFloatFormat" | "Lib.do_rethrow" | "Lib.rethrow":
				"void";
			case "Report.create":
				"std::shared_ptr<IReport<std::string>>";
			case "ReportTools.hasHeader" | "ReportTools.skipResult" | "ReportTools.hasOutput":
				"bool";
			case _:
				"std::string";
		};
		if (ownerName == "ReportTools")
			return renderCppReportToolsHelper(fn, owner, classLookup, returnType);
		final scope = renderScope(owner, classLookup, returnType);
		prepareFunctionSignatureScope(scope, fn);
		final args = HxFunctionDecl.getArgs(fn);
		final out = ["  "
			+ (HxFunctionDecl.getIsStatic(fn) ? "static " : "")
			+ returnType
			+ " "
			+ method
			+ "("
			+ renderFunctionArgs(args, scope)
			+ ") {"];
		for (arg in args)
			out.push("    (void)" + sanitizeIdentifier(HxFunctionArg.getName(arg)) + ";");
		if (returnType == "int") {
			out.push("    return 0;");
		} else if (returnType == "bool") {
			out.push("    return false;");
		} else if (returnType == "std::string") {
			out.push("    return std::string();");
		} else if (returnType != "void") {
			out.push("    return nullptr;");
		}
		out.push("  }");
		return out;
	}

	static function renderCppReportToolsHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup, returnType:String):Array<String> {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final args = HxFunctionDecl.getArgs(fn);
		final statsType = args.length > 1 ? cppFunctionArgType(args[1], renderScope(owner, classLookup, returnType)) : "std::shared_ptr<ResultStats>";
		final out = ["  template<typename TReport>",
			"  static "
			+ returnType
			+ " "
			+ method
			+ "(TReport report, "
			+ statsType
			+ " stats"
			+ (method == "skipResult" ? ", bool isOk" : "")
			+ ") {",
			"    (void)report;",
			"    (void)stats;"
		];
		if (method == "skipResult")
			out.push("    (void)isOk;");
		out.push("    return false;");
		out.push("  }");
		return out;
	}

	static function findFunctionArgByName(args:Array<HxFunctionArg>, name:String):Null<HxFunctionArg> {
		final wanted = sanitizeIdentifier(name);
		for (arg in args)
			if (sanitizeIdentifier(HxFunctionArg.getName(arg)) == wanted)
				return arg;
		return null;
	}

	static function renderTypeErasedValueHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final returnType = cppFunctionReturnType(fn, owner, classLookup);
		final argName = sanitizeIdentifier(HxFunctionArg.getName(HxFunctionDecl.getArgs(fn)[0]));
		final scope = renderScope(owner, classLookup, returnType);
		scope.localTypes.set(argName, "TValue");
		scope.localNames.set(argName, argName);
		scope.localNameCounts.set(argName, 1);
		final out = ["  template<typename TValue>",
			"  static "
			+ returnType
			+ " "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "(const TValue& "
			+ argName
			+ ") {"];
		for (line in renderFunctionBody(HxFunctionDecl.getBody(fn), "    ", scope))
			out.push(line);
		out.push("  }");
		return out;
	}

	static function functionReturnsLambda(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		for (stmt in HxFunctionDecl.getBody(fn))
			if (stmtReturnsLambda(stmt))
				return true;
		return false;
	}

	static function functionReturnsEnumMetadataCtor(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		for (stmt in HxFunctionDecl.getBody(fn))
			if (stmtReturnsEnumMetadataCtor(stmt))
				return true;
		return false;
	}

	static function stmtReturnsLambda(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SReturn(ELambda(_, _), _):
				true;
			case SBlock(stmts, _):
				var found = false;
				for (s in stmts)
					if (stmtReturnsLambda(s))
						found = true;
				found;
			case SIf(_, thenBranch, elseBranch, _): stmtReturnsLambda(thenBranch) || (elseBranch != null && stmtReturnsLambda(elseBranch));
			case _:
				false;
		};
	}

	static function stmtReturnsEnumMetadataCtor(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SReturn(expr, _):
				enumMetadataCtorStringExpr(expr) != null;
			case SBlock(stmts, _):
				var found = false;
				for (s in stmts)
					if (stmtReturnsEnumMetadataCtor(s))
						found = true;
				found;
			case SIf(_, thenBranch, elseBranch, _): stmtReturnsEnumMetadataCtor(thenBranch) || (elseBranch != null && stmtReturnsEnumMetadataCtor(elseBranch));
			case _:
				false;
		};
	}

	static function functionReturnsErasedDynamicValue(fn:HxFunctionDecl, ?scope:CppRenderScope):Bool {
		if (fn == null)
			return false;
		final key = functionSignatureKeyForScope(scope, fn);
		if (erasedDynamicReturnCache.exists(key))
			return erasedDynamicReturnCache.get(key);
		if (erasedDynamicReturnStack.exists(key))
			return false;
		erasedDynamicReturnStack.set(key, true);
		var found = false;
		final erasedLocals = new haxe.ds.StringMap<Bool>();
		for (stmt in HxFunctionDecl.getBody(fn)) {
			if (stmtReturnsErasedDynamicValue(stmt, scope, erasedLocals)) {
				found = true;
				break;
			}
		}
		erasedDynamicReturnStack.remove(key);
		erasedDynamicReturnCache.set(key, found);
		return found;
	}

	static function stmtReturnsErasedDynamicValue(stmt:HxStmt, ?scope:CppRenderScope, ?erasedLocals:haxe.ds.StringMap<Bool>):Bool {
		return switch (stmt) {
			case SVar(name, _, init, _):
				if (init != null && exprReturnsErasedDynamicValue(init, scope, erasedLocals) && erasedLocals != null)
					erasedLocals.set(sanitizeIdentifier(name), true);
				false;
			case SReturn(expr, _):
				exprReturnsErasedDynamicValue(expr, scope, erasedLocals);
			case SBlock(stmts, _):
				var found = false;
				for (s in stmts)
					if (stmtReturnsErasedDynamicValue(s, scope, erasedLocals))
						found = true;
				found;
			case SIf(_, thenBranch, elseBranch, _): stmtReturnsErasedDynamicValue(thenBranch, scope,
					erasedLocals) || (elseBranch != null && stmtReturnsErasedDynamicValue(elseBranch, scope, erasedLocals));
			case SWhile(cond, body, _): exprReturnsErasedDynamicValue(cond, scope, erasedLocals) || stmtReturnsErasedDynamicValue(body, scope, erasedLocals);
			case SDoWhile(body, cond, _): stmtReturnsErasedDynamicValue(body, scope, erasedLocals) || exprReturnsErasedDynamicValue(cond, scope, erasedLocals);
			case SSwitch(scrutinee, _, bodies, _):
				var found = exprReturnsErasedDynamicValue(scrutinee, scope, erasedLocals);
				for (body in bodies)
					if (stmtReturnsErasedDynamicValue(body, scope, erasedLocals))
						found = true;
				found;
			case STry(tryBody, catches, _):
				var found = stmtReturnsErasedDynamicValue(tryBody, scope, erasedLocals);
				for (c in catches)
					if (stmtReturnsErasedDynamicValue(c.body, scope, erasedLocals))
						found = true;
				found;
			case _:
				false;
		};
	}

	static function exprReturnsErasedDynamicValue(expr:HxExpr, ?scope:CppRenderScope, ?erasedLocals:haxe.ds.StringMap<Bool>):Bool {
		return switch (expr) {
			case EAnon(_, _):
				enumMetadataCtorStringExpr(expr, scope) == null;
			case EArrayDecl(_) | EArrayComprehension(_, _, _, _):
				true;
			case EIdent(name):
				final local = sanitizeIdentifier(name);
				final typeName = scope == null ? "" : scope.localTypes.get(local);
					(erasedLocals != null && erasedLocals.exists(local))
					|| typeName == "std::any"
					|| typeName == "std::vector<std::any>"
					|| isCppAnonStructType(typeName);
			case ECall(ELambda(lambdaArgs, body), args):
				final lambdaLocals = erasedLocals == null ? null : copyBoolMap(erasedLocals);
				if (lambdaLocals != null) {
					final count = lambdaArgs.length < args.length ? lambdaArgs.length : args.length;
					for (i in 0...count)
						if (exprReturnsErasedDynamicValue(args[i], scope, erasedLocals))
							lambdaLocals.set(sanitizeIdentifier(lambdaArgs[i]), true);
				}
				exprReturnsErasedDynamicValue(body, scope, lambdaLocals);
			case ECall(EIdent(name), args)
				if ((name == "__hxhx_for_in" || name == "__hxhx_for_key_value" || name == "__hxhx_while" || name == "__hxhx_try")
					&& args.length >= 3):
				exprReturnsErasedDynamicValue(args[2], scope, erasedLocals);
			case ECall(EField(_, "map"), _):
				true;
			case ECall(EIdent(name), _):
				sameOwnerCallReturnsErasedDynamicValue(name, scope);
			case ECall(EField(receiver, method), _):
				memberCallReturnsErasedDynamicValue(receiver, method, scope);
			case ETernary(_, thenExpr, elseExpr): exprReturnsErasedDynamicValue(thenExpr, scope,
					erasedLocals) || exprReturnsErasedDynamicValue(elseExpr, scope, erasedLocals);
			case ESwitch(_, _, exprs):
				var found = false;
				for (value in exprs)
					if (exprReturnsErasedDynamicValue(value, scope, erasedLocals))
						found = true;
				found;
			case ESwitchRaw(_):
				true;
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				exprReturnsErasedDynamicValue(inner, scope, erasedLocals);
			case _:
				false;
		};
	}

	static function sameOwnerCallReturnsErasedDynamicValue(name:String, ?scope:CppRenderScope):Bool {
		final fn = currentOwnerMethod(name, scope);
		if (fn == null || !isDynamicLikeTypeHint(HxFunctionDecl.getReturnTypeHint(fn)))
			return false;
		return functionReturnsErasedDynamicValue(fn, scope);
	}

	static function memberCallReturnsErasedDynamicValue(receiver:HxExpr, method:String, ?scope:CppRenderScope):Bool {
		if (scope == null)
			return false;
		final ownerName = classNameFromCppExprType(exprCppType(receiver, scope), scope);
		if (ownerName == null || ownerName.length == 0)
			return false;
		final fn = classMethodDecl(ownerName, method, false, scope);
		if (fn == null || !isDynamicLikeTypeHint(HxFunctionDecl.getReturnTypeHint(fn)))
			return false;
		final owner = scope.classByName.get(ownerName);
		if (owner == null)
			return false;
		final memberScope = renderScope(owner, {names: scope.classNames, byName: scope.classByName}, "std::any");
		return functionReturnsErasedDynamicValue(fn, memberScope);
	}

	static function cppFunctionReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		return inferredFunctionReturnCppType(fn, owner, classLookup.byName, classLookup);
	}

	static function cppMethodSignatureReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		final ownReturn = cppFunctionReturnType(fn, owner, classLookup);
		if (fn == null || owner == null || HxFunctionDecl.getIsStatic(fn))
			return ownReturn;
		final inherited = inheritedMethodSignatureReturnType(fn, owner, classLookup);
		return shouldUseInheritedMethodSignatureReturn(ownReturn, inherited) ? inherited : ownReturn;
	}

	static function shouldUseInheritedMethodSignatureReturn(ownReturn:String, inheritedReturn:String):Bool {
		return isCppReferenceType(ownReturn) && isCppReferenceType(inheritedReturn);
	}

	static function inheritedMethodSignatureReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		final method = sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final baseReturn = inheritedBaseMethodSignatureReturnType(fn, owner, classLookup);
		if (baseReturn.length > 0)
			return baseReturn;
		for (ifaceName in implementedInterfaceNames(owner, classLookup)) {
			final iface = classLookup.byName.get(ifaceName);
			if (iface == null)
				continue;
			if (genericClassTypeParams(iface).length > 0)
				continue;
			final ifaceFn = classMethodDeclIn(iface, method, false);
			if (ifaceFn != null)
				return cppFunctionReturnType(ifaceFn, iface, classLookup);
		}
		return "";
	}

	static function inheritedBaseMethodSignatureReturnType(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):String {
		final baseName = baseTypeName(owner);
		if (baseName == null || baseName.length == 0)
			return "";
		final base = classLookup.byName.get(baseName);
		if (base == null)
			return "";
		if (genericClassTypeParams(base).length > 0)
			return "";
		final baseFn = classMethodDeclIn(base, HxFunctionDecl.getName(fn), false);
		if (baseFn != null)
			return cppFunctionReturnType(baseFn, base, classLookup);
		return inheritedBaseMethodSignatureReturnType(fn, base, classLookup);
	}

	static function inferredFunctionReturnCppType(fn:HxFunctionDecl, owner:HxClassDecl, classByName:haxe.ds.StringMap<HxClassDecl>,
			?classLookup:CppClassLookup):String {
		final raw = StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn) == null ? "" : HxFunctionDecl.getReturnTypeHint(fn));
		final ownerName = owner == null ? "" : sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final returnLookup = classLookup == null ? {names: classNamesFromByName(classByName), byName: classByName} : classLookup;
		final cacheKey = functionDeclCacheKey(owner, fn, returnLookup);
		final cached = functionReturnTypesCache.get(cacheKey);
		if (cached != null)
			return cached;
		function cacheReturn(typeName:String):String {
			functionReturnTypesCache.set(cacheKey, typeName);
			return typeName;
		}
		if (ownerName == "Bytes" && sanitizeIdentifier(HxFunctionDecl.getName(fn)) == "fill")
			return cacheReturn(knownStdlibMethodReturnCppType(ownerName, HxFunctionDecl.getName(fn), raw, null,
				{names: new haxe.ds.StringMap<Bool>(), byName: classByName}));
		if (ownerName == "Exception") {
			final knownReturn = knownStdlibMethodReturnCppType(ownerName, HxFunctionDecl.getName(fn), raw, null,
				{names: new haxe.ds.StringMap<Bool>(), byName: classByName});
			if (knownReturn.length > 0)
				return cacheReturn(knownReturn);
		}
		if (isStringIteratorHelper(ownerName))
			return cacheReturn(knownStdlibMethodReturnCppType(ownerName, HxFunctionDecl.getName(fn), raw, null,
				{names: new haxe.ds.StringMap<Bool>(), byName: classByName}));
		if (ownerName == "EReg") {
			final knownReturn = knownStdlibMethodReturnCppType(ownerName, HxFunctionDecl.getName(fn), raw, null,
				{names: new haxe.ds.StringMap<Bool>(), byName: classByName});
			if (knownReturn.length > 0)
				return cacheReturn(knownReturn);
		}
		if (isDynamicLikeTypeHint(raw) && functionReturnsEnumMetadataCtor(fn))
			return cacheReturn("std::string");
		final returnScope = renderScope(owner, returnLookup, "auto");
		if (raw.length == 0) {
			final knownReturn = knownStdlibMethodReturnCppType(ownerName, HxFunctionDecl.getName(fn), raw, returnScope, returnLookup);
			if (knownReturn.length > 0)
				return cacheReturn(knownReturn);
		}
		if (raw.length > 0 && isDynamicLikeTypeHint(raw) && functionReturnsErasedDynamicValue(fn, returnScope))
			return cacheReturn("std::any");
		if (raw.length > 0) {
			applyFunctionTypeParams(returnScope, fn);
			if (functionReturnTypeParamShouldUseAuto(raw, fn))
				return cacheReturn(functionReturnsOnlyNull(fn) ? "std::nullptr_t" : "auto");
			final abstractReturn = abstractUnderlyingReturnCppType(raw, owner, returnScope, returnLookup);
			if (abstractReturn.length > 0)
				return cacheReturn(abstractReturn);
			return cacheReturn(cppReturnTypeHint(raw, returnScope, returnLookup));
		}
		if (functionReturnsLambda(fn))
			return cacheReturn("auto");
		final key = functionSignatureKey(owner, fn, returnLookup);
		if (inferredSignatureStack.exists(key))
			return "";
		inferredSignatureStack.set(key, true);
		final scope = renderScope(owner, returnLookup, "auto");
		prepareFunctionScope(scope, fn);
		for (stmt in HxFunctionDecl.getBody(fn)) {
			final inferred = inferReturnTypeFromStmt(stmt, scope);
			if (inferred.length > 0) {
				inferredSignatureStack.remove(key);
				return cacheReturn(inferred);
			}
		}
		inferredSignatureStack.remove(key);
		return cacheReturn(functionHasValueReturn(fn) ? cppReturnTypeHint(raw, returnScope, returnLookup) : "void");
	}

	static function abstractUnderlyingReturnCppType(rawReturnHint:String, owner:HxClassDecl, scope:CppRenderScope, classLookup:CppClassLookup):String {
		if (owner == null || rawReturnHint == null || rawReturnHint.length == 0)
			return "";
		final ownerName = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
		final returnName = sanitizeTypePath(typeBaseName(rawReturnHint));
		if (ownerName.length == 0 || ownerName != returnName || genericTypeHintArgs(rawReturnHint).length > 0)
			return "";
		final underlying = abstractUnderlyingTypeHint(owner);
		if (underlying == null || genericTypeHintArgs(underlying).length > 0)
			return "";
		final underlyingClass = sanitizeTypePath(typeBaseName(underlying));
		if (!classAbstractUnderlyingMatches(owner, underlyingClass, scope))
			return "";
		return cppReturnTypeHint(underlying, scope, classLookup);
	}

	static function classAbstractUnderlyingMatches(cls:HxClassDecl, expectedClass:String, scope:CppRenderScope):Bool {
		if (cls == null || expectedClass == null || expectedClass.length == 0)
			return false;
		final underlying = abstractUnderlyingTypeHint(cls);
		if (underlying == null || genericTypeHintArgs(underlying).length > 0)
			return false;
		final underlyingClass = sanitizeTypePath(typeBaseName(underlying));
		if (underlyingClass != sanitizeTypePath(typeBaseName(expectedClass)))
			return false;
		return scope != null && scope.classByName.exists(underlyingClass);
	}

	static function primitiveStringAbstractBinaryOpCppType(op:String, left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		return primitiveStringAbstractBinaryOpExpr(op, left, right, scope) == null ? "" : "std::string";
	}

	static function primitiveStringAbstractBinaryOpExpr(op:String, left:HxExpr, right:HxExpr, ?scope:CppRenderScope):Null<String> {
		if (scope == null)
			return null;
		final leftCls = primitiveBackedAbstractClassForExpr(left, scope);
		final rightCls = primitiveBackedAbstractClassForExpr(right, scope);
		if (op == "*") {
			if (leftCls != null && primitiveStringAbstractStaticMethod(leftCls, "repeat", scope) != null && isCppStringExpr(right, scope))
				return primitiveStringAbstractCall(leftCls, "repeat", [renderExpr(left, scope), stringExpr(right, scope)]);
			if (rightCls != null && primitiveStringAbstractStaticMethod(rightCls, "repeat", scope) != null && isCppStringExpr(left, scope))
				return primitiveStringAbstractCall(rightCls, "repeat", [renderExpr(right, scope), stringExpr(left, scope)]);
		}
		if (op == "/"
			&& rightCls != null
			&& primitiveStringAbstractStaticMethod(rightCls, "cut", scope) != null
			&& isCppStringExpr(left, scope))
			return primitiveStringAbstractCall(rightCls, "cut", [stringExpr(left, scope), renderExpr(right, scope)]);
		return null;
	}

	static function primitiveStringAbstractStaticMethod(cls:HxClassDecl, method:String, scope:CppRenderScope):Null<HxFunctionDecl> {
		if (cls == null || primitiveAbstractUnderlyingCppType(cls) != "int")
			return null;
		final fn = classMethodDecl(sanitizeTypePath(HxClassDecl.getName(cls)), method, true, scope);
		if (fn == null || cppFunctionReturnType(fn, cls, {names: scope.classNames, byName: scope.classByName}) != "std::string")
			return null;
		return fn;
	}

	static function primitiveStringAbstractCall(cls:HxClassDecl, method:String, args:Array<String>):String {
		return sanitizeTypePath(HxClassDecl.getName(cls)) + "::" + method + "(" + args.join(", ") + ")";
	}

	static function classBackedAbstractClassForExpr(expr:HxExpr, ?scope:CppRenderScope):Null<HxClassDecl> {
		if (scope == null)
			return null;
		final typeName = exprCppType(expr, scope);
		if (!isCppReferenceType(typeName))
			return null;
		final className = classNameFromCppExprType(typeName, scope);
		if (className == null || className.length == 0)
			return null;
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null || abstractUnderlyingTypeHint(cls) == null || primitiveAbstractUnderlyingCppType(cls) != null)
			return null;
		final underlying = abstractUnderlyingTypeHint(cls);
		if (underlying == null || genericTypeHintArgs(underlying).length > 0)
			return null;
		return scope.classByName.exists(sanitizeTypePath(typeBaseName(underlying))) ? cls : null;
	}

	static function classBackedAbstractBinaryOpMethod(op:String, left:HxExpr, right:HxExpr, cls:HxClassDecl, scope:CppRenderScope):String {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		return switch (op) {
			case "+" if (classMethodDecl(className, "add", true, scope) != null):
				"add";
			case "*" if (classMethodDecl(className, "scalar", true, scope) != null):
				"scalar";
			case "*=" if (classMethodDecl(className, "scalarAssign", true, scope) != null):
				"scalarAssign";
			case _:
				"";
		};
	}

	static function classBackedAbstractBinaryOpCppType(op:String, left:HxExpr, right:HxExpr, ?scope:CppRenderScope):String {
		final cls = classBackedAbstractClassForExpr(left, scope);
		if (cls == null || scope == null)
			return "";
		final method = classBackedAbstractBinaryOpMethod(op, left, right, cls, scope);
		return method.length == 0 ? "" : "std::shared_ptr<" + sanitizeTypePath(HxClassDecl.getName(cls)) + ">";
	}

	static function classBackedAbstractBinaryOpExpr(op:String, left:HxExpr, right:HxExpr, ?scope:CppRenderScope):Null<String> {
		final cls = classBackedAbstractClassForExpr(left, scope);
		if (cls == null || scope == null)
			return null;
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final method = classBackedAbstractBinaryOpMethod(op, left, right, cls, scope);
		if (method.length == 0)
			return null;
		final call = className + "::" + method + "(" + renderExpr(left, scope) + ", " + renderExpr(right, scope) + ")";
		if (op == "*=")
			return "([&]() { " + call + "; return " + renderExpr(left, scope) + "; })()";
		return classBackedAbstractWrapUnderlyingExpr(cls, call, scope);
	}

	static function classBackedAbstractWrapUnderlyingExpr(cls:HxClassDecl, valueExpr:String, scope:CppRenderScope):String {
		final className = sanitizeTypePath(HxClassDecl.getName(cls));
		final underlying = abstractUnderlyingTypeHint(cls);
		if (underlying == null)
			return valueExpr;
		final argNames = classConstructorArgNames(sanitizeTypePath(typeBaseName(underlying)), scope);
		if (argNames.length == 0)
			return valueExpr;
		final tmp = "__hxhx_" + className + "_underlying";
		return "([&]() { auto "
			+ tmp
			+ " = "
			+ valueExpr
			+ "; return std::make_shared<"
			+ className
			+ ">("
			+ [for (arg in argNames) tmp + "->" + arg].join(", ") + "); })()";
	}

	static function classConstructorArgNames(className:String, scope:CppRenderScope):Array<String> {
		if (scope == null || className == null || className.length == 0)
			return [];
		final cls = scope.classByName.get(sanitizeTypePath(typeBaseName(className)));
		if (cls == null)
			return [];
		final ctor = findConstructor(cls);
		if (ctor == null)
			return [];
		return [
			for (arg in HxFunctionDecl.getArgs(ctor))
				sanitizeIdentifier(HxFunctionArg.getName(arg))
		];
	}

	static function inferredFunctionArgCppTypes(fn:HxFunctionDecl, owner:HxClassDecl, classByName:haxe.ds.StringMap<HxClassDecl>,
			?allClasses:Array<HxClassDecl>):Array<String> {
		final rawReturn = StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn) == null ? "" : HxFunctionDecl.getReturnTypeHint(fn));
		final lookup = {names: classNamesFromByName(classByName), byName: classByName, all: allClasses == null ? [] : allClasses};
		final cacheKey = functionArgTypesCacheKey(owner, fn, lookup);
		final cached = functionArgTypesCache.get(cacheKey);
		if (cached != null)
			return cached.copy();
		final returnScope = renderScope(owner, lookup, "auto");
		applyFunctionTypeParams(returnScope, fn);
		final returnType = rawReturn.length > 0 ? cppReturnTypeHint(rawReturn, returnScope, lookup) : "auto";
		final key = functionSignatureKey(owner, fn, lookup);
		if (inferredSignatureStack.exists(key))
			return [for (arg in HxFunctionDecl.getArgs(fn)) cppFunctionArgBaseType(arg, null)];
		inferredSignatureStack.set(key, true);
		final scope = renderScope(owner, lookup, returnType);
		prepareFunctionScope(scope, fn);
		final types = [for (arg in HxFunctionDecl.getArgs(fn)) cppFunctionArgType(arg, scope)];
		inferredSignatureStack.remove(key);
		functionArgTypesCache.set(cacheKey, types.copy());
		return types;
	}

	static function functionArgTypesCacheKey(owner:HxClassDecl, fn:HxFunctionDecl, ?classLookup:CppClassLookup):String {
		return functionDeclCacheKey(owner, fn, classLookup);
	}

	static function functionDeclCacheKey(owner:HxClassDecl, fn:HxFunctionDecl, ?classLookup:CppClassLookup):String {
		final args = HxFunctionDecl.getArgs(fn);
		final argParts = [
			for (arg in args)
				sanitizeIdentifier(HxFunctionArg.getName(arg)) + ":" +
				removeTypeHintWhitespace(StringTools.trim(HxFunctionArg.getTypeHint(arg) == null ? "" : HxFunctionArg.getTypeHint(arg)))
		];
		return functionSignatureKey(owner, fn, classLookup)
			+ "("
			+ argParts.join(",")
			+ ")->"
			+ removeTypeHintWhitespace(StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn) == null ? "" : HxFunctionDecl.getReturnTypeHint(fn)));
	}

	static function functionSignatureKeyForScope(scope:CppRenderScope, fn:HxFunctionDecl):String {
		return scope == null ? functionSignatureKey(null, fn) : functionSignatureKey(scope.owner, fn, scope.classLookup);
	}

	static function functionSignatureKey(owner:HxClassDecl, fn:HxFunctionDecl, ?classLookup:CppClassLookup):String {
		final ownerName = owner == null ? "" : renderedClassName(owner, classLookup);
		return ownerName + "." + sanitizeIdentifier(HxFunctionDecl.getName(fn));
	}

	static function classNamesFromByName(classByName:haxe.ds.StringMap<HxClassDecl>):haxe.ds.StringMap<Bool> {
		final names = new haxe.ds.StringMap<Bool>();
		if (classByName != null)
			for (name in classByName.keys())
				names.set(name, true);
		return names;
	}

	static function functionHasValueReturn(fn:HxFunctionDecl):Bool {
		for (stmt in HxFunctionDecl.getBody(fn))
			if (stmtHasValueReturn(stmt))
				return true;
		return false;
	}

	static function functionReturnsOnlyNull(fn:HxFunctionDecl):Bool {
		var found = false;
		for (stmt in HxFunctionDecl.getBody(fn)) {
			final isNull = stmtReturnsOnlyNull(stmt);
			if (isNull == null)
				return false;
			if (isNull)
				found = true;
		}
		return found;
	}

	static function stmtReturnsOnlyNull(stmt:HxStmt):Null<Bool> {
		return switch (stmt) {
			case SReturn(ENull, _):
				true;
			case SBlock(stmts, _):
				stmtsReturnOnlyNull(stmts);
			case SIf(_, thenBranch, elseBranch, _): final thenNull = stmtReturnsOnlyNull(thenBranch); final elseNull = elseBranch == null ? false : stmtReturnsOnlyNull(elseBranch); thenNull == true && elseNull == true ? true : null;
			case STry(tryBody, catches, _):
				final tryNull = stmtReturnsOnlyNull(tryBody);
				if (tryNull != true) null; else {
					var ok = true;
					for (c in catches)
						if (stmtReturnsOnlyNull(c.body) != true)
							ok = false;
					ok ? true : null;
				}
			case SReturnVoid(_):
				null;
			case _:
				false;
		};
	}

	static function stmtsReturnOnlyNull(stmts:Array<HxStmt>):Null<Bool> {
		var found = false;
		for (stmt in stmts) {
			final isNull = stmtReturnsOnlyNull(stmt);
			if (isNull == null)
				return null;
			if (isNull)
				found = true;
		}
		return found;
	}

	static function stmtHasValueReturn(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SReturn(_, _):
				true;
			case SBlock(stmts, _):
				stmtsHaveValueReturn(stmts);
			case SIf(_, thenBranch, elseBranch, _): stmtHasValueReturn(thenBranch) || (elseBranch != null && stmtHasValueReturn(elseBranch));
			case SWhile(_, body, _) | SDoWhile(body, _, _):
				stmtHasValueReturn(body);
			case SSwitch(_, _, bodies, _):
				stmtsHaveValueReturn(bodies);
			case STry(tryBody, catches, _):
				if (stmtHasValueReturn(tryBody)) true; else {
					var found = false;
					for (c in catches)
						if (stmtHasValueReturn(c.body))
							found = true;
					found;
				}
			case _:
				false;
		};
	}

	static function stmtsHaveValueReturn(stmts:Array<HxStmt>):Bool {
		for (stmt in stmts)
			if (stmtHasValueReturn(stmt))
				return true;
		return false;
	}

	static function inferReturnTypeFromStmt(stmt:HxStmt, scope:CppRenderScope):String {
		return switch (stmt) {
			case SVar(name, typeHint, init, _):
				scope.localTypes.set(sanitizeIdentifier(name), cppLocalTypeHint(typeHint, init, scope));
				"";
			case SReturn(expr, _):
				inferExprCppType(expr, scope);
			case SReturnVoid(_):
				"void";
			case SBlock(stmts, _):
				inferReturnTypeFromStmts(stmts, scope);
			case SIf(_, thenBranch, elseBranch, _):
				final thenType = inferReturnTypeFromStmt(thenBranch, scope);
				final elseType = elseBranch == null ? "" : inferReturnTypeFromStmt(elseBranch, scope);
				if (thenType.length > 0 && thenType != "void") thenType; else if (elseType.length > 0 && elseType != "void") elseType; else
					if (thenType.length > 0) thenType; else elseType;
			case STry(tryBody, catches, _):
				final tryType = inferReturnTypeFromStmt(tryBody, scope);
				if (tryType.length > 0 && tryType != "void") {
					tryType;
				} else {
					var catchType = "";
					for (c in catches) {
						final inferred = inferReturnTypeFromStmt(c.body, scope);
						if (inferred.length > 0) {
							catchType = inferred;
							break;
						}
					}
					if (tryType.length > 0)
						tryType;
					else
						catchType;
				}
			case _:
				"";
		};
	}

	static function inferReturnTypeFromStmts(stmts:Array<HxStmt>, scope:CppRenderScope):String {
		for (stmt in stmts) {
			final inferred = inferReturnTypeFromStmt(stmt, scope);
			if (inferred.length > 0)
				return inferred;
		}
		return "";
	}

	static function cppNullableTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final inner = cppTypeHint(typeHint, scope, classLookup);
		if (isCppReferenceType(inner) || isCppOptionalType(inner))
			return inner;
		return "std::optional<" + inner + ">";
	}

	static function unwrapNullTypeHint(typeHint:String):String {
		return CppTypeModel.unwrapNullTypeHint(typeHint);
	}

	static function isFunctionTypeHint(typeHint:String):Bool {
		return CppTypeModel.isFunctionTypeHint(typeHint);
	}

	static function cppFunctionTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final parts = splitTopLevelFunctionType(typeHint);
		if (parts.length <= 1)
			return "std::function<std::string()>";
		final returnType = cppTypeHint(parts[parts.length - 1], scope, classLookup);
		final argParts = CppTypeModel.functionArgTypeParts(parts.slice(0, parts.length - 1));
		final args = [for (arg in argParts) cppTypeHint(functionTypePartHint(arg), scope, classLookup)].filter(t -> t != "void");
		return "std::function<" + returnType + "(" + args.join(", ") + ")>";
	}

	static function cppFunctionReturnTypeFromCppType(typeName:String):String {
		return CppTypeModel.cppFunctionReturnTypeFromCppType(typeName);
	}

	static function splitTopLevelFunctionType(typeHint:String):Array<String> {
		return CppTypeModel.splitTopLevelFunctionType(typeHint);
	}

	static function splitTopLevelComma(text:String):Array<String> {
		return CppTypeModel.splitTopLevelComma(text);
	}

	static function stripTypeParens(typeHint:String):String {
		return CppTypeModel.stripTypeParens(typeHint);
	}

	static function removeTypeHintWhitespace(typeHint:String):String {
		return CppTypeModel.removeTypeHintWhitespace(typeHint);
	}

	static function typeBaseName(typeHint:String):String {
		return CppTypeModel.typeBaseName(typeHint);
	}

	static function typeHintPathPart(typeHint:String):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final open = hint.indexOf("<");
		return open < 0 ? hint : hint.substr(0, open);
	}

	static function isClassLikeTypeHint(typeHint:String):Bool {
		return CppTypeModel.isClassLikeTypeHint(typeHint);
	}

	static function isStructuralTypeHint(typeHint:String):Bool {
		return CppTypeModel.isStructuralTypeHint(typeHint);
	}

	static function isCppReferenceType(typeName:String):Bool {
		return CppTypeModel.isCppReferenceType(typeName);
	}

	static function isCppVectorType(typeName:String):Bool {
		return CppTypeModel.isCppVectorType(typeName);
	}

	static function isCppBytesDataVectorType(typeName:String):Bool {
		return CppTypeModel.isCppBytesDataVectorType(typeName);
	}

	static function cppVectorElementType(typeName:String):String {
		return CppTypeModel.cppVectorElementType(typeName);
	}

	static function cppIteratorElementType(typeName:String):String {
		return CppTypeModel.cppIteratorElementType(typeName);
	}

	static function isCppArrayBackedAbstractType(typeName:String, ?scope:CppRenderScope):Bool {
		return CppTypeModel.isCppArrayBackedAbstractType(typeName, scope);
	}

	static function isCppOptionalType(typeName:String):Bool {
		return CppTypeModel.isCppOptionalType(typeName);
	}

	static function isCppFunctionType(typeName:String):Bool {
		return CppTypeModel.isCppFunctionType(typeName);
	}

	static function isScopedGenericCppType(typeName:String, ?scope:CppRenderScope):Bool {
		return CppTypeModel.isScopedGenericCppType(typeName, scope);
	}

	static function isCppAnonStructType(typeName:String):Bool {
		return typeName != null && (typeName == "__hxhx_anon" || StringTools.startsWith(typeName, "__hxhx_anon_"));
	}

	static function classNameFromCppType(typeName:String):Null<String> {
		return CppTypeModel.classNameFromCppType(typeName);
	}

	static function classNameFromCppExprType(typeName:String, ?scope:CppRenderScope):Null<String> {
		return CppTypeModel.classNameFromCppExprType(typeName, scope);
	}

	static function cppDefaultValue(typeName:String, ?scope:CppRenderScope):String {
		return CppTypeModel.cppDefaultValue(typeName, scope);
	}

	static function cStyleConditionExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final rendered = conditionExpr(expr, scope);
		return StringTools.startsWith(rendered, "(") && StringTools.endsWith(rendered, ")") ? rendered : "(" + rendered + ")";
	}

	static function callStringExpr(expr:HxExpr, ?scope:CppRenderScope):String {
		final typeName = exprCppType(expr, scope);
		final inferredType = typeName.length > 0 ? typeName : inferExprCppType(expr, scope);
		final rendered = renderExpr(expr, scope);
		return switch (inferredType) {
			case "std::string":
				rendered;
			case "bool":
				"std::string(" + rendered + " ? \"true\" : \"false\")";
			case "int" | "double" | "float" | "long long" | "unsigned int":
				"std::to_string(" + rendered + ")";
			case _:
				"__hxhx_stringify(" + rendered + ")";
		};
	}

	static function isPolymorphicIsOfTypeHelper(fn:HxFunctionDecl):Bool {
		if (fn == null || !HxFunctionDecl.getIsStatic(fn) || sanitizeIdentifier(HxFunctionDecl.getName(fn)) != "isOfType")
			return false;
		if (StringTools.trim(HxFunctionDecl.getReturnTypeHint(fn)) != "Bool")
			return false;
		final args = HxFunctionDecl.getArgs(fn);
		return args.length == 2
			&& removeTypeHintWhitespace(HxFunctionArg.getTypeHint(args[0])) == "Dynamic"
			&& removeTypeHintWhitespace(HxFunctionArg.getTypeHint(args[1])) == "Dynamic";
	}

	static function renderPolymorphicIsOfTypeHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final scope = renderScope(owner, classLookup, "bool");
		final args = HxFunctionDecl.getArgs(fn);
		final valueName = sanitizeIdentifier(HxFunctionArg.getName(args[0]));
		final typeName = sanitizeIdentifier(HxFunctionArg.getName(args[1]));
		scope.localTypes.set(valueName, "TValue");
		scope.localTypes.set(typeName, "TType");
		scope.localNames.set(valueName, valueName);
		scope.localNames.set(typeName, typeName);
		scope.localNameCounts.set(valueName, 1);
		scope.localNameCounts.set(typeName, 1);
		final out = ["  template<typename TValue, typename TType>",
			"  static bool "
			+ sanitizeIdentifier(HxFunctionDecl.getName(fn))
			+ "(const TValue& "
			+ valueName
			+ ", const TType& "
			+ typeName
			+ ") {"];
		for (line in renderFunctionBody(HxFunctionDecl.getBody(fn), "    ", scope))
			out.push(line);
		out.push("  }");
		return out;
	}

	static function structuralFieldCppType(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final raw = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (genericTypeParamName(raw).length > 0)
			return "std::string";
		final fieldType = cppTypeHint(raw, scope, classLookup);
		return isScopeTypeParam(fieldType, scope) || isBareCppTypeParamName(fieldType) ? "std::string" : fieldType;
	}
}
