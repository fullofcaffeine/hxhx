/** Function-body untyped syntax remains visible after return annotations and through declaration scanning. */
class M14UntypedFunctionBodySyntaxTest {
	static function main():Void {
		final root = '.tmp/untyped_function_body_syntax';
		sys.FileSystem.createDirectory(root);
		final source = '@:build(Observe.build()) class Main{' + 'static function typed():Int untyped{return 1;}'
			+ 'static function inferred() untyped{return 2;}' + 'static function main():Void{}}';
		final observer = 'import haxe.macro.Context;import haxe.macro.Expr;class Observe{'
			+
			'static function shape(e:Expr):String{return switch(e.expr){case EUntyped(inner):"untyped("+shape(inner)+")";case EBlock(_):"block";case _:"other";};}'
			+
			'public static function build():Array<Field>{var fields=Context.getBuildFields();for(field in fields)switch(field.kind){case FFun(fn):Sys.println(field.name+"="+shape(fn.expr));case _:}'
			+
			'var anonymous=Context.parse("function():Int untyped{return 3;}",Context.currentPos());switch(anonymous.expr){case EFunction(_,fn):Sys.println("anonymous="+shape(fn.expr));case _:throw "missing function";}return fields;}}';
		sys.io.File.saveContent(root + '/Main.hx', source);
		sys.io.File.saveContent(root + '/Observe.hx', observer);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--interp']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != 'typed=untyped(block)\ninferred=untyped(block)\nmain=block\nanonymous=untyped(block)\n')
			throw 'upstream untyped syntax differs: ' + output + errors;
		Sys.println('UPSTREAM_UNTYPED_BODY_SYNTAX:PASS');
		checkModule(new HxParser(source).parseModule('Main'));
		checkModule(ParserStage.parse(source, root + '/Main.hx').getDecl());
		switch HxParser.parseCompleteExprText('function():Int untyped{return 3;}') {
			case ESourceFunction(_, EUntyped(ESourceGroup([EReturn(EInt(3))], _)), _, _):
			case _:
				throw 'anonymous function lost its authored untyped body';
		}
		Sys.println('LOCAL_UNTYPED_BODY_SYNTAX:PASS');
	}

	/** The existing expression wrapper owns the permission; the return type remains an ordinary type hint. */
	static function checkModule(module:HxModuleDecl):Void {
		var checked = 0;
		final names = new Array<String>();
		for (owner in HxModuleDecl.getClasses(module))
			for (fn in HxClassDecl.getFunctions(owner)) {
				final name = HxFunctionDecl.getName(fn);
				names.push(name);
				if (name != 'typed' && name != 'inferred')
					continue;
				if (HxFunctionDecl.getReturnTypeHint(fn) != (name == 'typed' ? 'Int' : ''))
					throw 'untyped polluted a return type';
				switch HxFunctionDecl.getBody(fn) {
					case [SExpr(EUntyped(ESourceGroup([EReturn(EInt(value))], _)), _)] if (value == (name == 'typed' ? 1 : 2)):
					case _:
						throw 'declaration lost its authored untyped body: ' + name;
				}
				checked++;
			}
		if (checked != 2 || names.join(",") != "typed,inferred,main")
			throw 'untyped body test lost a declaration';
	}
}
