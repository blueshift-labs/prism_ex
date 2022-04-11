defmodule Test.PrismEx.UnitTest do
  use ExUnit.Case, async: false

  alias PrismEx.Util

  setup_all do
    testing_opts = [
      testing: [
        lock: {:ok, :mocked_lock_reply},
        unlock: {:ok, :mocked_unlock_reply}
      ]
    ]
    [opts: testing_opts]
  end

  describe "test local cache" do
    test "cache should clear when <ttl> time passes for pid locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, [ttl: 100])

      {:ok, :mocked_lock_reply} = PrismEx.lock(tenant, keys, nil, opts)

      Process.sleep(50)

      Task.async(fn ->
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys, nil, opts)
      end)

      Process.sleep(50)

      {:ok, :mocked_lock_reply} = PrismEx.lock(tenant, keys, nil, opts)
      {:ok ,:mocked_unlock_reply} = PrismEx.unlock(tenant, keys, nil, opts)
    end

    test "cache should clear when <ttl> time passes for global_id locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, [ttl: 100])
      global_id = Util.uuid()

      {:ok, :mocked_lock_reply} = PrismEx.lock(tenant, keys, global_id, opts)

      Process.sleep(100)

      {:ok, :mocked_lock_reply} = PrismEx.lock(tenant, keys, global_id, opts)
      {:ok ,:mocked_unlock_reply} = PrismEx.unlock(tenant, keys, global_id, opts)

      # :persistent_term.get(:prism_ex_default_opts)
      # |> IO.inspect
    end
  end
end
