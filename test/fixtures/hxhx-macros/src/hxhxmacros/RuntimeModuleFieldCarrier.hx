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
