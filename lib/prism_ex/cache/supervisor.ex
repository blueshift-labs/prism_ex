defmodule PrismEx.Cache.Supervisor do
  @moduledoc false
  @registry PrismEx.Cache.Registry

  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      PrismEx.Cache.DynamicSupervisor,
      {Registry, [keys: :unique, name: @registry]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
