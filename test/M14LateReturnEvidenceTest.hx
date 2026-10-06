/** Later body constraints must complete early returns without changing their lexical identity. */
class M14LateReturnEvidenceTest {
	static function main():Void {
		check("early", "if(flag)return value; constrain(value); return value;", false);
		check("annotated", "if(flag)return value; constrain(value); return value;", true);
		check("alias", "var alias=value; if(flag)return alias; constrain(value); return alias;", false);
		check("shadow", "if(flag){var alias=value; {var value:String='shadow';} return alias;} constrain(value); return value;", false);
		check("expression", "var ignored = {if(flag)return value; 0;}; constrain(value); return value;", false);
		check("nested", "var other=function():String {return 'nested';}; if(flag)return value; constrain(value); return value;", false);
		checkRejected();
		checkIncomplete();
		checkForkIsolation();
		Sys.println("LATE_RETURN_EVIDENCE:PASS");
	}

	/** A later incompatible use must fail, even if another return already supplies Int evidence. */
	static function checkRejected():Void {
		final source = 'class Main {static function constrain(value:Int):Void {} static function text(value:String):Void {} '
			+ 'static function choose(value,flag:Bool){if(flag)return value; constrain(value); text(value); return 1;}'
			+ 'static function main():Void {choose(7,true);}}';
		final root = '.tmp/late_return_evidence_conflict';
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		upstream.stdout.readAll();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || errors.indexOf('Int should be String') < 0)
			throw 'upstream did not reject conflicting late constraints: ' + errors;
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		var rejected = false;
		try
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]))
		catch (error:TyperError)
			rejected = true;
		if (!rejected)
			throw 'conflicting late constraints were accepted';
	}

	/** A concrete branch does not prove an unrelated unresolved return or an unresolved record field. */
	static function checkIncomplete():Void {
		for (body in ['if(flag)return value; return 1;', 'if(flag)return value.field; return 1;']) {
			final source = 'class Main {static function choose(value,flag:Bool){' + body + '} static function main():Void {}}';
			final module = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(source, 'Main.hx'));
			final index = TyperIndex.build([module]);
			TyperStage.typeResolvedModule(module, index);
			final owner = index.getByFullName('Main');
			if (!index.getMethodBodyResults().result(owner.declarationForSignature(owner.staticMethod('choose'))).isUnknown())
				throw 'missing return evidence was published as complete';
		}
	}

	/** Candidate constraints and copied return collections must not resolve through the parent solver. */
	static function checkForkIsolation():Void {
		final owner = 'late_return_fork';
		final symbol = new TySymbol('value', TyType.unknown(), TyLocalId.forSourceDeclaration(owner, 0, Parameter, 'value'), Parameter);
		final controls = new TyControlScope(owner, 'source');
		final scope = new TyFunctionEnv('choose', [symbol], [], TyType.unknown(), TyType.unknown(), owner, null, false, 0, true, controls);
		scope.getInference().registerOmittedParameter(symbol);
		controls.beginReturns(controls.getRoot(), null);
		final expression = HxExpr.EIdent('value');
		controls.currentReturns().record(scope.getInference().sourceTerm(expression, scope), HxPos.unknown());
		for (name in ['Int', 'String']) {
			final candidate = scope.copyForInference();
			final expected = TyType.fromHintText(name);
			if (!candidate.getInference().constrain([expression], [expected], candidate, TyperIndex.build([])))
				throw 'candidate constraint failed';
			final copiedControls = candidate.requireControlScope();
			final returns = copiedControls.finishReturns(copiedControls.getRoot());
			if (returns.length != 1 || candidate.getInference().termType(returns[0].term).getSemanticKey() != expected.getSemanticKey())
				throw 'copied return used the wrong inference owner';
		}
		final returns = controls.finishReturns(controls.getRoot());
		if (returns.length != 1 || !scope.getInference().termType(returns[0].term).isUnknown())
			throw 'speculative inference changed the original return';
	}

	/** The upstream interpreter and independently generated JavaScript must agree on both branches. */
	static function check(name:String, body:String, annotated:Bool):Void {
		final source = 'class Main {static function constrain(value:Int):Void {} static function choose(value'
			+ (annotated ? ':Int' : '')
			+ ',flag:Bool){'
			+ body
			+ '}'
			+ 'static function main():Void {Sys.println(choose(7,true)); Sys.println(choose(8,false));}}';
		final root = '.tmp/late_return_evidence_' + name;
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != '7\n8\n')
			throw 'upstream late-return result differs for ' + name + ': ' + output + errors;
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName('Main');
		final declaration = owner.declarationForSignature(owner.staticMethod('choose'));
		final before = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(declaration.getSourceDeclaration()));
		final typed = TyperStage.typeResolvedModule(module, index);
		final result = index.getMethodBodyResults().result(declaration);
		if (result.getSemanticKey() != 'primitive:Int')
			throw 'early return retained incomplete evidence for ' + name + ': ' + result.getSemanticKey();
		if (before != TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(declaration.getSourceDeclaration())))
			throw 'return inference mutated source';
		JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n8\n');
		Sys.println('LATE_RETURN_CASE:PASS ' + name);
	}
}
