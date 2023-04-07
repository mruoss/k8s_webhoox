# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:pluggable],
  locals_without_parens: [mutate: 2, mutate: 3, validate: 2, validate: 3],
  export: [
    locals_without_parens: [mutate: 2, mutate: 3, validate: 2, validate: 3]
  ]
]
