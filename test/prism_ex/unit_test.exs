defmodule Test.PrismEx.UnitTest do
  use ExUnit.Case, async: false

  alias PrismEx.Util

  setup_all do
    {:ok, _pid} =
      Application.get_all_env(:prism_ex)
      |> PrismEx.start_link()

    :ok
  end

  describe "test local cache" do
    test "cache should clear when <ttl> time passes for pid locks" do
      tenant = "test_tenant"
      keys = [1]
      opts = [ttl: 100]

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, nil, opts)

      Process.sleep(50)

      Task.async(fn ->
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys, nil, opts)
      end)

      Process.sleep(50)

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, nil, opts)
      :ok = PrismEx.unlock(tenant, keys, nil, opts)
    end

    test "cache should clear when <ttl> time passes for global_id locks" do
      tenant = "test_tenant"
      keys = [1]
      opts = [ttl: 100]
      global_id = Util.uuid()

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)

      Process.sleep(100)

      {:ok, :no_cache} = PrismEx.lock(tenant, keys, global_id, opts)
      :ok = PrismEx.unlock(tenant, keys, global_id, opts)
    end
  end
end
