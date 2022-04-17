defmodule Test.PrismEx.UnitTest do
  use ExUnit.Case, async: false

  alias PrismEx.Util
  alias PrismEx.Option

  setup_all do
    testing_opts = [
      testing: true
    ]

    opts =
      Application.get_all_env(:prism_ex)
      |> Keyword.merge(testing_opts)
      |> Option.validate!()

    Process.sleep(50)

    {:ok, pid} = PrismEx.start_link(opts)

    cleanup_fun = fn ->
      Process.alive?(pid)
      :ok = Supervisor.stop(pid, :normal)
    end


    [opts: opts, on_exit: cleanup_fun]
  end

  describe "local cache" do
    test "should clear when <ttl> time passes for pid locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, ttl: 100)

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, nil, opts)

      {:ok, :cache} = PrismEx.lock(tenant, keys, nil, opts)

      Task.async(fn ->
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys, nil, opts)
      end)

      Process.sleep(100)

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, nil, opts)
      :ok = PrismEx.unlock(tenant, keys, nil, opts)
    end

    test "should clear when <ttl> time passes for global_id locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, ttl: 100)
      global_id = Util.uuid()

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)

      Process.sleep(100)

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)
      :ok = PrismEx.unlock(tenant, keys, global_id, opts)
    end
  end
end
