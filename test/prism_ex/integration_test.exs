defmodule Test.PrismEx.IntegrationTest do
  use ExUnit.Case, async: false

  alias PrismEx.Util
  alias PrismEx.Option

  setup_all do
    opts =
      Application.get_all_env(:prism_ex)
      |> Option.validate!()

    {:ok, _pid} = PrismEx.start_link(opts)

    :ok
  end

  describe "prism locking with process exit cleanup" do
    test "it locks on unowned resources" do
      tenant = "test_tenant"
      keys = [1]
      {:ok, :no_cache} = PrismEx.lock(tenant, keys)
      :ok = PrismEx.unlock(tenant, keys)
    end

    test "it unlocks owned resources when the lock owner process dies" do
      tenant = "test_tenant"
      keys = [1]
      current_pid = self()

      child_pid =
        spawn_link(fn ->
          child_pid = self()
          send(current_pid, {child_pid, PrismEx.lock(tenant, keys)})

          receive do
            :kill ->
              Process.exit(self(), :normal)
          end
        end)

      receive do
        {^child_pid, lock_reply} ->
          assert {:ok, :no_cache} = lock_reply
      end

      assert {:error, {:cache, :lock_taken}} == PrismEx.lock(tenant, keys)

      Process.flag(:trap_exit, true)
      send(child_pid, :kill)

      receive do
        {:EXIT, from, reason} ->
          assert from == child_pid
          assert reason == :normal
      end

      assert Process.alive?(child_pid) == false
      assert {:ok, :no_cache} = PrismEx.lock(tenant, keys)
      assert :ok = PrismEx.unlock(tenant, keys)
    end

    test "it unlocks on owned resources" do
      tenant = "test_tenant"
      keys = [1]
      {:ok, :no_cache} = PrismEx.lock(tenant, keys)

      {:error, {:cache, :lock_taken}} =
        fn ->
          PrismEx.lock(tenant, keys)
        end
        |> Task.async()
        |> Task.await()

      :ok = PrismEx.unlock(tenant, keys)

      fn ->
        {:ok, :no_cache} = PrismEx.lock(tenant, keys)
        :ok = PrismEx.unlock(tenant, keys)
      end
      |> Task.async()
      |> Task.await()
    end

    test "it adds keys to existing lock" do
      tenant = "test_tenant"
      keys = [1]
      {:ok, :no_cache} = PrismEx.lock(tenant, keys)
      new_keys = [2, 3, 4]
      {:ok, :no_cache} = PrismEx.lock(tenant, new_keys)

      Task.async(fn ->
        conflict_key = [3]
        {:error, _metadata} = PrismEx.lock(tenant, conflict_key)
        conflict_key = [1]
        {:error, _metadata} = PrismEx.lock(tenant, conflict_key)
        conflict_key = [1, 5]
        {:error, _metadata} = PrismEx.lock(tenant, conflict_key)
      end)
      |> Task.await()

      :ok = PrismEx.unlock(tenant, keys ++ new_keys)
    end
  end

  describe "locking with global_id which disables process exit cleanups" do
    test "lock with global_id" do
      tenant = "test_tenant"
      keys = [1, "test"]
      global_id = Util.uuid()
      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id)
      {:ok, :cache} = PrismEx.lock(tenant, keys, global_id)
      new_global_id = Util.uuid()
      {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys, new_global_id)
      :ok = PrismEx.unlock(tenant, keys, global_id)
      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id)
      :ok = PrismEx.unlock(tenant, keys, global_id)
    end

    test "exiting calling process doesn't cleanup locks made with global_id" do
      tenant = "test_tenant"
      keys = [1, "test"]
      global_id = Util.uuid()

      Task.async(fn ->
        {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id)
      end)
      |> Task.await()

      {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys)
      :ok = PrismEx.unlock(tenant, keys, global_id)
    end
  end

  describe "test locking across multiple tenants" do
    test "locking by pid" do
      tenant1 = "test_tenant1"
      tenant2 = "test_tenant2"
      keys = [1, "test"]
      contention_keys1 = [1, 2, 3]
      contention_keys2 = ["test", 2, 3]

      {:ok, :no_cache} = PrismEx.lock(tenant1, keys)
      {:ok, :no_cache} = PrismEx.lock(tenant2, keys)

      Task.async(fn ->
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant1, contention_keys1)
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant2, contention_keys2)
      end)

      :ok = PrismEx.unlock(tenant1, keys)
      :ok = PrismEx.unlock(tenant2, keys)
    end

    test "lock by global_id" do
      tenant1 = "test_tenant1"
      tenant2 = "test_tenant2"
      keys = [1, "test"]
      contention_keys1 = [1, 2, 3]
      contention_keys2 = ["test", 2, 3]
      gid1 = Util.uuid()
      gid2 = Util.uuid()

      {:ok, :no_cache} = PrismEx.lock(tenant1, keys, gid1)
      {:ok, :no_cache} = PrismEx.lock(tenant2, keys, gid1)

      {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant1, contention_keys1, gid2)
      {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant2, contention_keys2, gid2)

      :ok = PrismEx.unlock(tenant1, keys, gid1)
      :ok = PrismEx.unlock(tenant2, keys, gid1)
    end
  end

  describe "test turning off caching" do
    test "turn off caching" do
      tenant = "test_tenant2"
      keys = [1, "test"]
      opts = [caching: :off]
      global_id = Util.uuid()

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)
      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)
      :ok = PrismEx.unlock(tenant, keys, global_id, opts)
    end
  end
end
