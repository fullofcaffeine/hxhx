package hxhxmacrohost.api;

import haxe.macro.Expr;
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
	- `getType(name)` is a deliberately small allowlist-backed lookup used to prove the request path.

	How
	- Backed by the compiler define store for `defined*` and `MacroRuntime.builtinTypes` for `getType`.
	- Later stages will replace the allowlist with real typed representations and a macro<->compiler ABI.
**/
class Context {
	public static function defined(name:String):Bool {
		if (name == null) return false;
		final v = HostToCompilerRpc.call("context.defined", Protocol.encodeLen("n", name));
		return v == "1";
	}

	public static function definedValue(name:String):String {
		if (name == null) return "";
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
		if (cb == null) return;
		final id = MacroRuntime.registerAfterTyping(cb);
		final tail = Protocol.encodeLen("k", "afterTyping") + " " + Protocol.encodeLen("i", Std.string(id));
		HostToCompilerRpc.call("compiler.registerHook", tail);
	}

	/**
		Register an "on generate" hook.

		See `onAfterTyping` for bring-up rationale and mechanics.
	**/
	public static function onGenerate(cb:Array<Dynamic>->Void, persistent:Bool = true):Void {
		if (cb == null) return;
		// `persistent` is currently ignored in the bring-up rung (no compilation server).
		final _ = persistent;
		final id = MacroRuntime.registerOnGenerate(cb);
		final tail = Protocol.encodeLen("k", "onGenerate") + " " + Protocol.encodeLen("i", Std.string(id));
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
		if (payload == null || payload.length == 0) return out;

		final m = Protocol.kvParse(payload);
		final countStr = m.exists("c") ? m.get("c") : "";
		final count = Std.parseInt(countStr);
		if (count == null || count <= 0) return out;

		for (i in 0...count) {
			final kKey = "k" + i;
			final vKey = "v" + i;
			if (!m.exists(kKey)) continue;
			out.set(m.get(kKey), m.exists(vKey) ? m.get(vKey) : "");
		}
		return out;
	}

	public static function getType(name:String):String {
		if (name == null || name.length == 0) return "missing";
		return MacroRuntime.builtinTypeDesc(name);
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

		final nullExpr:Expr = { expr: EConst(CIdent("null")), pos: null };

		for (i in 0...count) {
			final nKey = "n" + i;
			final kKey = "k" + i;
			final sKey = "s" + i;
			final vKey = "v" + i;
			if (!m.exists(nKey)) continue;

			final name = m.get(nKey);
			if (name.length == 0) continue;

			final kind = m.exists(kKey) ? m.get(kKey) : "";
			final isStatic = m.exists(sKey) && m.get(sKey) == "1";
			final vis = m.exists(vKey) ? m.get(vKey) : "";

			final access = new Array<Access>();
			if (vis == "Public") access.push(APublic) else access.push(APrivate);
			if (isStatic) access.push(AStatic);

			final field:Field = {
				name: name,
				access: access,
				kind: (kind == "var") ? FVar(null, null) : FFun({ args: [], expr: nullExpr }),
				pos: null
			};
			out.push(field);
			names.push(name);
		}

		MacroRuntime.setCurrentBuildFieldNames(names);
		return out;
	}
}
