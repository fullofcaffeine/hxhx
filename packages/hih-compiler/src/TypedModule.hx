/**
	A placeholder “typed module”.

	In a real compiler, this would contain typed AST nodes and symbol tables.
**/
class TypedModule {
	final parsed:ParsedModule;
	final env:TyModuleEnv;

	public function new(parsed:ParsedModule, env:TyModuleEnv) {
		this.parsed = parsed;
		this.env = env;
	}

	public function getParsed():ParsedModule {
		return parsed;
	}

	public function getEnv():TyModuleEnv {
		return env;
	}
}
