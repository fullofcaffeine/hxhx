class Main {
	static function main():Void {
		final specs:Array<MetaBase> = [];
		for (spec in MetaBuilder.generate("Utf8,Plain"))
			specs.push(spec);
		for (spec in specs)
			spec.test();
	}
}
