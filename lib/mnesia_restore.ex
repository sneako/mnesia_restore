defmodule MnesiaRestore do
  def create_backup(path \\ "/tmp") do
    path
    |> file_name()
    |> :mnesia.backup()
  end

  def from_backup(from, to, backup_source, backup_dest) do
    switch = fn
      node when node == from -> to
      node when node == to -> throw({:error, :already_exists})
      node -> node
    end

    convert = fn
      {:schema, :db_nodes, nodes}, acc ->
        {[:schema, :db_nodes, Enum.map(nodes, switch)], acc}

      {:schema, :version, version}, acc ->
        {[:schema, :version, version], acc}

      {:schema, :cookie, cookie}, acc ->
        {[:schema, :cookie, cookie], acc}

      {:schema, table, create_list}, acc ->
        keys = [:ram_copies, :disc_copies, :disc_only_copies]

        opt_switch = fn {k, v} ->
          case Enum.member?(keys, k) do
            true -> {k, Enum.map(v, switch)}
            false -> {k, v}
          end
        end

        {[:schema, table, Enum.map(create_list, opt_switch)], acc}

      other, acc ->
        {[other], acc}
    end

    :mnesia.traverse_backup(backup_source, __MODULE__, backup_dest, __MODULE__, convert, :switched)
  end

  defp file_name(path) do
    "#{path}/mnesia-backup-#{System.system_time(:second)}@#{Node.self()}"
  end
end
