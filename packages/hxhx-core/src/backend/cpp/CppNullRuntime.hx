package backend.cpp;

/**
	Test null after a generic C++ carrier is instantiated, without numeric conversion.

	Ordinary value carriers have no null state. Pointers, optional storage, and
	callables expose their own absence state. Erased values retain the existing
	runtime contract: an empty std::any or a stored nullptr represents null.
	Emit this block after that erased-value helper and before authored functions.
	The function call evaluates its operand once, even for a non-nullable carrier.
**/
function lines():Array<String> {
	return [
		"template<typename T>",
		"static bool __hxhx_generic_is_null(const T&) { return false; }",
		"static bool __hxhx_generic_is_null(std::nullptr_t) { return true; }",
		"static bool __hxhx_generic_is_null(const std::any& value) { return __hxhx_any_is_null_like(value); }",
		"template<typename T>",
		"static bool __hxhx_generic_is_null(T* value) { return value == nullptr; }",
		"template<typename T>",
		"static bool __hxhx_generic_is_null(const std::shared_ptr<T>& value) { return value == nullptr; }",
		"template<typename T>",
		"static bool __hxhx_generic_is_null(const std::optional<T>& value) { return !value.has_value(); }",
		"template<typename R, typename... Args>",
		"static bool __hxhx_generic_is_null(const std::function<R(Args...)>& value) { return !value; }"
	];
}
