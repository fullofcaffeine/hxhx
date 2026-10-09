import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Native string reads need a value type before later argument control is evaluated. */
class M14NekoStringReadTypeTest {
	static var nativeReads = 0;
	static var ordinaryReads = 0;

	static function inspect(value:TypedExpr):Void {
		if (value.getTag() == FieldRead && value.getTexts()[0] == '__s') {
			final receiver = value.getExpressions()[0].getType().unwrapNull();
			if (receiver.getSemanticKey() == 'primitive:String') {
				final identity = value.getType().getNominalIdentity();
				if (identity == null || identity.getCanonicalName() != 'neko.NativeString')
					throw 'native string operand has no precise type';
				nativeReads++;
			} else {
				if (value.getType().getSemanticKey() != 'primitive:Int')
					throw 'ordinary __s field changed type';
				ordinaryReads++;
			}
		}
		for (child in value.getExpressions())
			inspect(child);
	}

	static function main():Void {
		final root = '.tmp/neko_string_read_type';
		sys.FileSystem.createDirectory(root);
		sys.FileSystem.createDirectory(root + '/ordinary');
		sys.io.File.saveContent(root + '/ordinary/String.hx', 'package ordinary; class String {public var __s:Int=11; public function new(){}}');
		final source = 'class Main {static function sink(first:Dynamic,second:Dynamic):Void {Sys.println(neko.NativeString.length(cast first));}'
			+ 'static function ordinary(value:{__s:Int}):Int {return value.__s;}'
			+ 'static function named(value:ordinary.String):Int {return value.__s;}'
			+ 'static function nullable(value:Null<String>):Dynamic {return untyped value.__s;}'
			+
			'static function main():Void {var value="abc"; untyped sink(value.__s,if(true) null else value.__s); Sys.println(ordinary({__s:7})); Sys.println(named(new ordinary.String()));}}';
		sys.io.File.saveContent(root + '/Main.hx', source);
		if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
			throw 'upstream compilation failed';
		final process = new sys.io.Process('neko', [root + '/upstream.n']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '3\n7\n11\n')
			throw 'upstream native string contract differs: ' + output + errors;
		final args = Stage1Args.parse(['-cp', root, '-main', 'Main'], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(args),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: 'neko'
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], 'neko', 'neko-native');
		final resolved = ResolverStage.parseProjectRoots(paths, ['Main'], defines);
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		for (module in resolved)
			if (ResolvedModule.getModulePath(module) == 'Main') {
				final typed = TyperStage.typeResolvedModule(module, index, loader, true);
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions()) {
						for (statement in fn.getBody().getStatements())
							for (value in statement.getExpressions())
								inspect(value);
						TypedBodySource.functionProjection(fn);
					}
			}
		if (nativeReads != 3 || ordinaryReads != 2)
			throw 'native string operand coverage changed';
		final otherSource = 'class Main {static function read(value:String):Dynamic {return untyped value.__s;}}';
		final otherModule = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(otherSource, 'Main.hx'));
		final otherTyped = TyperStage.typeResolvedModule(otherModule, TyperIndex.build([otherModule]));
		final result = otherTyped.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0].getExpressions()[0].getType();
		if (result.getNominalIdentity() != null && result.getNominalIdentity().getCanonicalName() == 'neko.NativeString')
			throw 'Neko string representation leaked to another target';
		Sys.println('NEKO_STRING_READ_TYPE:PASS');
	}
}
