package reflaxe.ocaml.ast;

/**
	Orders type groups before the declarations that refer to them.

	An enum payload and a class field may refer to each other. Their declarations
	must share one OCaml `type ... and ...` group. A strongly connected dependency
	component supplies that group; dependencies outside it are emitted first.
	Groups with multiple records retain the existing rejection because generated
	class records share the `__hx_type` label. Independent declarations retain
	the existing stable traversal order.
**/
class OcamlTypeDeclarationPlanner {
	/** Returns declarations in the stable order that OCaml can compile. */
	public static function plan(declarations:Array<OcamlTypeDecl>):Array<Array<OcamlTypeDecl>> {
		final declarationIndexByName:Map<String, Int> = [];
		for (index in 0...declarations.length) {
			final name = declarations[index].name;
			if (declarationIndexByName.exists(name))
				throw 'reflaxe.ocaml [ocaml-type-order:duplicate]: generated type "$name" has more than one declaration in one OCaml module';
			declarationIndexByName.set(name, index);
		}

		final dependencies:Array<Array<Int>> = [];
		for (declaration in declarations) {
			final names:Map<String, Bool> = [];
			collectDeclarationDependencies(declaration, names);
			final indexes:Array<Int> = [];
			for (name in names.keys()) {
				final dependencyIndex = declarationIndexByName.get(name);
				if (dependencyIndex != null)
					indexes.push(dependencyIndex);
			}
			indexes.sort(compareInt);
			dependencies.push(indexes);
		}

		final discovery = [for (_ in 0...declarations.length) -1];
		final low = [for (_ in 0...declarations.length) -1];
		final active = [for (_ in 0...declarations.length) false];
		final stack:Array<Int> = [];
		final ordered:Array<Array<OcamlTypeDecl>> = [];
		var nextDiscovery = 0;
		function visit(index:Int):Void {
			discovery[index] = nextDiscovery;
			low[index] = nextDiscovery++;
			stack.push(index);
			active[index] = true;
			for (dependency in dependencies[index]) {
				if (discovery[dependency] < 0) {
					visit(dependency);
					if (low[dependency] < low[index])
						low[index] = low[dependency];
				} else if (active[dependency] && discovery[dependency] < low[index])
					low[index] = discovery[dependency];
			}
			if (low[index] != discovery[index])
				return;
			final members:Array<Int> = [];
			var member:Int;
			do {
				member = stack.pop();
				active[member] = false;
				members.push(member);
			} while (member != index);
			members.sort(compareInt);
			final group = members.map(memberIndex -> declarations[memberIndex]);
			var records = 0;
			for (declaration in group)
				switch (declaration.kind) {
					case Record(_):
						records++;
					case _:
				}
			if (records > 1)
				throw "reflaxe.ocaml [ocaml-type-order:unsupported-cycle]: generated class carriers "
					+ group.map(declaration -> declaration.name).join(", ")
					+ " depend on each other in one OCaml module; their shared __hx_type record field prevents a valid recursive type group";
			ordered.push(group);
		}

		for (index in 0...declarations.length)
			if (discovery[index] < 0)
				visit(index);
		return ordered;
	}

	static function collectDeclarationDependencies(declaration:OcamlTypeDecl, dependencies:Map<String, Bool>):Void {
		switch (declaration.kind) {
			case Alias(type):
				collectTypeDependencies(type, dependencies);
			case Record(fields):
				for (field in fields)
					collectTypeDependencies(field.typ, dependencies);
			case Variant(constructors):
				for (constructor in constructors)
					for (argument in constructor.args)
						collectTypeDependencies(argument, dependencies);
		}
	}

	static function collectTypeDependencies(type:OcamlTypeExpr, dependencies:Map<String, Bool>):Void {
		switch (type) {
			case TIdent(name):
				dependencies.set(name, true);
			case TApp(name, parameters):
				dependencies.set(name, true);
				for (parameter in parameters)
					collectTypeDependencies(parameter, dependencies);
			case TRuntimeApp(_, parameters):
				for (parameter in parameters)
					collectTypeDependencies(parameter, dependencies);
			case TArrow(from, to):
				collectTypeDependencies(from, dependencies);
				collectTypeDependencies(to, dependencies);
			case TTuple(items):
				for (item in items)
					collectTypeDependencies(item, dependencies);
			case TRecord(fields):
				for (field in fields)
					collectTypeDependencies(field.typ, dependencies);
			case TRuntimeIdent(_) | TVar(_):
		}
	}

	static inline function compareInt(left:Int, right:Int):Int
		return left - right;
}
