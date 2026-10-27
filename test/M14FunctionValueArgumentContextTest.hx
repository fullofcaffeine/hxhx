import sys.io.File;

/** Known function values reuse parameter context without inventing a method declaration or fixing open generic binders. */
class M14FunctionValueArgumentContextTest {
	static final providers = [
		{path: "Node.hx", source: 'enum Node{Empty;Text(value:String);}'},
		{path: "Other.hx", source: 'enum Other{Empty;}'},
		{path: "Choice.hx", source: 'enum Choice<T>{None;Some(value:T);}'}
	];

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Compare independently authored source with upstream, then inspect the original callable and enum identities. */
	static function check(name:String, members:String, accepted:Bool, ?bindingName:String, ?enumOwner:String, ?applied:String):Void {
		final root = ".tmp/function-value-argument-" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = members;
		File.saveContent(path, source);
		for (provider in providers)
			File.saveContent(root + "/" + provider.path, provider.source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		final output = upstream.stdout.readAll().toString() + upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		require((status == 0) == accepted, "upstream function-value contract differs: " + name + output);
		var typed:Null<TypedModule> = null;
		try {
			typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			require(error.message.indexOf("compatib") >= 0
				|| error.message.indexOf("conflict") >= 0
				|| error.message.indexOf("should be") >= 0,
				"unrelated rejection: "
				+ name
				+ ": "
				+ error.message);
		}
		require((typed != null) == accepted, "local function-value contract differs: " + name);
		if (typed != null) {
			var calls = 0;
			var fields = 0;
			function expression(value:TypedExpr):Void {
				if (value.getTag() == Call) {
					final callee = value.getExpressions()[0];
					for (binding in callee.getLocalBindings())
						if (binding.getSourceName() == bindingName) {
							require(value.getDeclaration() == null, "function value acquired an invented method declaration");
							require(binding.getCanonicalIdentity().indexOf("#local:") >= 0
								&& callee.getType().isFunction(), "local callable identity lost");
							require(!callee.getType().hasUnknownComponent(), "captured callable did not resolve its original inference variables");
							if (applied != null && enumOwner == null)
								require(callee.getType().getSemanticKey().indexOf(applied) >= 0, "generic capture did not retain concrete input evidence");
							calls++;
						}
				}
				final field = value.getFieldInfo();
				if (field != null && field.getOwner().getCanonicalName() == enumOwner) {
					require(field.getCanonicalKey() == enumOwner + "#static#" + field.getName(), "selected enum field identity changed");
					require(value.getType().getNominalIdentity().getCanonicalName() == enumOwner, "argument owner differs from selected field");
					if (applied != null) {
						require(value.getType().getTypeArguments()[0].getSemanticKey() == TyType.fromHintText(applied).getSemanticKey(),
							"generic singleton lost owner application");
						require(field.getType().getTypeArguments()[0].getTypeParameterIdentity() != null, "original field binder was replaced");
					}
					fields++;
				}
				if (value.getTag() == Call
					&& value.getDeclaration() != null
					&& value.getDeclaration().getSignature().getName() == "Text") {
					require(value.getDeclaration().getOwner().getCanonicalName() == "Node", "payload constructor changed enum owner");
					fields++;
				}
				for (child in value.getExpressions())
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (body in method.getBody().getStatements())
						statement(body);
			if (bindingName != null)
				require(calls > 0, "no original callable observed: " + name);
			if (enumOwner != null)
				require(fields > 0, "no exact enum argument observed: " + name);
			typed.getBackendProjection();
		}
		Sys.println("FUNCTION_VALUE_ARGUMENT_CONTEXT:PASS " + name);
	}

	/** Rest and omitted positions remain with alignment; complete aliases retain their original application. */
	static function checkAdmission():Void {
		final modules = [
			new ResolvedModule("Node", "Node.hx", ParserStage.parse(providers[0].source, "Node.hx"))
		];
		final index = TyperIndex.build(modules);
		final selected = TyType.nominal(new TyNominalTypeId("Node"), []);
		function signature(rest:Bool, optional:Bool):TyCallableSignature {
			return TyCallableSignature.fromFunctionValue(TyType.functionSignature([
				{
					name: "value",
					type: selected,
					isOptional: optional,
					isRest: rest,
					metadata: []
				}
			], TyType.fromHintText("Void")));
		}
		final fixed = signature(false, false);
		require(fixed.getDeclaration() == null
			&& fixed.getMethodTypeParameters().length == 0, "function row fabricated declaration facts");
		require(TyCallArgumentContext.functionValue(fixed, 1, index)[0].getSemanticKey() == selected.getSemanticKey(), "fixed row lost enum context");
		require(TyCallArgumentContext.functionValue(signature(true, false), 1, index)[0] == null, "rest row gained positional context");
		require(TyCallArgumentContext.functionValue(signature(false, true), 0, index).length == 0, "omitted row invented an operand");
		Sys.println("FUNCTION_VALUE_ARGUMENT_CONTEXT:PASS admission");
	}

	/** Observe local and captured calls, exact payloads, and source operand order in generated JavaScript. */
	static function checkRuntime():Void {
		final source = 'class Main{static var effects:String="";'
			+ 'static function apply<T>(callback:T->T):T->T{return callback;}'
			+ 'static function text():String{effects+="v";return "payload";}'
			+ 'static function main():Void{'
			+ 'function take(value:Node):Void{effects+="n";switch(value){case Empty:trace("node");case Text(text):trace(text);}}'
			+ 'var copy=take;copy(Empty);copy(Text(text()));'
			+ 'var other=function(value:Other):Void{effects+="o";switch(value){case Empty:trace("other");}};other(Empty);'
			+ 'var captured=apply;var callback=captured(function(value:Int):Int{return value+1;});trace(callback(7));trace(effects);}}';
		final root = ".tmp/function-value-argument-runtime";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		for (provider in providers)
			File.saveContent(root + "/" + provider.path, provider.source);
		final expected = "node\npayload\nother\n8\nnvno\n";
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		require(status == 0
			&& errors == ""
			&& output == expected.split("\n")
				.filter(line -> line != "")
				.map(line -> root + "/Main.hx:1: " + line + "\n")
				.join(""),
			"upstream runtime differs: "
			+ output
			+ errors);
		final modules = [
			new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"))
		].concat([
			for (provider in providers.slice(0, 2))
				new ResolvedModule(provider.path.substr(0, provider.path.length - 3), root + "/" + provider.path,
					ParserStage.parse(provider.source, root + "/" + provider.path))
		]);
		final index = TyperIndex.build(modules);
		JsRuntimeFixture.assertProgramRuntime(new MacroExpandedProgram([for (module in modules) TyperStage.typeResolvedModule(module, index)], false), "Main",
			expected);
		Sys.println("FUNCTION_VALUE_ARGUMENT_CONTEXT:PASS generated_runtime");
	}

	static function main():Void {
		checkAdmission();
		final local = 'function take(value:Node):Node{return value;}';
		for (entry in [
			{
				name: "named",
				body: local + 'take(Empty);',
				binding: "take",
				owner: "Node"
			},
			{
				name: "copy",
				body: local + 'var copy=take;copy(Empty);',
				binding: "copy",
				owner: "Node"
			},
			{
				name: "anonymous",
				body: 'var take=function(value:Node):Node{return value;};take(Empty);',
				binding: "take",
				owner: "Node"
			},
			{
				name: "payload",
				body: local + 'take(Text("ok"));',
				binding: "take",
				owner: "Node"
			},
			{
				name: "recursive",
				body: 'function take(count:Int,value:Node):Node{if(count>0)return take(count-1,Empty);return value;}take(0,Node.Empty);',
				binding: "take",
				owner: "Node"
			},
			{
				name: "qualified",
				body: local + 'take(Node.Empty);',
				binding: "take",
				owner: "Node"
			}
		])
			check(entry.name, 'class Main{static function main():Void{' + entry.body + '}}', true, entry.binding, entry.owner);
		for (entry in [
			{name: "wrong_owner", body: 'take(Other.Empty);'},
			{name: "wrong_string", body: 'take("wrong");'},
			{name: "no_context", body: 'var value=Empty;take(value);'}
		])
			check(entry.name, 'class Main{static function main():Void{' + local + entry.body + '}}', false);
		check("nullable_alias", 'typedef Selected=Null<Node>;class Main{static function main():Void{var take=function(value:Selected):Void{};take(Empty);}}',
			true, "take", "Node");
		check("generic_singleton",
			'typedef Selected=Null<Choice<String>>;class Main{static function main():Void{var take=function(value:Selected):Void{};take(None);}}', true,
			"take", "Choice", "String");
		check("generic_wrong_payload", 'class Main{static function main():Void{var take=function(value:Choice<String>):Void{};take(Choice.Some(1));}}', false);
		check("generic_method_callback",
			'class Main{static function apply<T>(callback:T->T):T->T{return callback;}static function main():Void{var captured=apply;var callback=captured(function(value:Int):Int{return value+1;});var observed:Int=callback(7);}}',
			true, "captured", null, "primitive:Int");
		check("generic_method_enum",
			'class Main{static function same<T>(value:Choice<T>):Choice<T>{return value;}static function main():Void{var captured=same;var selected:Choice<String>=captured(Choice.Some("ok"));}}',
			true, "captured", null, "primitive:String");
		check("generic_method_array",
			'class Main{static function same<T>(value:Array<T>):Array<T>{return value;}static function main():Void{var captured=same;var selected:Array<Int>=captured([7]);}}',
			true, "captured", null, "primitive:Int");
		check("temporal_collection",
			'class Main{static function same<T>(value:Array<T>):Array<T>{return value;}static function main():Void{var captured=same;var selected=captured([null]);selected.push(7);var result:Null<Int>=selected[0];}}',
			true, "captured");
		checkRuntime();
	}
}
