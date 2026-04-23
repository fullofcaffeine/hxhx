package hxhx;

import hxhx.macro.MacroRuntimeSession;

/**
	Shared Stage3 macro-hook execution helpers.

	Why
	- `Stage3Compiler` runs the same macro hook phases in both the type-only and
	  full emit lanes.
	- Keeping that sequencing inline duplicates the failure handling and logging
	  contracts that tests already rely on.

	What
	- Executes the standard Stage3 hook phases in order:
	  - `afterTyping`
	  - `onGenerate`
	  - `afterGenerate`
	- Preserves the existing `hook_<phase>[i]=ok` logging.

	How
	- Reads the hook IDs from `MacroState`.
	- Returns the exact Stage3 error string on failure so callers can keep their
	  existing close-and-return behavior.
**/
class Stage3HookSupport {
	static function runHookPhase(session:MacroRuntimeSession, phase:String, hookIds:Array<Int>):Null<String> {
		for (i in 0...hookIds.length) {
			try {
				session.runHook(phase, hookIds[i]);
			} catch (e:String) {
				return phase + " hook failed: " + e;
			}
			Sys.println("hook_" + phase + "[" + i + "]=ok");
		}
		return null;
	}

	public static function runStandardMacroHooks(session:Null<MacroRuntimeSession>):Null<String> {
		if (session == null)
			return null;

		final afterTypingError = runHookPhase(session, "afterTyping", hxhx.macro.MacroState.listAfterTypingHookIds());
		if (afterTypingError != null)
			return afterTypingError;

		final onGenerateError = runHookPhase(session, "onGenerate", hxhx.macro.MacroState.listOnGenerateHookIds());
		if (onGenerateError != null)
			return onGenerateError;

		return runHookPhase(session, "afterGenerate", hxhx.macro.MacroState.listAfterGenerateHookIds());
	}
}
