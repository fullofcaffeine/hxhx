package reflaxe.ocaml.ast;

/**
	Orders type declarations before the declarations that refer to them.

	This target cannot group mutually recursive class records because all records
	contain the same `__hx_type` label. The planner rejects that cycle before file
	publication. It preserves source order when no dependency requires a change.
**/
class OcamlTypeDeclarationPlanner {
	/** Returns declarations in the stable order that OCaml can compile. */
	public static function plan(declarations:Array<OcamlTypeDecl>):Array<OcamlTypeDecl> {
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

		final state = [for (_ in 0...declarations.length) 0];
		final stack:Array<Int> = [];
		final ordered:Array<OcamlTypeDecl> = [];
		function visit(index:Int):Void {
			if (state[index] == 2)
				return;
			if (state[index] == 1) {
				final cycleStart = stack.indexOf(index);
				final cycleIndexes = stack.slice(cycleStart < 0 ? 0 : cycleStart);
				cycleIndexes.sort(compareInt);
				final names = cycleIndexes.map(cycleIndex -> declarations[cycleIndex].name);
				throw "reflaxe.ocaml [ocaml-type-order:unsupported-cycle]: generated class carriers "
					+ names.join(", ")
					+ " depend on each other in one OCaml module; their shared __hx_type record field prevents a valid recursive type group";
			}

			state[index] = 1;
			stack.push(index);
			for (dependency in dependencies[index]) {
				// One OCaml type declaration can refer to itself without a recursive group.
				if (dependency != index)
					visit(dependency);
			}
			stack.pop();
			state[index] = 2;
			ordered.push(declarations[index]);
		}

		for (index in 0...declarations.length)
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
