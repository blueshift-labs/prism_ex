defmodule PrismEx.Server do
  @moduledoc """
  for now this is a single process where all lock/unlock requests are serialized.
  Initial design has a single process to simplify implementation for local caching
  before adding complexity for performance
  """
  use GenServer
  alias PrismEx.LocalOwner

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {
      :ok,
      %{
        opts: opts,
        owners: %{},
        owned_resources: MapSet.new()
      }
    }
  end

  @impl true
  def handle_call({:lock, tenant, keys, global_owner_id, opts}, {caller_pid, _ref}, state) do
    opts = Keyword.merge(state.opts, opts)
    owner_struct = LocalOwner.build(tenant, caller_pid, keys, global_owner_id, state)
    lock(owner_struct, opts, state)
  end

  @impl true
  def handle_call({:unlock, tenant, keys, global_owner_id, opts}, {caller_pid, _}, state) do
    opts = Keyword.merge(state.opts, opts)
    fallback_owner = LocalOwner.build(tenant, caller_pid, keys, global_owner_id, state)

    owner_map =
      get_in(
        state,
        [
          :owners,
          Access.key(caller_pid, %{fallback_owner => nil})
        ]
      )

    owner =
      owner_map
      |> Map.keys()
      |> List.first()

    {_popped_owner, new_state} =
      pop_in(
        state,
        [:owners, owner.pid]
      )

    new_state =
      update_in(
        new_state,
        [:owned_resources],
        fn owned_resources ->
          owner.owned_keys
          |> Enum.reduce(owned_resources, fn cleanup, acc ->
            MapSet.delete(acc, cleanup)
          end)
        end
      )

    reply = PrismEx.unlock_command(owner, opts)

    {:reply, reply, new_state}
  end

  @impl true
  def handle_call(:get_state, _caller_pid, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, _type, pid, _reason}, state) do
    owners_linked_to_pid =
      get_in(
        state,
        [
          Access.key(:owners, %{}),
          Access.key(pid, %{})
        ]
      )

    {cleanup_owners, do_not_cleanup} =
      owners_linked_to_pid
      |> Enum.reduce({%{}, %{}}, fn {owner, timestamp}, {cleanup_acc, dont_acc} ->
        if owner.cleanup_on_process_exit? do
          cleanup = Map.merge(cleanup_acc, %{owner => timestamp})
          {cleanup, dont_acc}
        else
          dont = Map.merge(dont_acc, %{owner => timestamp})
          {cleanup_acc, dont}
        end
      end)

    # cleanup(

    cleanup_owned_resources =
      cleanup_owners
      |> Enum.reduce([], fn {owner, _timestamp}, acc ->
        owned_keys = MapSet.to_list(owner.owned_keys)
        acc ++ owned_keys
      end)

    new_state =
      if do_not_cleanup == %{} do
        {_, new_state} = pop_in(state, [Access.key(:owners, %{}), Access.key(pid, %{})])
        new_state
      else
        put_in(state, [Access.key(:owners, %{}), Access.key(pid, %{})], do_not_cleanup)
      end
      |> update_in([:owned_resources], fn owned_resources ->
        cleanup_owned_resources
        |> Enum.reduce(owned_resources, fn key, acc ->
          MapSet.delete(acc, key)
        end)
      end)

    cleanup_owners
    |> Task.async_stream(fn {owner, _timestamp} ->
      PrismEx.unlock_command(owner, state.opts)
    end)
    |> Stream.run()

    {:noreply, new_state}
  end

  defp lock(owner, opts, state) do
    Process.monitor(owner.pid)

    case check_local_lock(owner, opts, state) do
      {:ok, :all_locally_owned} ->
        {:reply, {:ok, {:cache, owner.global_id}}, state}

      {:ok, :not_all_locally_owned} ->
        {reply, new_state} = check_prism_lock(owner, opts, state)
        {:reply, reply, new_state}

      {:error, :resource_locally_owned_by_another} ->
        {:reply, {:error, {:cache, :lock_taken}}, state}
    end
  end

  defp check_local_lock(owner, _opts, state) do
    not_locally_owned = MapSet.difference(owner.attempt_to_own_keys, owner.owned_keys)

    if MapSet.size(not_locally_owned) == 0 do
      {:ok, :all_locally_owned}
    else
      no_one_owns = MapSet.disjoint?(not_locally_owned, state.owned_resources)

      if no_one_owns do
        {:ok, :not_all_locally_owned}
      else
        {:error, :resource_locally_owned_by_another}
      end
    end
  end

  defp check_prism_lock(owner, opts, state) do
    PrismEx.lock_command(owner, opts)
    |> case do
      {:ok, :locked} ->
        new_state = update_state(owner, state)
        reply = {:ok, owner.global_id}
        {reply, new_state}

      {:error, :lock_taken} ->
        reply = {:error, :lock_taken}
        {reply, state}
    end
  end

  defp update_state(owner, old_state) do
    now = DateTime.utc_now()
    pid = owner.pid
    new_owner = LocalOwner.successfully_locked(owner)

    {_old_owner, new_state} =
      pop_in(
        old_state,
        [
          Access.key(:owners, %{}),
          Access.key(owner.pid, %{}),
          Access.key(owner, nil)
        ]
      )

    new_state
    |> put_in(
      [
        Access.key(:owners, %{}),
        Access.key(pid, %{}),
        Access.key(new_owner, nil)
      ],
      now
    )
    |> update_in([:owned_resources], fn owned_resources ->
      owner.attempt_to_own_keys
      |> Enum.reduce(owned_resources, fn key, acc ->
        MapSet.put(acc, key)
      end)
    end)
  end
end
