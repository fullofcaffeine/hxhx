# JavaScript quotation values

Run `haxe test/m14_js_macro_quotation_runtime_test.hxml` from the repository root.
The same source must pass upstream Haxe and candidate JavaScript execution.

This retains the quotation inputs from the original switch emitter test.
Assertions inspect real enum constructors and payloads for strings, fields,
the in operator, identifier splicing, both forms of if, function types, and
nested ComplexType construction. The real haxe.macro.Expr provider supplies
constructor declarations. This does not establish source-position parity.

The combined switch gate calls the same QuotationCases module in one typed
program. The standalone command remains available for focused diagnosis.
