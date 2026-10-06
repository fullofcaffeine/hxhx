import HxTypeSyntax.HxTypeSyntaxParameter;

/** Named inputs keep declaration identity, authored type structure, and source range together. */
typedef HxTypedefDeclarationInput = {
	final name:String;
	final visibility:HxVisibility;
	final isExtern:Bool;
	final metadata:Array<String>;
	final parameters:Array<HxTypeSyntaxParameter>;
	final target:HxTypeSyntax;
	final pos:HxPos;
	final endPos:HxPos;
};

/**
	A transparent source type alias, distinct from a runtime class declaration.

	The parser retains the target syntax and binders here. This node does not
	choose a nominal identity or expand the alias. Those operations require the
	defining module's imports and belong to shared type resolution.
**/
class HxTypedefDecl {
	final name:String;
	final visibility:HxVisibility;
	final isExtern:Bool;
	final metadata:Array<String>;
	final parameters:Array<HxTypeSyntaxParameter>;
	final target:HxTypeSyntax;
	final pos:HxPos;
	final endPos:HxPos;

	public function new(input:HxTypedefDeclarationInput) {
		name = input.name;
		visibility = input.visibility;
		isExtern = input.isExtern;
		metadata = input.metadata.copy();
		parameters = HxTypeSyntax.copyParameters(input.parameters);
		target = input.target;
		pos = input.pos;
		endPos = input.endPos;
	}

	public function getName():String
		return name;

	public function getVisibility():HxVisibility
		return visibility;

	public function getIsExtern():Bool
		return isExtern;

	public function getMetadata():Array<String>
		return metadata.copy();

	public function getParameters():Array<HxTypeSyntaxParameter>
		return HxTypeSyntax.copyParameters(parameters);

	public function getTarget():HxTypeSyntax
		return target;

	public function getPos():HxPos
		return pos;

	public function getEndPos():HxPos
		return endPos;
}
