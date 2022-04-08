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
            owned_keys: MapSet.new(),
            attempt_to_own_keys: MapSet.new(),
            cleanup_on_process_exit?: true

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map

  def build(tenant, pid, keys, global_id, state) do
    local_owner =
      get_in(
        state,
        [
          Access.key(:owners, %{}),
          Access.key(pid, %{}),
          Access.key(tenant, nil)
        ]
      )

    case local_owner do
      nil ->
        build_default(tenant, pid, keys, global_id)

      local_owner ->
        update_local_owner(local_owner, keys, global_id)
    end
  end

  def successfully_locked(owner) do
    owned_keys =
      owner.attempt_to_own_keys
      |> Enum.reduce(owner.owned_keys, fn key, acc ->
        MapSet.put(acc, key)
      end)

    struct(owner, %{owned_keys: owned_keys})
  end

  defp build_default(tenant, pid, attempt_keys, nil = _global_id) do
    should_cleanup_on_process_exit = true
    global_id = Util.uuid()

    do_build_default(
      global_id,
      pid,
      tenant,
      attempt_keys,
      should_cleanup_on_process_exit
    )
  end

  defp do_build_default(
         global_id,
         pid,
         tenant,
         attempt_keys,
         should_cleanup_on_process_exit
       ) do
    %LocalOwner{
      global_id: global_id,
      pid: pid,
      tenant: tenant,
      attempt_to_own_keys: attempt_keys,
      cleanup_on_process_exit?: should_cleanup_on_process_exit
    }
  end

  defp update_local_owner(owner, keys, global_id) do
    cleanup_on_exit = global_id == nil

    struct(
      owner,
      %{attempt_to_own_keys: keys, cleanup_on_process_exit?: cleanup_on_exit}
    )
  end
end
