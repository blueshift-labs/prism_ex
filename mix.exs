defmodule PrismEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :prism_ex,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib", "vendor/retryable_ex/lib"]

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:redix, "~> 1.1"},
      {:nimble_options, "~> 0.4.0"},
      {:elixir_uuid, "~> 1.6", hex: :uuid_utils},
      {:poolboy, "~> 1.5"},
      {:telemetry, "~> 1.1"},
      {:retryable_ex, git: "https://github.com/blueshift-labs/retryable_ex.git", tag: "0.1.0"}
    ]
  end
end
