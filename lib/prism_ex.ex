defmodule PrismEx do
  @moduledoc """
  public api for prism_ex
  should only call functions defined here as a library consumer
  """
  alias PrismEx.Server
  alias PrismEx.Supervisor

  def start_link(opts), do: Supervisor.start_link(opts)
  def child_spec(opts), do: Supervisor.child_spec(opts)

  # spec tenant:string
  # keys:list
  # owner:optional(string)
  # opts:optional(keyword)
  def lock(tenant, keys, global_owner_id \\ nil, opts \\ []) do
    keys = MapSet.new(keys)
    GenServer.call(Server, {:lock, tenant, keys, global_owner_id, opts})
  end

  def unlock(tenant, keys, global_owner_id \\ nil, opts \\ []) do
    GenServer.call(Server, {:unlock, tenant, keys, global_owner_id, opts})
  end

  def lock_command(owner) do
    keys = MapSet.to_list(owner.attempt_to_lock_keys)

    lock =
      ["LOCK", owner.tenant, owner.namespace] ++
        keys ++
        ["OWNER", owner.global_id, "TTL", owner.ttl]

    worker = :poolboy.checkout(:redix_pool)

    reply =
      Redix.command(worker, lock)
      |> case do
        {:ok, [1, _owned_resources]} ->
          {:ok, :locked}

        {:ok, _lock_contention} ->
          {:error, :lock_taken}
      end

    :poolboy.checkin(:redix_pool, worker)
    reply
  end

  def unlock_command(owner) do
    keys = MapSet.to_list(owner.owned_keys)

    unlock =
      ["UNLOCK", owner.tenant, owner.namespace] ++
        keys ++
        ["OWNER", owner.global_id]

    worker = :poolboy.checkout(:redix_pool)

    reply =
      case Redix.command(worker, unlock) do
        {:ok, 1} -> :ok
        {:ok, -1} -> :error
      end

    :poolboy.checkin(:redix_pool, worker)
    reply
  end
end
