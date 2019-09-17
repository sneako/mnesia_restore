defmodule MnesiaRestore do

  def rename_backup(from, to, backup_source, backup_dest) do
    switch = fn
      node when node == from -> to
      node -> node
    end

    convert = fn
      {:schema, :db_nodes, nodes}, acc ->
        {[{:schema, :db_nodes, Enum.map(nodes, switch)}], acc}

      {:schema, :version, version}, acc ->
        {[{:schema, :version, version}], acc}

      {:schema, :cookie, cookie}, acc ->
        {[{:schema, :cookie, cookie}], acc}

      {:schema, table, create_list}, acc ->
        keys = [:ram_copies, :disc_copies, :disc_only_copies]

        opt_switch = fn
          {k, {a, v}} ->
            {k, {a, switch.(v)}}

          {k, v} ->
            case Enum.member?(keys, k) do
              true -> {k, Enum.map(v, switch)}
              false -> {k, v}
            end
        end

        {[{:schema, table, Enum.map(create_list, opt_switch)}], acc}

      other, acc ->
        {[other], acc}
    end

    :mnesia.traverse_backup(backup_source, backup_dest, convert, :switched)
  end

  def restore(path_to_renamed, opts \\ [default_op: :recreate_tables]),
    do: :mnesia.restore(path_to_renamed, opts)
end
