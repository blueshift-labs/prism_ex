defmodule PrismEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :prism_ex,
      version: "0.1.0",
      elixir: "~> 1.10",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:redix, "~> 1.1"},
      {:nimble_options, "~> 0.4.0"},
      {:uuid, "~> 2.0", hex: :uuid_erl}
    ]
  end
end
