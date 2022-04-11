defmodule PrismEx.Cache.Supervisor do
  @moduledoc false
  @registry PrismEx.Cache.Registry

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      PrismEx.Cache.DynamicSupervisor,
      {Registry, [keys: :unique, name: @registry]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
