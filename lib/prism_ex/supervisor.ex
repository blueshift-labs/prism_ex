defmodule PrismEx.Supervisor do
  @moduledoc false

  use Supervisor

  alias PrismEx.Option

  def start_link(opts) do
    opts = Option.validate!(opts)
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Keyword.get(opts, :testing, false)
    |> if do
      :persistent_term.put(:prism_ex_default_opts, opts[:lock_defaults] ++ [testing: true])
    else
      :persistent_term.put(:prism_ex_default_opts, opts[:lock_defaults])
    end

    opts
    |> children()
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp children(opts) do
    Keyword.get(opts, :testing, false)
    |> if do
      :cache_only
    else 
      :with_network
    end
    |> children_for_env(opts)
  end

  defp children_for_env(:cache_only, _opts) do
    children = [
      PrismEx.Cache.Supervisor
    ]
  end

  defp children_for_env(_, opts) do
    {pool_size, opts} = pop_in(opts, [:connection, :pool_size])

    children = [
      PrismEx.Cache.Supervisor,
      :poolboy.child_spec(:redix_pool, pool_config(pool_size), opts[:connection])
    ]
  end

  defp pool_config(size) do
    [
      name: {:local, :redix_pool},
      worker_module: Redix,
      size: size,
      max_overflow: 0
    ]
  end
end
