defmodule Test.PrismEx.UnitTest do
  use ExUnit.Case, async: false

  alias PrismEx.Util
  alias PrismEx.Option

  setup_all do
    testing_opts = [
      testing: [
        lock_return: {:ok, :mocked_lock_return},
        unlock_return: {:ok, :mocked_unlock_return}
      ]
    ]

    opts =
      Application.get_all_env(:prism_ex)
      |> Keyword.merge(testing_opts)
      |> Option.validate!()

    [opts: opts]
  end

  describe "local cache" do
    test "should clear when <ttl> time passes for pid locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, ttl: 100)

      {:ok, :mocked_lock_return} = PrismEx.lock(tenant, keys, nil, opts)

      {:ok, :cache} = PrismEx.lock(tenant, keys, nil, opts)

      Task.async(fn ->
        {:error, {:cache, :lock_taken}} = PrismEx.lock(tenant, keys, nil, opts)
      end)

      Process.sleep(100)

      {:ok, :mocked_lock_return} = PrismEx.lock(tenant, keys, nil, opts)
      {:ok, :mocked_unlock_return} = PrismEx.unlock(tenant, keys, nil, opts)
    end

    test "should clear when <ttl> time passes for global_id locks", %{opts: opts} do
      tenant = "test_tenant"
      keys = [1]
      opts = Keyword.merge(opts, ttl: 100)
      global_id = Util.uuid()

      {:ok, :mocked_lock_return} = PrismEx.lock(tenant, keys, global_id, opts)

      Process.sleep(100)

      {:ok, :mocked_lock_return} = PrismEx.lock(tenant, keys, global_id, opts)
      {:ok, :mocked_unlock_return} = PrismEx.unlock(tenant, keys, global_id, opts)
    end
  end
end
