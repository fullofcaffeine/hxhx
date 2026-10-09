/** Structural method parameters bind only inside their own signature, including nested methods. */
class M14StructuralMethodBinderTest {
	static function main():Void {
		for (entry in [
			{name: "ordinary", method: 'function map<U>(input:T, callback:T->U):U;'},
			{name: "shadow", method: 'function map<T>(input:T):T;'},
			{name: "nested", method: 'function map<U>(input:T):{function next<V>(outer:U, input:V):V;};'}
		]) {
			final source = 'typedef Contract<T>={var value:T;'
				+ entry.method
				+ '}'
				+ 'abstract Wrapper<T>(Contract<T>) from Contract<T>{}'
				+ 'extern class Holder<T>{public var contract:Null<Contract<T>>;}'
				+ 'class Main{static function main():Void{Sys.println(7);}}';
			final root = '.tmp/structural_method_binder_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--interp']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code != 0 || output != '7\n')
				throw 'upstream structural binder differs: ' + entry.name + output + errors;
			Sys.println('STRUCTURAL_BINDER_UPSTREAM:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
			// Construct every class fact, including unused abstract backing and field types.
			for (owner in typed.getTypedClasses())
				new TypedBackendClassSemanticFacts(owner.getSemanticInfo(), null, owner.getFunctions());
			JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n');
			if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
				throw 'structural binder validation changed typed source';
			Sys.println('STRUCTURAL_BINDER_PROJECTION:PASS ' + entry.name);
		}
		checkScopeIsolation();
	}

	/** Corrupt semantic graphs must not gain permission from another member's same-named binder. */
	static function checkScopeIsolation():Void {
		final owner = new TyNominalTypeId('fixture.Container');
		final enclosing = TyTypeParameterId.nominal(owner, 0, 'T');
		final local = TyTypeParameterId.method(owner, false, 'map', 0, 0, 'T');
		final foreign = TyTypeParameterId.method(owner, false, 'other', 0, 0, 'T');
		function method(name:String, parameters:Array<TyTypeParameterId>, result:TyType):TyAnonymousField {
			return {
				name: name,
				type: TyType.functionType([TyType.typeParameter(enclosing)], result),
				kind: Method(parameters),
				isOptional: false,
				visibility: Public,
				metadata: [],
				position: HxPos.unknown()
			};
		}
		final scoped = TyType.declaredAnonymous([method('map', [local], TyType.typeParameter(local))]);
		final free = TyTypeSubstitution.freeParameterIdentities(scoped);
		if (free.length != 1 || !free[0].equals(enclosing) || TyTypeSubstitution.parameterIdentities(scoped).length != 2)
			throw 'scope scan erased an enclosing parameter or changed the complete substitution scan';
		@:privateAccess TypedBackendClassSemanticFacts.requireDeclaredTypeParameters(scoped, [enclosing], 'valid scope');
		final nested = TyType.declaredAnonymous([
			method('map', [local], TyType.declaredAnonymous([method('next', [foreign], TyType.typeParameter(local))]))
		]);
		@:privateAccess TypedBackendClassSemanticFacts.requireDeclaredTypeParameters(nested, [enclosing], 'nested scope');
		for (entry in [
			{name: 'foreign_same_name', type: TyType.declaredAnonymous([method('map', [local], TyType.typeParameter(foreign))])},
			{
				name: 'sibling_escape',
				type: TyType.declaredAnonymous([
					method('map', [local], TyType.typeParameter(local)),
					TyAnonymousField.inferred('zEscaped', TyType.typeParameter(local))
				])
			},
			{name: 'missing_enclosing', type: scoped}
		]) {
			var rejected = false;
			try {
				@:privateAccess TypedBackendClassSemanticFacts.requireDeclaredTypeParameters(entry.type, entry.name == 'missing_enclosing' ? [] : [enclosing],
					entry.name);
			} catch (message:String) {
				rejected = message.indexOf('unbound type parameter') >= 0;
			}
			if (!rejected)
				throw 'invalid structural binder accepted: ' + entry.name;
			Sys.println('STRUCTURAL_BINDER_NEGATIVE:PASS ' + entry.name);
		}
	}
}
