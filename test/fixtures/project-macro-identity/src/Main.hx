/**
	Runtime check for the identity project macro.

	`Identity.preserve` receives the function below as authored syntax and returns it
	unchanged. The function keeps a nested brace group whose explicit `return` must leave
	the whole function, so the code after the group never runs and no event is recorded.
**/
class Main {
	static function main():Void {
		final events = new Array<String>();
		final check = Identity.preserve(function(label:String):String {
			{
				if (label == "ok") {
					return label;
				}
				events.push("inner-fallthrough");
			}
			events.push("after-group");
			return "unreachable";
		});
		Sys.println(check("ok"));
		Sys.println(events.join(","));
	}
}
