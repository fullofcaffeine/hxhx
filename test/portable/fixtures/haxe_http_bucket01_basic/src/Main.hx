class Main {
	static function main() {
		final http = new haxe.Http("http://example.invalid/path");
		http.setHeader("X-Test", "1");
		http.setParameter("q", "hxhx");
		Sys.println("http.url=" + http.url);

		final responseData = http.responseData;
		Sys.println("http.response.null=" + (responseData == null));

		final method:haxe.http.HttpMethod = haxe.http.HttpMethod.Post;
		final methodString:String = method;
		Sys.println("method.post=" + methodString);

		final status:haxe.http.HttpStatus = haxe.http.HttpStatus.OK;
		final statusInt:Int = status;
		Sys.println("status.ok=" + statusInt);

		final httpJsClass = Type.resolveClass("haxe.http.HttpJs");
		Sys.println("httpjs.class=" + (httpJsClass != null));

		final httpNodeJsClass = Type.resolveClass("haxe.http.HttpNodeJs");
		Sys.println("httpnode.class=" + (httpNodeJsClass != null));
	}
}
