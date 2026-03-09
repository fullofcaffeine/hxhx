package hxhx.macro;

/**
	Runtime effect sink used by in-process generated macro entrypoints.

	Why
	- The generated-entrypoint registry needs a tiny compiler-effect surface without
	  depending on the external-host RPC client.
	- On the OCaml backend, this sink must also avoid interface record casts for the
	  same reason as `MacroRuntimeSession`: concrete stateful classes cannot be
	  exposed safely as smaller record-shaped interfaces.

	What
	- Defines the current bring-up effect surface: defines, classpaths, emitted
	  OCaml modules, build-field snippets, and hook registration.

	How
	- Inproc runtime code builds an exact-shape anonymous sink object that forwards
	  into `MacroState` and local hook arrays.
**/
typedef InProcMacroEffectSink = {
	function setDefine(name:String, value:String):Void;
	function definedValue(name:String):String;
	function addClassPath(path:String):Void;
	function emitOcamlModule(name:String, source:String):Void;
	function emitBuildFields(modulePath:String, membersSource:String):Void;
	function registerAfterTypingHook(cb:Void->Void):Void;
	function registerOnGenerateHook(cb:Void->Void):Void;
	function registerAfterGenerateHook(cb:Void->Void):Void;
}
