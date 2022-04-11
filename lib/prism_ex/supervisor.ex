defmodule PrismEx.Supervisor do
  @moduledoc false

  use Supervisor

  alias PrismEx.Server
  alias PrismEx.Option

  def start_link(opts) do
    {:ok, opts} = Option.validate(opts)
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, opts} = Option.validate(opts)
    {pool_size, opts} = pop_in(opts, [:connection, :pool_size])

    children = [
      :poolboy.child_spec(:redix_pool, pool_config(pool_size), opts[:connection]),
      {Server, opts[:lock_defaults]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def pool_config(size) do
    [
      name: {:local, :redix_pool},
      worker_module: Redix,
      size: size,
      max_overflow: 0
    ]
  end
end
