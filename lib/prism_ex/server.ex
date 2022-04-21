defmodule PrismEx.Server do
  @moduledoc """
  for now this is a single process where all lock/unlock requests are serialized.
  Initial design has a single process to simplify implementation for local caching
  before adding complexity for performance
  """
  @registry PrismEx.Cache.Registry

  use GenServer

  alias PrismEx.LocalOwner
  alias PrismEx.Telemetry

  def start_link(name: tenant, opts: opts) do
    via = {:via, Registry, {@registry, tenant}}
    GenServer.start_link(__MODULE__, [opts, tenant], name: via)
  end

  @impl true
  def init([opts, tenant]) do
    Process.send_after(self(), :metrics, :timer.seconds(1))

    {
      :ok,
      %{
        tenant: tenant,
        opts: opts,
        owners: %{},
        owned_resources: MapSet.new(),
        ttl_timestamps: :gb_trees.empty()
      }
    }
  end

  def handle_info(:metrics, state) do
    [
      {:total_heap_size, t_heap},
      {:heap_size, heap},
      {:stack_size, stack}
    ] =
      self()
      |> Process.info()
      |> Keyword.take([:total_heap_size, :heap_size, :stack_size])

    Telemetry.measure([:prism_ex, :lock_pid, :total_heap_size], t_heap, %{tenant: state.tenant})
    Telemetry.measure([:prism_ex, :lock_pid, :heap_size], heap, %{tenant: state.tenant})
    Telemetry.measure([:prism_ex, :lock_pid, :stack_size], stack, %{tenant: state.tenant})

    Process.send_after(self(), :metrics, :timer.seconds(1))
    {:noreply, state}
  end

  # client replies in [
  # {:ok, :cache},
  # {:ok, :no_cache},
  # {:error, {:cache, :lock_taken}}
  # {:error, {:no_cache, :lock_taken}}
  # ]

  @impl true
  def handle_call({:lock, tenant, keys, global_owner_id, opts}, {caller_pid, _ref}, state) do
    timestamp = System.os_time(:microsecond)
    state = cleanup_ttl(timestamp, state)
    opts = Keyword.merge(state.opts, opts)
    caching_toggle = Keyword.get(opts, :caching, :on)
    owner = LocalOwner.build(:lock, tenant, caller_pid, keys, global_owner_id, opts, state)

    client_reply =
      do_lock(caching_toggle, owner, opts, state)
      |> case do
        {:ok, :all_locally_owned} ->
          Telemetry.count([:prism_ex, :cache, :success], 1, %{tenant: owner.tenant})
          {:ok, :cache}

        {:error, :resource_locally_owned_by_another} ->
          Telemetry.count([:prism_ex, :cache, :rejected], 1, %{tenant: owner.tenant})
          {:error, {:cache, :lock_taken}}

        {:ok, [1, _]} ->
          {:ok, :no_cache}

        {:ok, [-1, _]} ->
          {:error, {:no_cache, :lock_taken}}
      end

    new_state =
      {caching_toggle, client_reply}
      |> case do
        {:on, {:ok, :no_cache}} ->
          update_state(owner, timestamp, state)

        _rest_dont_update ->
          state
      end

    {:reply, client_reply, new_state}
  end

  @impl true
  def handle_call({:unlock, tenant, keys, global_id, opts}, {caller_pid, _}, state) do
    timestamp = System.os_time(:microsecond)
    state = cleanup_ttl(timestamp, state)
    opts = Keyword.merge(state.opts, opts)
    owner = LocalOwner.build(:unlock, tenant, caller_pid, keys, global_id, opts, state)

    new_state =
      state
      |> cleanup_owned_resources([owner])
      |> cleanup_owners([owner])
      |> cleanup_timestamps([owner])

    client_reply =
      PrismEx.unlock_command(owner, opts)
      |> case do
        {:ok, 1} -> :ok
        {:ok, -1} -> :error
      end

    {:reply, client_reply, new_state}
  end

  defp do_lock(:on, owner, opts, state) do
    Process.monitor(owner.pid)

    check_local_lock(owner, state)
    |> case do
      {:ok, :not_all_locally_owned} ->
        check_prism_lock(owner, opts)

      reply ->
        reply
    end
  end

  defp do_lock(:off, owner, opts, _state) do
    check_prism_lock(owner, opts)
  end

  @impl true
  def handle_info({:DOWN, _ref, _type, pid, _reason}, state) do
    timestamp = System.os_time(:microsecond)
    state = cleanup_ttl(timestamp, state)

    owners_linked_to_pid =
      get_in(
        state,
        [
          Access.key(:owners, %{}),
          Access.key(pid, %{})
        ]
      )
      |> Map.values()
      |> Enum.map(fn owner ->
        struct(owner, %{attempt_to_unlock_keys: owner.owned_keys})
      end)

    new_state =
      state
      |> cleanup_owned_resources(owners_linked_to_pid)
      |> cleanup_owners(owners_linked_to_pid)
      |> cleanup_timestamps(owners_linked_to_pid)

    owners_linked_to_pid
    |> Task.async_stream(fn owner ->
      PrismEx.unlock_command(owner, state.opts)
    end)
    |> Stream.run()

    {:noreply, new_state}
  end

  defp cleanup_ttl(now, state) do
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

  defp check_prism_lock(owner, opts) do
    PrismEx.lock_command(owner, opts)
    # case Keyword.get(opts, :testing, nil) do
    #   mock_opt when is_list(mock_opt) ->
    #     lock_reply = Keyword.get(mock_opt, :lock_return)
    #     do_check_prism_lock({:testing, lock_reply}, owner, opts)
    #
    #   _rest_are_non_test ->
    #     do_check_prism_lock(nil, owner, opts)
    # end
  end

  # defp do_check_prism_lock({:testing, mocked_reply}, _owner, _opts) do
  #   {:ok, mocked_reply}
  # end
  #
  # defp do_check_prism_lock(_testing_flag, owner, opts) do
  #   |> case do
  #     {:ok, :locked} ->
  #       client_reply = {:ok, :no_cache}
  #       {:ok, client_reply}
  #
  #     {:error, :lock_taken} ->
  #       client_reply = {:error, {:no_cache, :lock_taken}}
  #       {:ok, client_reply}
  #   end
  # end

  # defp refresh_ttl_for_owner(old_owner, timestamp, state) do
  #   new_owner = LocalOwner.refresh_ttl(old_owner, timestamp)
  #
  #   state
  #   |> update_owners(old_owner, new_owner)
  #   |> update_ttl_timestamps(old_owner, new_owner)
  # end

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

  defp cleanup_owners(state, []) do
    state
  end

  defp cleanup_owners(state, [%{cache_group: cg} = _owner | _rest] = owners) do
    owners
    |> Enum.reduce(state, fn owner, acc ->
      {_, new_acc} = pop_in(acc, [:owners, owner.cache_group, owner.cache_key])
      new_acc
    end)
    |> maybe_cleanup_empty_cache_group(cg)
  end

  defp maybe_cleanup_empty_cache_group(state, cache_group) do
    get_in(state, [:owners, Access.key(cache_group, %{})])
    |> case do
      map when map_size(map) == 0 ->
        {_popped, new_state} = pop_in(state, [:owners, cache_group])
        new_state

      _rest ->
        state
    end
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
