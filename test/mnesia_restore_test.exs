defmodule MnesiaRestoreTest do
  use ExUnit.ClusteredCase, async: false
  doctest MnesiaRestore

  scenario "given two nodes", cluster_size: 2 do
    @backup1 "/tmp/mnesia_restore_test_backup1"
    @renamed1 "/tmp/mnesia_restore_test_renamed_backup1"

    @backup2 "/tmp/mnesia_restore_test_backup2"
    @renamed2 "/tmp/mnesia_restore_test_renamed_backup2"

    setup do
      on_exit(fn ->
        [
          @backup1,
          @renamed1,
          @backup2,
          @renamed2
        ]
        |> Enum.each(&File.rm/1)
      end)
    end

    test "create a backup and restore it on a new node with default recreate_tables option", %{
      cluster: cluster
    } do
      [primary, secondary] = Cluster.members(cluster)

      create_schema(primary)
      create_table(:table1, primary)

      # insert some rows on primary node
      for i <- 1..10 do
        write_mfa(:table1, i, i)
      end
      |> run_on(primary)

      # data exists
      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:table1, i]}, [{:table1, i, i}]}
      end
      |> run_and_assert_on(primary)

      # take a backup
      [{:mnesia, :backup, [to_charlist(@backup1)]}]
      |> run_on(primary)

      # rename the backup
      assert {:ok, :switched} =
               MnesiaRestore.rename_backup(
                 [secondary],
                 to_charlist(@backup1),
                 to_charlist(@renamed1)
               )

      # prepare second node,
      create_schema(secondary)

      # restore the renamed backup on the secondary node
      [{{MnesiaRestore, :restore, [to_charlist(@renamed1)]}, {:atomic, [:table1]}}]
      |> run_and_assert_on(secondary)

      # no references to the primary node left
      # refute String.contains?(File.read!(@renamed1), to_string(primary))

      # read the data on the new node
      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:table1, i]}, [{:table1, i, i}]}
      end
      |> run_and_assert_on(secondary)

      cleanup([primary, secondary], :table1)
    end

    test "can merge a backup in to existing data with keep_tables option", %{
      cluster: cluster
    } do
      [primary, secondary] = Cluster.members(cluster)

      # prepare primary node
      create_schema(primary)
      create_table(:table2, primary)

      # prepare second node,
      create_schema(secondary)
      create_table(:table2, secondary)

      # insert some rows on secondary node that should still exist after the restore
      for i <- 10..20 do
        write_mfa(:table2, i, i * 10)
      end
      |> run_on(primary)

      # insert some rows on primary node
      for i <- 1..10 do
        write_mfa(:table2, i, i * 10)
      end
      |> run_on(primary)

      # take a backup
      [{:mnesia, :backup, [to_charlist(@backup2)]}]
      |> run_on(primary)

      # rename the backup
      assert {:ok, :switched} =
               MnesiaRestore.rename_backup(
                 [secondary],
                 to_charlist(@backup2),
                 to_charlist(@renamed2)
               )

      # restore the renamed backup on the secondary node
      [
        {{MnesiaRestore, :restore, [to_charlist(@renamed2), [keep_tables: [:table2]]]},
         {:atomic, [:table2]}}
      ]
      |> run_and_assert_on(secondary)

      # read all of the merged data on the new node
      for i <- 1..20 do
        {{:mnesia, :dirty_read, [:table2, i]}, [{:table2, i, i * 10}]}
      end
      |> run_and_assert_on(secondary)

      cleanup([primary, secondary], :table2)
    end
  end

  scenario "given three nodes", cluster_size: 3 do
    @backup3 "/tmp/mnesia_restore_test_backup3"
    @renamed3 "/tmp/mnesia_restore_test_renamed_backup3"
    setup do
      on_exit(fn ->
        [
          @backup3,
          @renamed3
        ]
        |> Enum.each(&File.rm/1)
      end)
    end

    test "backup cluster to single node", %{cluster: cluster} do
      [primary, secondary, new_node] = Cluster.members(cluster)
      Cluster.partition(cluster, [[primary, secondary], [new_node]])

      setup_mnesia_cluster(primary, [secondary])

      create_table(:table3, primary)
      Cluster.call(secondary, :mnesia, :add_table_copy, [:table3, secondary, :disc_copies])

      # insert some rows on primary node
      for i <- 1..10 do
        write_mfa(:table3, i, i)
      end
      |> run_on(primary)

      # data exists on secondary node
      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:table3, i]}, [{:table3, i, i}]}
      end
      |> run_and_assert_on(secondary)

      # take a backup
      [{:mnesia, :backup, [to_charlist(@backup3)]}]
      |> run_on(primary)

      # rename the backup
      assert {:ok, :switched} =
               MnesiaRestore.rename_backup(
                 [new_node],
                 to_charlist(@backup3),
                 to_charlist(@renamed3)
               )

      create_schema(new_node)

      # restore the renamed backup on the new node
      [{{MnesiaRestore, :restore, [to_charlist(@renamed3)]}, {:atomic, [:table3]}}]
      |> run_and_assert_on(new_node)

      # read the data on the new node
      for i <- 1..10 do
        {{:mnesia, :dirty_read, [:table3, i]}, [{:table3, i, i}]}
      end
      |> run_and_assert_on(new_node)

      cleanup([primary, secondary, new_node], :table3)
    end
  end

  defp setup_mnesia_cluster(primary, nodes) do
    create_schema(primary)

    Enum.each(nodes, fn node ->
      [
        {:mnesia, :stop, []},
        {:mnesia, :delete_schema, [[node]]},
        {:mnesia, :start, []}
      ]
      |> run_on(node)
    end)

    Cluster.call(primary, :mnesia, :change_config, [:extra_db_nodes, nodes])

    Enum.each(nodes, fn node ->
      Cluster.call(node, :mnesia, :change_table_copy_type, [:schema, node, :disc_copies])
    end)
  end

  defp create_schema(node) do
    [
      {:mnesia, :stop, []},
      {:mnesia, :create_schema, [[node]]},
      {:mnesia, :start, []}
    ]
    |> run_on(node)
  end

  defp create_table(name, node) do
    [
      {:mnesia, :create_table, [name, [{:attributes, [:id, :value]}, {:disc_copies, [node]}]]}
    ]
    |> run_on(node)
  end

  defp write_mfa(table, key, value) do
    {MnesiaRestoreTest, :write, [table, key, value]}
  end

  defp run_on(mfas, node) do
    Enum.each(mfas, fn {m, f, a} ->
      Cluster.call(node, m, f, a)
    end)
  end

  defp run_and_assert_on(mfas, node) do
    Enum.each(mfas, fn {{m, f, a}, expected} ->
      assert ^expected = Cluster.call(node, m, f, a)
    end)
  end

  def write(table, k, v) do
    fn ->
      :mnesia.write({table, k, v})
    end
    |> :mnesia.transaction()
  end

  defp cleanup(nodes, table) do
    delete = [{:mnesia, :delete_table, [table]}]
    Enum.each(nodes, &run_on(delete, &1))
  end
end
