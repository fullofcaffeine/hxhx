# Native C++ substring reference

These independently authored programs measure upstream Haxe 4.3.7 with hxcpp
4.3.2. They distinguish native C++ behavior from eval behavior before the
managed C++ runtime implements the operation. No upstream implementation code
was copied or translated.

Use an isolated haxelib repository that already contains hxcpp 4.3.2. Set
`HAXELIB_PATH` to its absolute path, then run the installed Haxe binary directly:

```sh
haxe -cp test/oracle/cpp_string_substr_seed -main Pr92SubstrReference \
  -cpp .tmp/substr-reference -D HXCPP_COMPILE_THREADS=2
.tmp/substr-reference/Pr92SubstrReference
haxe -cp test/oracle/cpp_string_substr_seed -main Pr92SubstrDetails \
  -cpp .tmp/substr-reference -D HXCPP_COMPILE_THREADS=2
.tmp/substr-reference/Pr92SubstrDetails
```

The first program covers 504 combinations of ASCII, empty and Unicode strings,
negative and extreme positions, and omitted, null, negative and extreme lengths.
It also observes operand order and null receiver behavior. The second checks
surrogate halves before byte conversion and narrows the negative-length rule.

Observed native behavior:

- `"Aé😀Z"` has five UTF-16 units. Eval reports four Unicode scalar values.
- `substr(2, 2)` returns the whole emoji. Either half returns U+FFFD, including
  when checked with `charCodeAt` before conversion to bytes.
- For `"abcdef"`, `substr(0, -2)` returns `"abcd"`, `substr(1, -2)` returns
  `"bcde"`, and `substr(2, -2)` returns empty text.
- Omitted or null length selects the remaining text. A null position selects zero.
- A null String returns empty text after receiver, position and length effects
  execute. Eval throws after the receiver effect.

The ordinary regression command is:

```sh
haxe test/m14_cpp_string_substr_test.hxml
```

It uses real String declarations, tests altered ownership/signature facts and
same-named user methods, then executes generated C++ at O0 and O2 with address
and undefined-behavior sanitizers. An independent observer forces collection
between arguments and checks failure order, result publication and root cleanup.
The authored fixture also exercises static and instance field initializers.
The binary-operator integration HXML includes this regression before its original
program. The upstream native probes require hxcpp; the ordinary regression does not.

The runtime stores valid UTF-8 and translates substring bounds to UTF-16 units.
Foreign malformed bytes must be decoded at their input boundary. This test does
not claim coverage for those separate input codecs or for other String methods.
