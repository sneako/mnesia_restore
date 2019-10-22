# MnesiaRestore

When you take a backup of your mnesia database using the built in `:mnesia.backup/1` function, you will not be able to load this backup on a different node, unless you first rename the backup.

This library provides some helper functions to help you rename mnesia backups. 

Adapted from the [Mnesia User's Guide](http://erlang.org/documentation/doc-5.8.1/lib/mnesia-4.4.15/doc/html/Mnesia_chap7.html#id74479)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mnesia_restore` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mnesia_restore, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mnesia_restore](https://hexdocs.pm/mnesia_restore).

