# Morley: Developer tools for the Michelson Language

Morley is a library to make writing smart contracts in Michelson pleasant and
effective.

## I: A reimplementation of the Michelson Language in Haskell

- `Michelson.Untyped`: Simple data types representing Michelson smart
  contracts and expresions. We use word `Untyped` to reflect that
  Michelson type of corresponding Haskel values is not statically known
  (e. g. there is a `Value` type which is basically dynamically typed).
- `Michelson.Typed`: These modules contain more advanced types comparing to
  `Michelson.Untyped` with similar semantics. These types use `GADTs` GHC
  extension and in this representation Michelson type of each value and
  instruction is statically known. There are also some utilities to use this
  advanced machinery.
- `Michelson.TypeCheck`: A typechecker that validates ADT's that conform to
  Michelson's typing rules.
- `Michelson.Intepreter`: An intepreter for Michelson contracts which doesn't
  perform any side effects.
- `Morley.Types`: Types for macros, syntactic sugar, and interpreter directives.
- `Morley.Parser` A parser to turn a `.tz` file into an ADT.
- `Morley.Runtime`: An interpreter that executes a well-typed Morley smart
  contract in a sandbox.

## II: Testing tools (TBD)

- `Morley.REPL`: An interactive REPL with stack visualization.
- `Morley.QuickCheck`: QuickCheck generators for arbitary Michelson `Value`s,
  `LAMBDA`s and `Contract`s.
- `Morley.Sandbox`: Simulating a more realistic network environment, multiple
   smart contracts in the same sandbox.

## Issue Tracker

We use [YouTrack](https://issues.serokell.io/issues/TM) as our issue
tracker. You can login using your GitHub account to leave a comment or
create a new issue.

## For Contributors

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for more information.
