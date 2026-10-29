# Null reference call selection

Passing null to a reference parameter must retain the selected method declaration.
This fixture covers arrays, strings, records, and functions.

Run the upstream behavior check:

```sh
haxe -cp test/fixtures/null_reference_call --run Main
```

It must print `true` four times, followed by `false` for a non-null argument.
The shared selection and native execution checks are:

```sh
npm run test:m14:null-reference-call
```

These checks cover exact declarations, generic inference, nullable and optional
parameters, abstract reference types, overload ambiguity, and invalid arguments.
They compile and run the native OCaml program and compare its complete output.
Bead `haxe_ocaml-nxlzm` owns the repair. Strict null-safety and platform-specific
scalar legality need separate validation; these checks do not prove those contracts.
This is a dedicated compiler regression, not a public buildable example.
