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
        owned_resources: MapSet.new(),
        ttl_timestamps: :gb_trees.empty()
      }
    }
  end

  @impl true
  def handle_call({:lock, tenant, keys, global_owner_id, opts}, {caller_pid, _ref}, state) do
    state = cleanup_ttl(state)
    opts = Keyword.merge(state.opts, opts)

    owner = LocalOwner.build(:lock, tenant, caller_pid, keys, global_owner_id, opts, state)

    Process.monitor(owner.pid)

    case check_local_lock(owner, state) do
      {:ok, :all_locally_owned} ->
        {:reply, {:ok, :cache}, state}

      {:ok, :not_all_locally_owned} ->
        {reply, new_state} = check_prism_lock(owner, opts, state)
        {:reply, reply, new_state}

      {:error, :resource_locally_owned_by_another} ->
        {:reply, {:error, {:cache, :lock_taken}}, state}
    end
  end

  @impl true
  def handle_call({:unlock, tenant, keys, global_id, opts}, {caller_pid, _}, state) do
    state = cleanup_ttl(state)
    opts = Keyword.merge(state.opts, opts)

    owner = LocalOwner.build_default(:unlock, tenant, caller_pid, keys, global_id, opts)

    owner =
      get_in(
        state,
        [
          :owners,
          Access.key(owner.cache_group, %{}),
          Access.key(owner.cache_key, %{owner.tenant => owner})
        ]
      )

    new_state =
      state
      |> cleanup_owned_resources([owner])
      |> cleanup_owners([owner])
      |> cleanup_timestamps([owner])

    reply =
      case Keyword.get(opts, :testing, nil) do
        list when is_list(list) ->
          Keyword.get(list, :unlock)
        _ ->
          PrismEx.unlock_command(owner)
      end

    {:reply, reply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, _type, pid, _reason}, state) do
    state = cleanup_ttl(state)

    owners_linked_to_pid =
      get_in(
        state,
        [
          Access.key(:owners, %{}),
          Access.key(pid, %{})
        ]
      )
      |> Map.values()

    new_state =
      state
      |> cleanup_owned_resources(owners_linked_to_pid)
      |> cleanup_owners(owners_linked_to_pid)
      |> cleanup_timestamps(owners_linked_to_pid)

    owners_linked_to_pid
    |> Task.async_stream(fn owner ->
      PrismEx.unlock_command(owner)
    end)
    |> Stream.run()

    {:noreply, new_state}
  end

  defp cleanup_ttl(state) do
    now = System.os_time(:microsecond)
    gb_tree = state.ttl_timestamps

    cleanups =
      gb_tree
      |> :gb_trees.to_list()
      |> Enum.reduce_while([], fn {timestamp, owner}, acc ->
        if timestamp <= now do
          {:cont, [owner | acc]}
        else
          {:halt, acc}
        end
      end)

    state
    |> cleanup_owned_resources(cleanups)
    |> cleanup_owners(cleanups)
    |> cleanup_timestamps(cleanups)
  end

  defp check_local_lock(owner, state) do
    not_locally_owned = MapSet.difference(owner.attempt_to_lock_keys, owner.owned_keys)

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
    ttl_in_microseconds = owner[:ttl] * 1000
    timestamp = System.os_time(:microsecond) + ttl_in_microseconds

    case Keyword.get(opts, :testing, nil) do
      list when is_list(list) ->
        do_check_prism_lock({:testing, list[:lock]}, {owner, timestamp, state})
      _ ->
        do_check_prism_lock(nil, {owner, timestamp, state})
    end
  end

  defp do_check_prism_lock({:testing, mocked_reply}, {owner, timestamp, state}) do
    new_state = update_state(owner, timestamp, state)
    {mocked_reply, new_state}
  end

  defp do_check_prism_lock(_, {owner, timestamp, state}) do
    PrismEx.lock_command(owner)
    |> case do
      {:ok, :locked} ->
        new_state = update_state(owner, timestamp, state)
        {{:ok, :no_cache}, new_state}

      {:error, :lock_taken} ->
        reply = {:error, :lock_taken}
        {reply, state}
    end
  end

  defp update_state(old_owner, timestamp, state) do
    new_owner = LocalOwner.successfully_locked(old_owner, timestamp)

    state
    |> update_owners(old_owner, new_owner)
    |> update_owned_resources(old_owner)
    |> update_ttl_timestamps(old_owner, new_owner)
  end

  defp update_owners(state, old_owner, new_owner) do
    put_in(
      state,
      [
        :owners,
        Access.key(old_owner.cache_group, %{}),
        Access.key(old_owner.cache_key, nil)
      ],
      new_owner
    )
  end

  defp update_owned_resources(state, old_owner) do
    update_in(
      state,
      [:owned_resources],
      fn owned_resources ->
        old_owner.attempt_to_lock_keys
        |> Enum.reduce(owned_resources, fn key, acc ->
          MapSet.put(acc, key)
        end)
      end
    )
  end

  defp update_ttl_timestamps(state, old_owner, new_owner) do
    update_in(
      state,
      [:ttl_timestamps],
      fn gb_tree ->
        if old_owner.cleanup_at == nil do
          :gb_trees.insert(new_owner.cleanup_at, new_owner, gb_tree)
        else
          gb_tree = :gb_trees.delete_any(old_owner.cleanup_at, gb_tree)
          :gb_trees.insert(new_owner.cleanup_at, new_owner, gb_tree)
        end
      end
    )
  end

  defp cleanup_owned_resources(state, owners) do
    old_owned_resources = state.owned_resources

    new_owned_resources =
      owners
      |> Enum.reduce(old_owned_resources, fn owner, state_acc ->
        owner.owned_keys
        |> Enum.reduce(state_acc, fn key, inner_state_acc ->
          MapSet.delete(inner_state_acc, key)
        end)
      end)

    put_in(state, [:owned_resources], new_owned_resources)
  end

  defp cleanup_owners(state, owners) do
    owners
    |> Enum.reduce(state, fn owner, acc ->
      {_, new_acc} = pop_in(acc, [:owners, owner.cache_group, owner.cache_key])
      new_acc
    end)
  end

  defp cleanup_timestamps(state, owners) do
    owners
    |> Enum.reduce(state, fn owner, acc ->
      update_in(acc, [:ttl_timestamps], fn tree ->
        :gb_trees.delete_any(owner.cleanup_at, tree)
      end)
    end)
  end
end
