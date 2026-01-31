/**
	A placeholder “typed module”.

	In a real compiler, this would contain typed AST nodes and symbol tables.
**/
class TypedModule {
	final parsed:ParsedModule;

	public function new(parsed:ParsedModule) {
		this.parsed = parsed;
	}

	public function getParsed():ParsedModule {
		return parsed;
	}
}

