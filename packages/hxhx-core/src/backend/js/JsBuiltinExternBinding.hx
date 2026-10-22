package backend.js;

/** Existing target-owned host adapters, shared by reference planning and rendering.
	Ordinary extern paths belong to JsExternBinding. This module preserves the
	built-in bindings during that distinction; it does not infer compiler types.
 */
function owns(fullName:String):Bool {
	return isNativeJsGlobalExtern(fullName) || nativeJsNodeRequireExternRef(fullName) != null || fullName == "js.Browser";
}

inline function isNativeJsLibExtern(fullName:String):Bool {
	return fullName != null && StringTools.startsWith(fullName, "js.lib.");
}

inline function isNativeJsHtmlExtern(fullName:String):Bool {
	return fullName != null && StringTools.startsWith(fullName, "js.html.");
}

inline function isNativeJsGlobalExtern(fullName:String):Bool {
	return isNativeJsLibExtern(fullName) || isNativeJsHtmlExtern(fullName);
}

function nativeJsNodeRequireExternRef(fullName:String):Null<String> {
	return switch (fullName) {
		case "js.node.buffer.Buffer":
			"require(\"buffer\").Buffer";
		case "js.node.buffer.SlowBuffer":
			"require(\"buffer\").SlowBuffer";
		case "js.node.console.Console":
			"require(\"console\").Console";
		case "js.node.url.URL":
			"require(\"url\").URL";
		case "js.node.url.URLSearchParams":
			"require(\"url\").URLSearchParams";
		case _:
			null;
	}
}

/**
	Provides the runtime facade for `js.Browser`.

	Why
	- Upstream JS treats `js.Browser.console` as a shortcut to the selected JS
	  global's `console` object.
	- Emitting `js.Browser` as an owned Haxe class initializes recovered static
	  extern fields to `null`, so `js.Browser.console.log(...)` crashes under Node.

	What
	- Binds the recovered class symbol to a small facade over the active JS global.
	- Keeps static field emission disabled for this extern, preventing synthetic
	  `null` assignments from overwriting host-provided globals.
**/
function nativeJsBrowserExternRef(fullName:String):Null<String> {
	if (fullName != "js.Browser")
		return null;
	return [
		"(function() {",
		" var __hx_global = (typeof window !== \"undefined\") ? window : ((typeof global !== \"undefined\") ? global : ((typeof self !== \"undefined\") ? self : globalThis));",
		" return {",
		"self: __hx_global,",
		"window: __hx_global.window,",
		"document: __hx_global.document,",
		"location: __hx_global.location,",
		"navigator: __hx_global.navigator,",
		"console: __hx_global.console,",
		"supported: (typeof __hx_global.window !== \"undefined\" && __hx_global.window.location != null && typeof __hx_global.window.location.protocol === \"string\")",
		"};",
		" })()"
	].join("");
}

function nativeJsGlobalExternRef(fullName:String):String {
	if (isNativeJsHtmlExtern(fullName))
		return nativeJsSimpleGlobalRef(fullName.split(".").pop());
	return nativeJsLibGlobalRef(fullName);
}

function nativeJsSimpleGlobalRef(globalName:String):String {
	final quoted = JsNameMangler.quoteString(globalName);
	return "((globalThis != null && globalThis[" + quoted + "] != null) ? globalThis[" + quoted + "] : {})";
}

function nativeJsLibGlobalRef(fullName:String):String {
	final suffix = fullName.substr("js.lib.".length);
	final parts = suffix.split(".");
	var expr = "globalThis";
	var guard = "(globalThis != null)";
	for (i in 0...parts.length) {
		final part = parts[i];
		if (part == null || part.length == 0)
			continue;
		final globalPart = switch ([i, part]) {
			case [0, "intl"]: "Intl";
			case _: part;
		};
		expr += "[" + JsNameMangler.quoteString(globalPart) + "]";
		guard = "(" + guard + " && " + expr + " != null)";
	}
	return "(" + guard + " ? " + expr + " : {})";
}
