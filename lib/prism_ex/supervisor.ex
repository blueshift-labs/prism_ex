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

    children = [
      {Redix, opts[:connection]},
      {Server, opts[:lock_defaults]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
