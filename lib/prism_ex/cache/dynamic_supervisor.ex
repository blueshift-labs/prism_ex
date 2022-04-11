defmodule PrismEx.Cache.DynamicSupervisor do
  use DynamicSupervisor

  alias PrismEx.Server

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(name) do
    opts = :persistent_term.get(:prism_ex_default_opts)
    child = {Server, [name: name, opts: opts]}
    DynamicSupervisor.start_child(__MODULE__, child)
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
