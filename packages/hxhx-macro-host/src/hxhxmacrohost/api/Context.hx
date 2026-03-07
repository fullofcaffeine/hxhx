package hxhxmacrohost.api;

import haxe.io.Bytes;
import haxe.macro.Expr;
import haxe.macro.DisplayMode;
import haxe.macro.Type;
import StringTools;
import hxhxmacrohost.api.RuntimeMacroExprs;
import hxhxmacrohost.api.Compiler as HostCompiler;
import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.MacroRuntime;
import hxhxmacrohost.Protocol;

/**
	Minimal “Context-like” API surface for Stage 4 macro bring-up.

	Why
	- Real-world macro libraries rely heavily on `haxe.macro.Context.*`.
	- For the first non-stage0 rung, we want to demonstrate that:
	  - macro code can call into a Context-like API,
	  - the API can query compiler/macro-host state,
	  - and we can return deterministic results over RPC.

	What
	- `defined(name)` / `definedValue(name)` query the compiler’s define store (reverse RPC).
	- `getType(name)`, `resolveType(t, pos)`, and `typeof(expr)` expose a tiny builtin-only type
	  model for runtime macro code that needs basic type plumbing without upstream eval.
	- `typeExpr(expr)` exposes a synthetic typed-expression rung for literal, parenthesized,
	  `check-type`, and simple `+` expressions so runtime probes can exercise `TypedExprTools`.
	- `getClassPath()` / `resolvePath(path)` expose compiler-owned classpath lookup so runtime macro
	  code can find target resources without reimplementing file search inside the host.
	- `getLocalModule()`, `getLocalMethod()`, `getLocalType()`, and `getExpectedType()` expose a
	  compiler-seeded local-context snapshot through the same builtin-only type model.
	- `getModule(name)` exposes an existence-only module lookup rung backed by compiler-side classpath
	  resolution and a synthetic named-type payload.

	How
	- Backed by the compiler define store for `defined*`.
	- Builtin type plumbing is implemented locally through `RuntimeMacroTypes`.
	- Later stages may replace or augment the local model with richer compiler-provided typed data.
**/
class Context {
	static inline final DEFAULT_MACRO_FILE:String = "<macro>";

	static function parseNonNegativeInt(raw:String, fallback:Int):Int {
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed < 0 ? fallback : parsed;
	}

	public static function defined(name:String):Bool {
		if (name == null)
			return false;
		final v = HostToCompilerRpc.call("context.defined", Protocol.encodeLen("n", name));
		return v == "1";
	}

	public static function definedValue(name:String):String {
		if (name == null)
			return "";
		return HostToCompilerRpc.call("context.definedValue", Protocol.encodeLen("n", name));
	}

	/**
		Register an "after typing" hook.

		Why
		- Upstream macros can register callbacks that run after typing completes.
		- Gate1/Gate2 macro initialization commonly uses `Context.onAfterTyping(...)`.

		What
		- Stores `cb` inside the macro host process and returns immediately.
		- Notifies the compiler of the hook ID so the compiler can invoke it later during the
		  Stage3 pipeline.

		How
		- Macro host assigns a stable integer ID to the closure and sends a reverse RPC
		  `compiler.registerHook k=afterTyping i=<id>`.
	**/
	public static function onAfterTyping(cb:Array<Dynamic>->Void):Void {
		if (cb == null)
			return;
		final id = MacroRuntime.registerAfterTyping(cb);
		final tail = Protocol.encodeLen("k", "afterTyping") + " " + Protocol.encodeLen("i", Std.string(id));
		HostToCompilerRpc.call("compiler.registerHook", tail);
	}

	/**
		Register an "on generate" hook.

		See `onAfterTyping` for bring-up rationale and mechanics.
	**/
	public static function onGenerate(cb:Array<Dynamic>->Void, persistent:Bool = true):Void {
		if (cb == null)
			return;
		// `persistent` is currently ignored in the bring-up rung (no compilation server).
		final _ = persistent;
		final id = MacroRuntime.registerOnGenerate(cb);
		final tail = Protocol.encodeLen("k", "onGenerate") + " " + Protocol.encodeLen("i", Std.string(id));
		HostToCompilerRpc.call("compiler.registerHook", tail);
	}

	/**
		Register an "after generate" hook.

		Why
		- Some macro libraries (notably compiler-style plugins) register a finalization callback
		  that runs after the generation phase completes.
		- Keeping a distinct hook kind makes it possible to evolve Stage3/Stage4 ordering without
		  overloading `onGenerate`.

		What
		- Stores `cb` inside the macro host and returns immediately.
		- Notifies the compiler of the hook ID so the compiler can invoke it later.

		Gotchas
		- This hook kind currently receives no arguments.
	**/
	public static function onAfterGenerate(cb:Void->Void):Void {
		if (cb == null)
			return;
		final id = MacroRuntime.registerAfterGenerate(cb);
		final tail = Protocol.encodeLen("k", "afterGenerate") + " " + Protocol.encodeLen("i", Std.string(id));
		HostToCompilerRpc.call("compiler.registerHook", tail);
	}

	/**
		Return a snapshot of all compiler defines.

		Why
		- Real macro libraries commonly enumerate defines to enable/disable features.
		- This is a cheap bring-up rung that unlocks a lot of upstream-ish macro patterns.

		What
		- Returns a `Map<String,String>` that contains all known defines at the time of the call.
		- Modifying the returned map has no effect on the compiler.

		How
		- Implemented as a reverse RPC (`context.getDefines`) that returns a length-prefixed payload
		  containing `c=<count>` plus `kN`/`vN` pairs.
	**/
	public static function getDefines():Map<String, String> {
		final out:Map<String, String> = [];
		final payload = HostToCompilerRpc.call("context.getDefines", "");
		if (payload == null || payload.length == 0)
			return out;

		final m = Protocol.kvParse(payload);
		final countStr = m.exists("c") ? m.get("c") : "";
		final count = Std.parseInt(countStr);
		if (count == null || count <= 0)
			return out;

		for (i in 0...count) {
			final kKey = "k" + i;
			final vKey = "v" + i;
			if (!m.exists(kKey))
				continue;
			out.set(m.get(kKey), m.exists(vKey) ? m.get(vKey) : "");
		}
		return out;
	}

	/**
		Return a snapshot of compiler-owned resources.

		Why
		- Real macro libraries may publish binary/text assets through `Context.addResource(...)` and
		  then inspect them through `Context.getResources()`.
		- The external host needs a stable snapshot because resources are compiler-owned effects, not
		  process-local host state.

		What
		- Returns a detached `Map<String, Bytes>` copy of the currently registered resources.
	**/
	public static function getResources():Map<String, Bytes> {
		final out:Map<String, Bytes> = [];
		final payload = HostToCompilerRpc.call("context.getResources", "");
		if (payload == null || payload.length == 0)
			return out;

		final m = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(m.exists("c") ? m.get("c") : "", 0);
		for (i in 0...count) {
			final kKey = "k" + i;
			final dKey = "d" + i;
			if (!m.exists(kKey) || !m.exists(dKey))
				continue;
			final hex = m.get(dKey);
			if (hex == null || (hex.length & 1) != 0)
				continue;
			out.set(m.get(kKey), Bytes.ofHex(hex));
		}
		return out;
	}

	public static function addResource(name:String, data:Bytes):Void {
		if (name == null || name.length == 0 || data == null)
			return;
		final tail = Protocol.encodeLen("n", name) + " " + Protocol.encodeLen("d", data.toHex());
		HostToCompilerRpc.call("context.addResource", tail);
	}

	/**
		Return a no-op timer end-function for runtime macro code.

		Why
		- Reflaxe-adjacent helper code and code generators often wrap work in `Context.timer("id")`
		  purely for optional instrumentation.
		- The external-host bring-up has no real compiler timing channel yet, but missing the method
		  entirely causes avoidable runtime-API breakage.

		What
		- Returns a closure that does nothing.

		Gotchas
		- This is compatibility plumbing only. It does not claim timing/reporting parity.
	**/
	public static function timer(id:String):Void->Void {
		if (id != null) {}
		return function():Void {};
	}

	static function encodePosition(pos:Position):{file:String, min:Int, max:Int} {
		if (pos == null)
			return {file: DEFAULT_MACRO_FILE, min: 0, max: 0};
		final info = getPosInfos(pos);
		return {
			file: info.file == null || info.file.length == 0 ? DEFAULT_MACRO_FILE : info.file,
			min: info.min < 0 ? 0 : info.min,
			max: info.max < 0 ? 0 : info.max
		};
	}

	public static function warning(msg:String, pos:Position, ?depth:Int = 0):Void {
		if (msg == null || msg.length == 0)
			return;
		if (depth != 0) {}
		final info = encodePosition(pos);
		final tail = Protocol.encodeLen("k", "warning") + " " + Protocol.encodeLen("m", msg) + " " + Protocol.encodeLen("f", info.file) + " "
			+ Protocol.encodeLen("mi", Std.string(info.min)) + " " + Protocol.encodeLen("ma", Std.string(info.max));
		HostToCompilerRpc.call("context.addMessage", tail);
	}

	public static function info(msg:String, pos:Position, ?depth:Int = 0):Void {
		if (msg == null || msg.length == 0)
			return;
		if (depth != 0) {}
		final infoPos = encodePosition(pos);
		final tail = Protocol.encodeLen("k", "info") + " " + Protocol.encodeLen("m", msg) + " " + Protocol.encodeLen("f", infoPos.file) + " "
			+ Protocol.encodeLen("mi", Std.string(infoPos.min)) + " " + Protocol.encodeLen("ma", Std.string(infoPos.max));
		HostToCompilerRpc.call("context.addMessage", tail);
	}

	public static function getMessages():Array<{kind:String, msg:String, pos:Position}> {
		final out = new Array<{kind:String, msg:String, pos:Position}>();
		final payload = HostToCompilerRpc.call("context.getMessages", "");
		if (payload == null || payload.length == 0)
			return out;
		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final kindKey = "k" + i;
			final msgKey = "m" + i;
			if (!parts.exists(kindKey) || !parts.exists(msgKey))
				continue;
			final file = parts.exists("f" + i) && parts.get("f" + i).length > 0 ? parts.get("f" + i) : DEFAULT_MACRO_FILE;
			final min = parseNonNegativeInt(parts.exists("mi" + i) ? parts.get("mi" + i) : "", 0);
			final max = parseNonNegativeInt(parts.exists("ma" + i) ? parts.get("ma" + i) : "", min);
			out.push({
				kind: parts.get(kindKey),
				msg: parts.get(msgKey),
				pos: {file: file, min: min, max: max < min ? min : max}
			});
		}
		return out;
	}

	public static function filterMessages(predicate:{kind:String, msg:String, pos:Position}->Bool):Void {
		if (predicate == null)
			return;
		final snapshots = getMessages();
		final kept = new Array<{kind:String, msg:String, pos:Position}>();
		for (snapshot in snapshots)
			if (predicate(snapshot))
				kept.push(snapshot);
		final parts = new Array<String>();
		parts.push(Protocol.encodeLen("c", Std.string(kept.length)));
		for (i in 0...kept.length) {
			final snapshot = kept[i];
			parts.push(Protocol.encodeLen("k" + i, snapshot.kind));
			parts.push(Protocol.encodeLen("m" + i, snapshot.msg));
			parts.push(Protocol.encodeLen("f" + i, snapshot.pos == null
				|| snapshot.pos.file == null ? DEFAULT_MACRO_FILE : snapshot.pos.file));
			parts.push(Protocol.encodeLen("mi" + i, Std.string(snapshot.pos == null ? 0 : (snapshot.pos.min < 0 ? 0 : snapshot.pos.min))));
			parts.push(Protocol.encodeLen("ma" + i, Std.string(snapshot.pos == null ? 0 : (snapshot.pos.max < 0 ? 0 : snapshot.pos.max))));
		}
		HostToCompilerRpc.call("context.replaceMessages", Protocol.encodeLen("p", parts.join(" ")));
	}

	public static function getType(name:String):Type {
		if (name == null || name.length == 0)
			throw "runtime macro getType: missing name";
		return RuntimeMacroTypes.getTypeByName(name);
	}

	public static function getModule(name:String):Array<Type> {
		if (name == null || name.length == 0)
			return [];
		final payload = HostToCompilerRpc.call("context.getModule", Protocol.encodeLen("n", name));
		if (payload == null || payload.length == 0)
			return [];
		return RuntimeMacroTypes.moduleTypesForPath(name);
	}

	public static function parse(expr:String, pos:Position):Expr {
		return RuntimeMacroExprs.parse(expr, pos);
	}

	public static function parseInlineString(expr:String, pos:Position):Expr {
		return RuntimeMacroExprs.parseInlineString(expr, pos);
	}

	public static function makeExpr(v:Dynamic, pos:Position):Expr {
		return RuntimeMacroExprs.makeExpr(v, pos);
	}

	public static function signature(v:Dynamic):String {
		return RuntimeMacroExprs.signature(v);
	}

	public static function resolveType(t:ComplexType, p:Position):Type {
		if (p != null) {}
		return RuntimeMacroTypes.resolveComplexType(t);
	}

	public static function typeof(e:Expr):Type {
		return RuntimeMacroTypes.typeofExpr(e);
	}

	public static function typeExpr(e:Expr):TypedExpr {
		return RuntimeTypedExprs.typeExpr(e);
	}

	/**
		Return a compiler-seeded main-expression snapshot.

		Why
		- Reflaxe-style compiler helpers sometimes inspect `Context.getMainExpr()` to find the typed
		  entry expression for the current compilation.
		- The external-host runtime has no live typer access, so the honest bring-up rung is a seeded
		  expression snapshot provided by the compiler.

		What
		- Returns `null` when no snapshot has been seeded.
		- Otherwise reparses the seeded expression text and re-types it through the narrow runtime
		  typed-expression bridge.

		Gotchas
		- This is a seeded snapshot rung, not live compiler main-expression parity.
		- Supported shapes are limited by `RuntimeMacroExprs` + `RuntimeTypedExprs`.
	**/
	public static function getMainExpr():TypedExpr {
		final payload = HostToCompilerRpc.call("context.getMainExpr", "");
		if (payload == null || StringTools.trim(payload).length == 0)
			return cast null;
		final expr = RuntimeMacroExprs.parseInlineString(payload, currentPos());
		return RuntimeTypedExprs.typeExpr(expr);
	}

	public static function getTypedExpr(t:TypedExpr):Expr {
		return RuntimeTypedExprs.toExpr(t);
	}

	/**
		Store an untyped expression for later runtime macro use.

		Why
		- Reflaxe-style helper layers sometimes route expressions through `Context.storeExpr(...)`
		  even when they are not relying on upstream's full macro-eval storage semantics.
		- The external-host runtime still needs a compatible rung so those helpers do not fail
		  immediately.

		What
		- Returns the provided expression unchanged.

		Gotchas
		- This is an identity compatibility rung, not compiler-side expression interning.
	**/
	public static function storeExpr(e:Expr):Expr {
		return e;
	}

	/**
		Store a typed expression for later runtime macro use.

		Why
		- Helper layers may route typed expressions through `Context.storeTypedExpr(...)` before
		  converting them back to plain `Expr`.
		- The honest runtime bring-up rung is to reuse the existing synthetic typed-expression inverse.

		What
		- Returns the `Expr` form of the supported synthetic `TypedExpr` subset.

		Gotchas
		- Coverage is limited by `RuntimeTypedExprs.toExpr(...)`.
		- This is not upstream's full typed-expression storage/interner behavior.
	**/
	public static function storeTypedExpr(t:TypedExpr):Expr {
		return RuntimeTypedExprs.toExpr(t);
	}

	/**
		Define a single type by emitting generated Haxe source into the compiler-managed `_gen_hx`
		directory.

		Why
		- Reflaxe-style helper layers sometimes use `Context.defineType(...)` to add a generated type
		  to the current compilation without requiring full typed-AST mutation support.
		- The external-host runtime can support a useful bring-up rung by printing one
		  `TypeDefinition` back to source and emitting it through the existing generated-module path.

		What
		- Prints `t` through a narrow repo-owned source printer.
		- Emits the resulting source using the type's full module path (`pack.name`).
		- Optionally records `moduleDependency` in the compiler-owned compatibility ledger.

		Gotchas
		- This is source-emission-backed compatibility, not upstream-equivalent typed mutation.
		- It intentionally supports a narrow subset of `TypeDefinition` shapes and does not claim
		  `defineModule(...)` semantics.
	**/
	public static function defineType(t:TypeDefinition, ?moduleDependency:String):Void {
		final rendered = RuntimeMacroTypeDefinitions.renderTypeDefinition(t);
		if (rendered == null)
			throw "runtime macro defineType: unsupported TypeDefinition shape";
		HostCompiler.emitHxModule(rendered.modulePath, rendered.source);
		if (moduleDependency != null && StringTools.trim(moduleDependency).length > 0)
			registerModuleDependency(rendered.modulePath, moduleDependency);
	}

	/**
		Register a module dependency in the compiler-owned runtime ledger.

		Why
		- Reflaxe-style helper layers may announce that a module depends on an external file even when
		  the external-host runtime does not own the final generation pipeline.
		- The compiler, not the host process, must keep that information.

		What
		- Sends the `(modulePath, externFile)` pair to the compiler-owned `MacroState` ledger.

		Gotchas
		- This is a compatibility ledger rung only. It does not yet imply upstream-equivalent module
		  graph semantics.
	**/
	public static function registerModuleDependency(modulePath:String, externFile:String):Void {
		if (modulePath == null || externFile == null)
			return;
		final mp = StringTools.trim(modulePath);
		final ef = StringTools.trim(externFile);
		if (mp.length == 0 || ef.length == 0)
			return;
		final tail = Protocol.encodeLen("m", mp) + " " + Protocol.encodeLen("f", ef);
		HostToCompilerRpc.call("context.registerModuleDependency", tail);
	}

	public static function toComplexType(t:Type):Null<ComplexType> {
		return RuntimeMacroTypes.toComplexType(t);
	}

	public static function unify(t1:Type, t2:Type):Bool {
		return RuntimeMacroTypes.unify(t1, t2);
	}

	public static function follow(t:Type, once:Bool = false):Type {
		return RuntimeMacroTypes.follow(t, once);
	}

	public static function followWithAbstracts(t:Type, once:Bool = false):Type {
		return RuntimeMacroTypes.followWithAbstracts(t, once);
	}

	public static function getClassPath():Array<String> {
		final payload = HostToCompilerRpc.call("context.getClassPath", "");
		final out = new Array<String>();
		if (payload == null || payload.length == 0)
			return out;
		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final key = "p" + i;
			if (parts.exists(key))
				out.push(parts.get(key));
		}
		return out;
	}

	public static function resolvePath(file:String):String {
		if (file == null || file.length == 0)
			return "";
		return HostToCompilerRpc.call("context.resolvePath", Protocol.encodeLen("f", file));
	}

	public static function getExpectedType():Null<Type> {
		return parseOptionalTypeSnapshot("context.getExpectedType");
	}

	/**
		Return the compiler-provided current macro call arguments.

		Why
		- Some macro helpers inspect `Context.getCallArguments()` to understand the immediate callsite
		  without needing full live typer access.
		- In the external-host runtime, the compiler is the only honest place to seed that snapshot.

		What
		- Returns `null` when no callsite snapshot has been seeded.
		- Otherwise returns parsed `Expr` values reconstructed from compiler-seeded expression text.

		Gotchas
		- This is a seeded snapshot rung, not full live callsite parity.
		- Expression coverage is limited by `RuntimeMacroExprs.parseInlineString(...)`.
	**/
	public static function getCallArguments():Null<Array<Expr>> {
		final payload = HostToCompilerRpc.call("context.getCallArguments", "");
		if (payload == null || payload.length == 0)
			return null;
		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", -1);
		if (count < 0)
			return null;
		final out = new Array<Expr>();
		for (i in 0...count) {
			final key = "e" + i;
			if (!parts.exists(key))
				continue;
			out.push(RuntimeMacroExprs.parseInlineString(parts.get(key), currentPos()));
		}
		return out;
	}

	public static function getLocalModule():String {
		final payload = HostToCompilerRpc.call("context.getLocalModule", "");
		return payload == null ? "" : payload;
	}

	public static function getLocalType():Null<Type> {
		return parseOptionalTypeSnapshot("context.getLocalType");
	}

	public static function getLocalMethod():Null<String> {
		final payload = HostToCompilerRpc.call("context.getLocalMethod", "");
		if (payload == null)
			return null;
		final trimmed = StringTools.trim(payload);
		return trimmed.length == 0 ? null : trimmed;
	}

	/**
		Return the compiler-provided local `using` list for the active module.

		Why
		- Reflaxe-style helpers may inspect `Context.getLocalUsing()` to understand which extension
		  classes are in scope for the current module.
		- The external-host runtime cannot inspect the parser/typer state directly, so the compiler
		  must provide a conservative top-of-module snapshot.

		What
		- Returns synthetic `ClassType` refs for the `using` paths declared in the active source file.
		- The refs are sufficient for path rendering and identity within the current runtime type rung;
		  they do not claim rich compiler metadata.
	**/
	public static function getLocalUsing():Array<Ref<ClassType>> {
		final payload = HostToCompilerRpc.call("context.getLocalUsing", "");
		final paths = new Array<String>();
		if (payload == null || payload.length == 0)
			return [];

		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final pathKey = "p" + i;
			if (!parts.exists(pathKey))
				continue;
			final pathText = StringTools.trim(parts.get(pathKey));
			if (pathText.length == 0)
				continue;
			paths.push(pathText);
		}
		return RuntimeMacroTypes.localUsingRefsForPaths(paths);
	}

	/**
		Return the compiler-provided local type-variable snapshot for the active module.

		Why
		- Some macro helpers inspect `Context.getLocalTVars()` to understand the immediate local type
		  environment without needing full typed-AST access.
		- The external-host runtime cannot inspect compiler locals directly, so the compiler must
		  seed a conservative snapshot when tests or build macros require it.

		What
		- Returns a detached `Map<String, TVar>` keyed by local variable name.
		- The returned TVars use the narrow runtime builtin-type model and do not claim rich metadata.
	**/
	public static function getLocalTVars():Map<String, TVar> {
		final out:Map<String, TVar> = [];
		final payload = HostToCompilerRpc.call("context.getLocalTVars", "");
		if (payload == null || payload.length == 0)
			return out;

		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final nameKey = "n" + i;
			final typeKey = "t" + i;
			if (!parts.exists(nameKey) || !parts.exists(typeKey))
				continue;
			final name = StringTools.trim(parts.get(nameKey));
			final typeText = StringTools.trim(parts.get(typeKey));
			if (name.length == 0 || typeText.length == 0)
				continue;
			final id = parseNonNegativeInt(parts.exists("id" + i) ? parts.get("id" + i) : "", i + 1);
			final capture = parts.exists("cap" + i) && parts.get("cap" + i) == "1";
			final isStatic = parts.exists("st" + i) && parts.get("st" + i) == "1";
			out.set(name, RuntimeMacroTypes.localTVar(name, typeText, id, capture, isStatic));
		}
		return out;
	}

	/**
		Return the compiler-provided local import list for the active module.

		Why
		- Real target macros use `Context.getLocalImports()` to resolve aliases and wildcard imports
		  against the module currently being typed.
		- The external-host runtime does not own the parsed module, so the compiler must provide a
		  conservative snapshot.

		What
		- Returns `ImportExpr` values with:
		  - real `path` segment names
		  - preserved import modes (`INormal`, `IAsName`, `IAll`)
		  - synthetic positions derived from the source file snapshot

		How
		- Reverse RPC `context.getLocalImports` returns a length-prefixed fragment list containing
		  the path, mode, alias, and synthetic source span for each import.
	**/
	public static function getLocalImports():Array<ImportExpr> {
		final payload = HostToCompilerRpc.call("context.getLocalImports", "");
		final out = new Array<ImportExpr>();
		if (payload == null || payload.length == 0)
			return out;

		final parts = Protocol.kvParse(payload);
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final pathKey = "p" + i;
			if (!parts.exists(pathKey))
				continue;
			final pathText = StringTools.trim(parts.get(pathKey));
			if (pathText.length == 0)
				continue;

			final file = parts.exists("f" + i) && parts.get("f" + i).length > 0 ? parts.get("f" + i) : DEFAULT_MACRO_FILE;
			final min = parseNonNegativeInt(parts.exists("mi" + i) ? parts.get("mi" + i) : "", 0);
			final max = parseNonNegativeInt(parts.exists("ma" + i) ? parts.get("ma" + i) : "", min);
			final pos:Position = {file: file, min: min, max: max < min ? min : max};

			final path = new Array<{pos:Position, name:String}>();
			for (segment in pathText.split(".")) {
				final trimmed = StringTools.trim(segment);
				if (trimmed.length == 0)
					continue;
				path.push({pos: pos, name: trimmed});
			}
			if (path.length == 0)
				continue;

			final modeKey = "m" + i;
			final aliasKey = "a" + i;
			final modeText = parts.exists(modeKey) ? parts.get(modeKey) : "";
			final aliasText = parts.exists(aliasKey) ? parts.get(aliasKey) : "";
			final entry:ImportExpr = cast {
				path: path,
				mode: if (modeText == "all") {
					IAll;
				} else if (modeText == "alias") {
					IAsName(aliasText);
				} else {
					INormal;
				}
			};
			out.push(entry);
		}
		return out;
	}

	/**
		Return the compiler-provided current macro position.

		Why
		- Runtime macro modules use `Context.currentPos()` for diagnostics and for position helper APIs.
		- In the external-host model, only the compiler process knows the best current callsite fallback.

		What
		- Returns a deterministic `{file,min,max}` position.
		- Falls back to `<macro>:0-0` if the compiler has not seeded a more specific location yet.
	**/
	public static function currentPos():Position {
		final payload = HostToCompilerRpc.call("context.currentPos", "");
		if (payload == null || payload.length == 0)
			return {file: DEFAULT_MACRO_FILE, min: 0, max: 0};
		final parts = Protocol.kvParse(payload);
		return {
			file: parts.exists("f") && parts.get("f").length > 0 ? parts.get("f") : DEFAULT_MACRO_FILE,
			min: parseNonNegativeInt(parts.exists("mi") ? parts.get("mi") : "", 0),
			max: parseNonNegativeInt(parts.exists("ma") ? parts.get("ma") : "", 0)
		};
	}

	/**
		Return the current display mode for runtime macro code.

		Why
		- Some upstream-ish helper code probes `Context.getDisplayMode()` to branch between display
		  and normal compilation behavior.
		- The current external-host bring-up does not execute real display requests, so `None` is the
		  only honest answer today.
	**/
	public static function getDisplayMode():DisplayMode {
		return DisplayMode.None;
	}

	/**
		Return whether the current display position is within `pos`.

		Why
		- Some macro helpers probe `Context.containsDisplayPosition(...)` before attempting display-only
		  behavior.
		- The external-host bring-up currently has no real display requests or display cursor state.

		What
		- Always returns `false` in runtime mode.

		Gotchas
		- This is an honest "no display session is active" rung, not partial display parity.
	**/
	public static function containsDisplayPosition(pos:Position):Bool {
		if (pos != null) {}
		return false;
	}

	public static function getPosInfos(p:Position):{min:Int, max:Int, file:String} {
		if (p == null)
			return currentPos();
		return {
			file: p.file == null || p.file.length == 0 ? DEFAULT_MACRO_FILE : p.file,
			min: p.min < 0 ? 0 : p.min,
			max: p.max < 0 ? 0 : p.max
		};
	}

	public static function makePosition(inf:{min:Int, max:Int, file:String}):Position {
		return {
			file: inf == null || inf.file == null || inf.file.length == 0 ? DEFAULT_MACRO_FILE : inf.file,
			min: inf == null || inf.min < 0 ? 0 : inf.min,
			max: inf == null || inf.max < 0 ? 0 : inf.max};
	}

	static function parseOptionalTypeSnapshot(method:String):Null<Type> {
		final payload = HostToCompilerRpc.call(method, "");
		if (payload == null)
			return null;
		return RuntimeMacroTypes.parseTypeText(payload);
	}

	/**
		Return the fields of the class currently being built (Stage4 bring-up subset).

		Why
		- Many upstream build macros begin by calling `Context.getBuildFields()` and then either
		  return the same list or push additional fields.
		- Our bring-up ABI does not transport full typed AST yet, but we can still provide a
		  minimal field list so these macros can run.

		What
		- Returns `Array<haxe.macro.Expr.Field>` values with:
		  - `name`, `access`, `kind`, and `pos`
		  - `FFun` bodies are stubbed with a trivial `null` expression so `ExprTools.map`-style
			traversals do not crash on `null` bodies.

		How
		- Reverse RPC `context.getBuildFields` returns a length-prefixed fragment list:
		  `c=<count> n0=<name> k0=<kind> s0=<0|1> v0=<visibility> ...`
	**/
	public static function getBuildFields():Array<Field> {
		final payload = HostToCompilerRpc.call("context.getBuildFields", "");
		final out = new Array<Field>();
		final names = new Array<String>();

		if (payload == null || payload.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return out;
		}

		final m = Protocol.kvParse(payload);
		final countStr = m.exists("c") ? m.get("c") : "";
		final count = Std.parseInt(countStr);
		if (count == null || count < 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return out;
		}

		final nullExpr:Expr = {expr: EConst(CIdent("null")), pos: null};

		for (i in 0...count) {
			final nKey = "n" + i;
			final kKey = "k" + i;
			final sKey = "s" + i;
			final vKey = "v" + i;
			if (!m.exists(nKey))
				continue;

			final name = m.get(nKey);
			if (name.length == 0)
				continue;

			final kind = m.exists(kKey) ? m.get(kKey) : "";
			final isStatic = m.exists(sKey) && m.get(sKey) == "1";
			final vis = m.exists(vKey) ? m.get(vKey) : "";

			final access = new Array<Access>();
			if (vis == "Public")
				access.push(APublic)
			else
				access.push(APrivate);
			if (isStatic)
				access.push(AStatic);

			final field:Field = {
				name: name,
				access: access,
				kind: (kind == "var") ? FVar(null, null) : FFun({args: [], expr: nullExpr}),
				pos: null
			};
			out.push(field);
			names.push(name);
		}

		MacroRuntime.setCurrentBuildFieldNames(names);
		return out;
	}
}
