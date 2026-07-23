/** Filtered source paired with request-specific conditional-compilation evidence. **/
class CompilerConditionalCompilationResult {
	final filteredSource:String;
	final observation:CompilerConditionalCompilationObservation;

	public function new(filteredSource:String, observation:CompilerConditionalCompilationObservation) {
		this.filteredSource = filteredSource;
		this.observation = observation == null ? CompilerConditionalCompilationObservation.empty() : observation;
	}

	public function getFilteredSource():String
		return filteredSource;

	public function getObservation():CompilerConditionalCompilationObservation
		return observation;
}
