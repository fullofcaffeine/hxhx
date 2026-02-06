package haxe.macro;

// Imports must appear before any declarations in this compilation unit.
#if (neko || eval || display)
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#else
import haxe.macro.Expr;
import hxhxmacrohost.api.Context as HostContext;
import hxhxmacrohost.MacroError;
#end

/**
	Macro-host override for `haxe.macro.Context` (Stage 4 bring-up).

	Why
	- Macro modules we compile *into the macro host binary* naturally import `haxe.macro.Context`.
	- Outside of upstream's macro interpreter (`eval`/`neko`/`display`), the standard library version
	  throws "Can't be called outside of macro".
	- At the same time, **building the macro host binary** executes real compile-time macros
	  (Reflaxe init, `nullSafety(...)`, etc.), which require the *real* macro API to remain available.

	What
	- This file therefore has **two personalities**:
	  - `#if (neko || eval || display)`: behave like upstream `haxe.macro.Context` by forwarding to
	    the compiler's macro API via `load(...)`.
	  - `#else`: provide a tiny runtime subset mapped to the Stage4 RPC API (`hxhxmacrohost.api.Context`)
	    so runtime macro code like `Macro.init()` can register hooks.

	How
	- The macro personality is a small forwarder wrapper (not a full copy of upstream).
	- The runtime personality intentionally implements only what our bring-up tests need today.

	Gotchas
	- Do not grow the runtime subset opportunistically. Add methods only when a gate/test requires it.
**/
// Keep `Message` compatible with upstream.

enum Message {
	Info(msg:String, pos:Position);
	Warning(msg:String, pos:Position);
}

#if (neko || eval || display)
class Context {
	@:allow(haxe.macro.TypeTools)
	@:allow(haxe.macro.MacroStringTools)
	@:allow(haxe.macro.TypedExprTools)
	@:allow(haxe.macro.PositionTools)
	@:allow(haxe.macro.Compiler)
	static function load(f:String, nargs:Int):Dynamic {
		#if neko
		return neko.Lib.load("macro", f, nargs);
		#elseif eval
		return eval.vm.Context.callMacroApi(f);
		#else
		return Reflect.makeVarArgs(function(_) return throw "Can't be called outside of macro");
		#end
	}

	public static function error(msg:String, pos:Position, ?depth:Int = 0):Dynamic {
		return load("error", 2)(msg, pos, depth);
	}

	public static function fatalError(msg:String, pos:Position, ?depth:Int = 0):Dynamic {
		return load("fatal_error", 2)(msg, pos, depth);
	}

	public static function warning(msg:String, pos:Position, ?depth:Int = 0):Void {
		load("warning", 2)(msg, pos, depth);
	}

	public static function info(msg:String, pos:Position, ?depth:Int = 0):Void {
		load("info", 2)(msg, pos, depth);
	}

	public static function getMessages():Array<Message> {
		return load("get_messages", 0)();
	}

	public static function filterMessages(predicate:Message->Bool):Void {
		load("filter_messages", 1)(predicate);
	}

	public static function resolvePath(file:String):String {
		return load("resolve_path", 1)(file);
	}

	public static function getClassPath():Array<String> {
		return load("class_path", 0)();
	}

	public static function containsDisplayPosition(pos:Position):Bool {
		return load("contains_display_position", 1)(pos);
	}

	public static function currentPos():Position {
		return load("current_pos", 0)();
	}

	public static function getExpectedType():Null<Type> {
		return load("get_expected_type", 0)();
	}

	public static function getCallArguments():Null<Array<Expr>> {
		return load("get_call_arguments", 0)();
	}

	public static function getLocalClass():Null<Type.Ref<Type.ClassType>> {
		var l:Type = load("get_local_type", 0)();
		if (l == null)
			return null;
		return switch (l) {
			case TInst(c, _): c;
			default: null;
		}
	}

	public static function getLocalModule():String {
		return load("get_local_module", 0)();
	}

	public static function getLocalType():Null<Type> {
		return load("get_local_type", 0)();
	}

	public static function getLocalMethod():Null<String> {
		return load("get_local_method", 0)();
	}

	public static function getLocalUsing():Array<Dynamic> {
		return load("get_local_using", 0)();
	}

	public static function getLocalImports():Array<ImportExpr> {
		return load("get_local_imports", 0)();
	}

	public static function getLocalTVars():Map<String, haxe.macro.Type.TVar> {
		return load("get_local_tvars", 0)();
	}

	public static function defined(key:String):Bool {
		return load("defined", 1)(key);
	}

	public static function definedValue(key:String):String {
		return load("defined_value", 1)(key);
	}

	public static function getDefines():Map<String, String> {
		return load("get_defines", 0)();
	}

	public static function getType(name:String):Type {
		return load("get_type", 1)(name);
	}

	public static function getModule(name:String):Array<Type> {
		return load("get_module", 1)(name);
	}

	public static function parse(expr:String, pos:Position):Expr {
		return load("parse", 2)(expr, pos);
	}

	public static function parseInlineString(expr:String, pos:Position):Expr {
		return load("parse_inline_string", 2)(expr, pos);
	}

	public static function makeExpr(v:Dynamic, pos:Position):Expr {
		return load("make_expr", 2)(v, pos);
	}

	public static function signature(v:Dynamic):String {
		return load("signature", 1)(v);
	}

	public static function onGenerate(callback:Array<Type>->Void, persistent:Bool = true):Void {
		load("on_generate", 2)(callback, persistent);
	}

	public static function onAfterGenerate(callback:Void->Void):Void {
		load("on_after_generate", 1)(callback);
	}

	public static function onAfterTyping(callback:Array<haxe.macro.Type.ModuleType>->Void):Void {
		load("on_after_typing", 1)(callback);
	}

	public static function onTypeNotFound(callback:String->TypeDefinition):Void {
		load("on_type_not_found", 1)(callback);
	}

	public static function typeof(e:Expr):Type {
		return load("typeof", 1)(e);
	}

	public static function typeExpr(e:Expr):TypedExpr {
		return load("type_expr", 1)(e);
	}

	public static function resolveType(t:ComplexType, p:Position):Type {
		return load("resolve_type", 2)(t, p);
	}

	public static function toComplexType(t:Type):Null<ComplexType> {
		return load("to_complex_type", 1)(t);
	}

	public static function unify(t1:Type, t2:Type):Bool {
		return load("unify", 2)(t1, t2);
	}

	public static function follow(t:Type, once:Bool = false):Type {
		return load("follow", 2)(t, once);
	}

	public static function followWithAbstracts(t:Type, once:Bool = false):Type {
		return load("follow_with_abstracts", 2)(t, once);
	}

	public static function getPosInfos(p:Position):{min:Int, max:Int, file:String} {
		return load("get_pos_infos", 1)(p);
	}

	public static function makePosition(inf:{min:Int, max:Int, file:String}):Position {
		return load("make_position", 3)(inf.min, inf.max, inf.file);
	}

	public static function getResources():Map<String, haxe.io.Bytes> {
		return load("get_resources", 0)();
	}

	public static function addResource(name:String, data:haxe.io.Bytes):Void {
		load("add_resource", 2)(name, data);
	}

	public static function getBuildFields():Array<Field> {
		return load("get_build_fields", 0)();
	}

	public static function defineType(t:TypeDefinition, ?moduleDependency:String):Void {
		load("define_type", 2)(t, moduleDependency);
	}

	public static function defineModule(modulePath:String, types:Array<TypeDefinition>, ?imports:Array<ImportExpr>, ?usings:Array<TypePath>):Void {
		load("define_module", 4)(modulePath, types, imports, usings);
	}

	public static function getTypedExpr(t:TypedExpr):Expr {
		return load("get_typed_expr", 1)(t);
	}

	public static function storeTypedExpr(t:TypedExpr):Expr {
		return load("store_typed_expr", 1)(t);
	}

	public static function storeExpr(e:Expr):Expr {
		return load("store_expr", 1)(e);
	}

	public static function registerModuleDependency(modulePath:String, externFile:String):Void {
		load("register_module_dependency", 2)(modulePath, externFile);
	}

	public static function timer(id:String):Void->Void {
		return load("timer", 1)(id);
	}

	@:allow(haxe.macro.Compiler)
	private static function includeFile(file:String, position:String):Void {
		load("include_file", 2)(file, position);
	}

	@:allow(haxe.macro.TypedExprTools)
	private static function sExpr(e:TypedExpr, pretty:Bool):String {
		return load("s_expr", 2)(e, pretty);
	}

	#if (haxe >= version("4.3.0"))
	public static function getMainExpr():TypedExpr {
		return load("get_main_expr", 0)();
	}
	#end
}
#else
class Context {
	public static function defined(key:String):Bool {
		return HostContext.defined(key);
	}

	public static function definedValue(key:String):String {
		return HostContext.definedValue(key);
	}

	public static function getDefines():Map<String, String> {
		return HostContext.getDefines();
	}

	public static function getBuildFields():Array<haxe.macro.Expr.Field> {
		return HostContext.getBuildFields();
	}

	public static function error(msg:String, pos:Position, ?depth:Int = 0):Dynamic {
		// Bring-up rung: we cannot attach a real macro `Position` yet.
		// Still raise a tagged error so the compiler can surface *some* `file:line` info.
		// Touch args so OCaml warning-as-error builds don't fail on unused parameters.
		if (pos != null) {}
		if (depth != 0) {}
		return MacroError.raise(msg);
	}

	public static function fatalError(msg:String, pos:Position, ?depth:Int = 0):Dynamic {
		if (pos != null) {}
		if (depth != 0) {}
		return MacroError.raise(msg);
	}

	public static function warning(msg:String, pos:Position, ?depth:Int = 0):Void {
		// Bring-up rung: warnings are currently ignored at runtime.
		if (msg != null) {}
		if (pos != null) {}
		if (depth != 0) {}
	}

	public static function info(msg:String, pos:Position, ?depth:Int = 0):Void {
		if (msg != null) {}
		if (pos != null) {}
		if (depth != 0) {}
	}

	public static function currentPos():Position {
		return null;
	}

	public static function onGenerate(callback:Array<Dynamic>->Void, persistent:Bool = true):Void {
		HostContext.onGenerate(callback, persistent);
	}

	public static function onAfterTyping(callback:Array<Dynamic>->Void):Void {
		HostContext.onAfterTyping(callback);
	}

	public static function getMessages():Array<Message> {
		return [];
	}

	public static function filterMessages(predicate:Message->Bool):Void {
		// Bring-up rung: message filtering is currently a no-op at runtime.
		// Keep argument "used" so OCaml warning-as-error builds don't fail.
		if (predicate == null) return;
	}
}
#end
