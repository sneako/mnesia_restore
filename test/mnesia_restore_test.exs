defmodule MnesiaRestoreTest do
  use ExUnit.ClusteredCase
  doctest MnesiaRestore
  alias ExUnit.ClusteredCase.Cluster

  @backup1 "/tmp/mnesia_restore_test_backup1"
  @renamed1 "/tmp/mnesia_restore_test_renamed_backup1"

  setup do
    on_exit(fn ->
      [
        @backup1,
        @renamed1
      ]
      |> Enum.each(&File.rm/1)
    end)
  end

  scenario "given two nodes", cluster_size: 2 do
    test "create a backup and restore it on a new cluster with recreate_tables option", %{
      cluster: cluster
    } do
      [primary, secondary] = Cluster.members(cluster)

      [
        {:mnesia, :stop, []},
        {:mnesia, :create_schema, [[primary]]},
        {:mnesia, :start, []},
        create_table_mfa(:test_table, primary)
      ]
      |> run_on(primary)

      # insert some rows on primary node
      for i <- 1..10 do
        write_mfa(:test_table, i, i)
      end
      |> run_on(primary)

      # data exists
      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:test_table, i]}, [{:test_table, i, i}]}
      end
      |> run_and_assert_on(primary)

      # take a backup
      [
        # {:mnesia, :activate_checkpoint, [[{:name, :checkpoint}, {:max, [:test_table]}]]},
        {:mnesia, :backup, [to_charlist(@backup1)]}
      ]
      |> run_on(primary)

      # ensure the backup is good, restore it on the node it just came from
      [
        {{:mnesia, :start, []}, :ok},
        {{:mnesia, :delete_table, [:test_table]}, {:atomic, :ok}},
        {{MnesiaRestore, :restore, [to_charlist(@backup1)]}, {:atomic, [:test_table]}}
      ]
      |> run_and_assert_on(primary)

      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:test_table, i]}, [{:test_table, i, i}]}
      end
      |> run_and_assert_on(primary)

      # rename the backup
      assert {:ok, :switched} =
               MnesiaRestore.rename_backup(
                 primary,
                 secondary,
                 to_charlist(@backup1),
                 to_charlist(@renamed1)
               )

      [
        {:mnesia, :stop, []},
        {:mnesia, :create_schema, [[secondary]]},
        {:mnesia, :start, []}
      ]
      |> run_on(secondary)

      # restore the renamed backup on the secondary node
      [
        {{MnesiaRestore, :restore, [to_charlist(@renamed1)]}, {:atomic, [:test_table]}}
      ]
      |> run_and_assert_on(secondary)

      # read the data on the new node
      [{:mnesia, :dirty_all_keys, [:test_table]}]
      |> run_on(secondary)

      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:test_table, i]}, [{:test_table, i, i}]}
      end
      |> run_and_assert_on(secondary)
    end
  end

  defp create_table_mfa(name, node) do
    {:mnesia, :create_table, [name, [{:attributes, [:id, :value]}, {:disc_copies, [node]}]]}
  end

  defp write_mfa(table, key, value) do
    {MnesiaRestoreTest, :write, [table, key, value]}
  end

  defp run_on(mfas, node) do
    Enum.each(mfas, fn {m, f, a} ->
      :rpc.call(node, m, f, a)
    end)
  end

  defp run_and_assert_on(mfas, node) do
    Enum.each(mfas, fn {{m, f, a}, expected} ->
      assert ^expected = :rpc.call(node, m, f, a)
    end)
  end

  def write(table, k, v) do
    fn ->
      :mnesia.write({table, k, v})
    end
    |> :mnesia.transaction()
  end
end
