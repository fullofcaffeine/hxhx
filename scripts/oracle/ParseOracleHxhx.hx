import haxe.macro.Expr;

/** One exported body, or the reason it could not be exported. */
typedef ParseOracleRecord = {key:String, ?body:String, ?error:String};

/**
	hxhx side of the frontend parse oracle. Runs under `haxe --interp` with the hxhx-core sources.

	For every file in the upstream dump it applies the same defines with hxhx's conditional
	compilation, parses the result with `ParserStage`, exports each function body and field
	initializer with `MacroBodyExport`, and prints it with `haxe.macro.Printer`. A file that does
	not parse, or a body that cannot be exported, is recorded with its error, never skipped.

	Usage: `ParseOracleHxhx <upstream.json> <out.json>`
**/
class ParseOracleHxhx {
	/**
		One function body as the oracle prints it. Upstream's recorder sees an abstract constructor
		only through its generated wrapper block, which loses the authored bracing, so an abstract's
		`new` is compared as a block (statement content is still compared).
	**/
	public static function functionBody(cls:HxClassDecl, fn:HxFunctionDecl, export:MacroBodyExport, position:Position):String {
		final isAbstract = HxClassDecl.getMetadata(cls).indexOf("__hxhx_abstract") >= 0;
		final braced = HxFunctionDecl.getBodyBraced(fn) || (isAbstract && HxFunctionDecl.getName(fn) == "new");
		return new haxe.macro.Printer().printExpr(ParseOracleNormalize.expr(export.functionBody(HxFunctionDecl.getBody(fn), braced, position)));
	}

	static function main():Void {
		final args = Sys.args();
		if (args.length != 2)
			throw "usage: ParseOracleHxhx <upstream.json> <out.json>";
		final upstream:{defines:Array<{name:String, value:String}>, records:Array<{key:String, file:String, body:String}>} = haxe.Json.parse(sys.io.File.getContent(args[0]));
		final defines = new haxe.ds.StringMap<String>();
		for (entry in upstream.defines)
			defines.set(entry.name, entry.value);
		final files = new Array<String>();
		final seen = new Map<String, Bool>();
		for (record in upstream.records)
			if (!seen.exists(record.file)) {
				seen.set(record.file, true);
				files.push(record.file);
			}
		final records:Array<ParseOracleRecord> = [];
		final fileErrors:Array<{file:String, error:String}> = [];
		final printer = new haxe.macro.Printer();
		for (file in files) {
			final decl = try {
				final filtered = HxConditionalCompilation.filterSource(sys.io.File.getContent(file), defines);
				ParserStage.parseAuthored(filtered, file).getDecl();
			} catch (e:haxe.Exception) {
				fileErrors.push({file: file, error: e.message});
				continue;
			}
			final packagePath = HxModuleDecl.getPackagePath(decl);
			final base = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(file));
			final module = packagePath.length == 0 ? base : packagePath + "." + base;
			final export = new MacroBodyExport(new MacroSyntaxPositions(file));
			final unknown:Position = {file: file, min: 0, max: 0};
			for (cls in HxModuleDecl.getClasses(decl)) {
				final owner = module + "." + HxClassDecl.getName(cls);
				for (fn in HxClassDecl.getFunctions(cls)) {
					if (!HxFunctionDecl.getHasBody(fn))
						continue;
					final key = owner + "." + HxFunctionDecl.getName(fn);
					try {
						records.push({
							key: key,
							body: functionBody(cls, fn, export, unknown)
						});
					} catch (e:haxe.Exception) {
						records.push({key: key, error: e.message});
					}
				}
				for (field in HxClassDecl.getFields(cls)) {
					final value = HxFieldDecl.getInit(field);
					if (value == null)
						continue;
					final key = owner + "." + HxFieldDecl.getName(field);
					try {
						records.push({key: key, body: printer.printExpr(ParseOracleNormalize.expr(export.fieldInitializer(value, unknown)))});
					} catch (e:haxe.Exception) {
						records.push({key: key, error: e.message});
					}
				}
			}
		}
		sys.io.File.saveContent(args[1], haxe.Json.stringify({records: records, fileErrors: fileErrors}));
	}
}
