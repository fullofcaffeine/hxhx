/**
	One exact typed local as exposed through the temporary source-shaped backend
	migration boundary.

	`projectedName` is only a function-local transport name. The authoritative
	identity and semantic type remain on `binding`; a backend must not infer them
	from the transport spelling.
**/
class TypedBackendLocalProjection {
	final projectedName:String;
	final binding:TyLocalBinding;

	public function new(projectedName:String, binding:TyLocalBinding) {
		if (projectedName == null || projectedName.length == 0)
			throw "typed backend local projection requires a transport name";
		if (binding == null)
			throw "typed backend local projection requires an exact binding";
		this.projectedName = projectedName;
		this.binding = binding;
	}

	public function getProjectedName():String
		return projectedName;

	public function getBinding():TyLocalBinding
		return binding;
}
