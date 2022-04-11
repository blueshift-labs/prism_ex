defmodule PrismEx.LocalOwner do
  @moduledoc """
  Struct with convenience functions representing a local owner and associated metadata.
  Delegates necessary functions to adhere to Access behaviour.
  """

  alias PrismEx.LocalOwner
  alias PrismEx.Util

  defstruct global_id: nil,
            pid: nil,
            tenant: nil,
            cache_group: nil,
            cache_key: nil,
            owned_keys: MapSet.new(),
            attempt_to_lock_keys: MapSet.new(),
            attempt_to_unlock_keys: MapSet.new(),
            cleanup_on_process_exit?: true,
            cleanup_at: nil,
            ttl: nil,
            namespace: nil

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map

  def build(:lock, tenant, pid, keys, global_id, opts, state) do
    cache_group = if global_id, do: :global, else: pid
    cache_key = if global_id, do: global_id, else: tenant

    local_owner =
      get_in(
        state,
        [
          Access.key(:owners, %{}),
          Access.key(cache_group, %{}),
          Access.key(
            cache_key,
            build_default(:lock, tenant, pid, keys, global_id, opts)
          )
        ]
      )

    struct(local_owner, %{attempt_to_lock_keys: MapSet.new(keys)})
  end

  def build(:unlock, tenant, pid, keys, global_id, opts, state) do
    cache_group = if global_id, do: :global, else: pid
    cache_key = if global_id, do: global_id, else: tenant
    local_owner =
      get_in(
        state,
        [
          :owners,
          Access.key(cache_group, %{}),
          Access.key(
            cache_key, 
            build_default(:unlock, tenant, pid, keys, global_id, opts)
          )
        ]
      )
  end

  def successfully_locked(owner, timestamp) do
    owned_keys =
      owner.attempt_to_lock_keys
      |> Enum.reduce(owner.owned_keys, fn key, acc ->
        MapSet.put(acc, key)
      end)

    struct(owner, %{
      owned_keys: owned_keys,
      attempt_to_lock_keys: MapSet.new(),
      cleanup_at: timestamp
    })
  end

  def build_default(op, tenant, pid, attempt_keys, global_id, opts) do
    cache_group = if global_id, do: :global, else: pid
    cache_key = if global_id, do: global_id, else: tenant
    global_id = if global_id, do: global_id, else: Util.uuid()

    op_specific_keys =
      if op == :lock do
        %{attempt_to_lock_keys: attempt_keys}
      else
        %{attempt_to_unlock_keys: attempt_keys}
      end

    %LocalOwner{
      global_id: global_id,
      pid: pid,
      cache_group: cache_group,
      cache_key: cache_key,
      tenant: tenant,
      cleanup_on_process_exit?: true,
      ttl: opts[:ttl],
      namespace: opts[:namespace]
    }
    |> struct(op_specific_keys)
  end
end
