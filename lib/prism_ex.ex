defmodule PrismEx do
  @moduledoc """
  public api for prism_ex
  should only call functions defined here as a library consumer
  """

  alias PrismEx.Supervisor
  alias PrismEx.Cache.Registry, as: CacheRegistry
  alias PrismEx.Cache.DynamicSupervisor
  alias PrismEx.Telemetry
  alias PrismEx.Util

  def start_link(opts), do: Supervisor.start_link(opts)
  def child_spec(opts), do: Supervisor.child_spec(opts)

  # spec tenant:string
  # keys:list
  # owner:optional(string)
  # opts:optional(keyword)
  def lock(tenant, keys, global_owner_id \\ nil, opts \\ []) do
    opts =
      :persistent_term.get(:prism_ex_default_opts)
      |> Keyword.merge(opts)

    lock_func = fn ->
      keys = MapSet.new(keys)

      {:ok, pid} =
        case Registry.lookup(CacheRegistry, tenant) do
          [] ->
            DynamicSupervisor.start_child(tenant)

          [{pid, _}] ->
            {:ok, pid}
        end

      GenServer.call(pid, {:lock, tenant, keys, global_owner_id, opts})
    end

    wrapped_retry_lock_func = fn ->
      Util.retry(lock_func, opts, [:prism_ex, :lock], %{tenant: tenant})
    end

    Telemetry.span([:prism_ex, :lock], wrapped_retry_lock_func, %{tenant: tenant})
  end

  def unlock(tenant, keys, global_owner_id \\ nil, opts \\ []) do
    unlock_func = fn ->
      {:ok, pid} =
        case Registry.lookup(CacheRegistry, tenant) do
          [] ->
            DynamicSupervisor.start_child(tenant)

          [{pid, _}] ->
            {:ok, pid}
        end

      GenServer.call(pid, {:unlock, tenant, keys, global_owner_id, opts})
    end

    Telemetry.span([:prism_ex, :unlock], unlock_func, %{tenant: tenant})
  end

  def lock_command(owner, opts) do
    keys = MapSet.to_list(owner.attempt_to_lock_keys)

    lock =
      ["LOCK", owner.tenant, owner.namespace] ++
        keys ++
        ["OWNER", owner.global_id, "TTL", owner.ttl]

    case prism_command(:lock, lock, owner.tenant, opts) do
      {:ok, [1  | _owned_resources]} = reply ->
        Telemetry.count([:prism_ex, :lock, :success], 1, %{tenant: owner.tenant})
        reply

      {:ok, _} = reply ->
        Telemetry.count([:prism_ex, :lock, :failure], 1, %{tenant: owner.tenant})
        reply
    end
  end

  def unlock_command(owner, opts) do
    keys = MapSet.to_list(owner.attempt_to_unlock_keys)

    unlock = ["UNLOCK", owner.tenant, owner.namespace] ++ keys ++ ["OWNER", owner.global_id]

    case prism_command(:unlock, unlock, owner.tenant, opts) do
      {:ok, 1} = reply ->
        Telemetry.count([:prism_ex, :unlock, :success], 1, %{tenant: owner.tenant})
        reply

      {:ok, -1} = reply ->
        Telemetry.count([:prism_ex, :unlock, :failure], 1, %{tenant: owner.tenant})
        reply
    end
  end

  defp prism_command(cmd_atom, cmd_list, tenant, opts) do
    is_testing = Keyword.get(opts, :testing, false)

    if is_testing do
      do_prism_command(cmd_atom, cmd_list, tenant, opts, :testing)
    else
      do_prism_command(cmd_atom, cmd_list, tenant, opts, nil)
    end
  end

  defp do_prism_command(:lock, cmd_list, tenant, opts, :testing) do
    {:ok, [1, nil]}
  end

  defp do_prism_command(:unlock, cmd_list, tenant, opts, :testing) do
    {:ok, 1}
  end

  defp do_prism_command(cmd_atom, cmd_list, tenant, opts, _) do
    telemetry = [:prism_ex, :prism_request, cmd_atom]

    attempt_fun = fn ->
      with pid when is_pid(pid) <- :poolboy.checkout(:redix_pool, true, 5_000),
           {:ok, _} = prism_reply <- Redix.command(pid, cmd_list) do
        worker_pid = pid
        {:ok, {prism_reply, worker_pid}}
      else
        :full ->
          Telemetry.count([:prism_ex, :pool_checkout, :full], %{tenant: tenant})
          :error
      end
    end

    {:ok, {prism_reply, worker_pid}} = Util.retry(attempt_fun, opts, telemetry, %{tenant: tenant})
    :poolboy.checkin(:redix_pool, worker_pid)
    prism_reply
  end
end
