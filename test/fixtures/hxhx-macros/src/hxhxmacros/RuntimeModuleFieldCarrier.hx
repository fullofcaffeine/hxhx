package hxhxmacros;

@:router
function routerMarker():String {
	return "router";
}

@:schema
function schemaMarker():String {
	return "schema";
}

@:routeTag
final routeTag = "router";

@:retry
final retryCount = 3;

@:enabled
var featureEnabled = true;

@:summary
function renderSummary(label:String, retryCount:Int):String {
	return label + ":" + retryCount;
}

@:sourceTag
final sourceTag = "from-source".toUpperCase();
