class Main {
	static function main():Void {
		// Upstream's TestMain consumes UnitBuilder.generateSpec this way: it iterates the
		// returned literal of `new $tp()` and pushes each instance into a base-typed array.
		final specs:Array<SpecBase> = [];
		for (spec in SpecBuilder.generate("alpha,beta"))
			specs.push(spec);
		for (spec in specs)
			spec.test();
		Sys.println("registry " + SpecBuilder.registry(2));
	}
}
