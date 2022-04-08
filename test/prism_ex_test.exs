defmodule Test.PrismEx.IntegrationTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _pid} =
      Application.get_all_env(:prism_ex)
      |> PrismEx.start_link()

    :ok
  end

  describe "prism locking with process exit cleanup" do
    test "it locks on unowned resources" do
      tenant = "test_tenant"
      keys = [1]
      {:ok, _owner_id} = PrismEx.lock(tenant, keys)
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
          assert {:ok, _metadata} = lock_reply
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
      assert {:ok, _owner_id} = PrismEx.lock(tenant, keys)
    end

    test "it unlocks on owned resources" do
      tenant = "test_tenant"
      keys = [1]
      {:ok, _owner_id} = PrismEx.lock(tenant, keys)

      {:error, {:cache, :lock_taken}} =
        fn ->
          PrismEx.lock(tenant, keys)
        end
        |> Task.async()
        |> Task.await()

      PrismEx.unlock(tenant, keys)

      {:ok, _owner_id} =
        fn ->
          PrismEx.lock(tenant, keys)
        end
        |> Task.async()
        |> Task.await()
    end
  end
end
