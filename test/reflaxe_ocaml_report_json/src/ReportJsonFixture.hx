import haxe.Json;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.reports.OcamlReportJson.digest;
import reflaxe.ocaml.reports.OcamlReportJson.render;

/** Independent byte expectations for the report digest encoding on each host. */
class ReportJsonFixture {
	static function main():Void {
		final expected = '{"a":[null,true,false,0,-1,2147483647,-2147483648],"nested":{"a":"quote\\\"\\n","z":"last"},"z":"é"}';
		final first = '{"z":"é","nested":{"z":"last","a":"quote\\\"\\n"},"a":[null,true,false,0,-1,2147483647,-2147483648]}';
		final second = '{"a":[null,true,false,0,-1,2147483647,-2147483648],"z":"é","nested":{"a":"quote\\\"\\n","z":"last"}}';
		// Fixed JSON strings enter and leave the validated serialization boundary here.
		for (source in [first, second]) {
			final actual = encode(Json.parse(source));
			if (actual != expected)
				throw 'Wrong canonical report bytes: $actual';
			// Expected independently from the literal UTF-8 bytes with Python hashlib.
			if (digest(Json.parse(source)) != "sha256:684bf045efe53bb478f8e9ecefe0627c961c978c9b046bd46181b8a9d3d9318d")
				throw "Wrong UTF-8 report digest.";
		}
		if (encode(["second", "first"]) != '["second","first"]')
			throw "Report encoding reordered an array.";
		if (encode(Json.parse('{"é":1,"z":2,"a":3}')) != '{"a":3,"z":2,"é":1}')
			throw "Report encoding used host key order.";
		if (render(Json.parse('{"b":2,"a":1}')) != '{\n  "a": 1,\n  "b": 2\n}')
			throw "Report rendering changed its ordered indentation.";
		if (encode(Json.parse(render(Json.parse(first)))) != expected)
			throw "Report rendering changed a value.";
		if (digest(Json.parse(first)) == digest(Json.parse(StringTools.replace(first, '"last"', '"changed"'))))
			throw "Report digest ignored a changed nested value.";
		var rejected = false;
		try {
			encode(() -> 1);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "Report encoding accepted a function.";
		Sys.println(expected);
		Sys.println(digest(Json.parse(expected)));
		Sys.println("OCAML_REPORT_JSON:PASS");
	}
}
