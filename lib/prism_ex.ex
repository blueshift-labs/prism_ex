defmodule PrismEx do
  @moduledoc """
  public api for prism_ex
  should only call functions defined here as a library consumer
  """
  alias PrismEx.Server
  alias PrismEx.Supervisor

  defdelegate child_spec(opts), to: PrismEx.Supervisor

  def start_link(opts) do
    Supervisor.start_link(opts)
  end

  # spec tenant:string
  # keys:list
  # owner:optional(string)
  # opts:optional(keyword)
  def lock(tenant, keys, owner_id \\ nil, opts \\ []) do
    keys = MapSet.new(keys)
    GenServer.call(Server, {:lock, tenant, keys, owner_id, opts})
  end

  def unlock(tenant, keys, owner_id \\ nil, opts \\ []) do
    GenServer.call(Server, {:unlock, tenant, keys, owner_id, opts})
  end

  def lock_command(owner, opts) do
    ttl = Keyword.get(opts, :ttl)
    namespace = Keyword.get(opts, :namespace)
    tenant = owner.tenant
    keys = MapSet.to_list(owner.attempt_to_own_keys)
    owner_id = owner.global_id

    lock = ["LOCK", tenant, namespace] ++ keys ++ ["OWNER", owner_id, "TTL", ttl]

    Redix.command(:prism_conn, lock)
    |> case do
      {:ok, [1, _owned_resources]} ->
        {:ok, :locked}

      {:ok, _lock_contention} ->
        {:error, :lock_taken}
    end
  end

  def unlock_command(owner, opts) do
    namespace = Keyword.get(opts, :namespace)
    tenant = owner.tenant
    keys = MapSet.to_list(owner.owned_keys)
    owner_id = owner.global_id
    unlock = ["UNLOCK", tenant, namespace] ++ keys ++ ["OWNER", owner_id]

    Redix.command(:prism_conn, unlock)
  end
end
