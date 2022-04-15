defmodule Test.Support.Reporter do
  def attach do
    attach_default_handler()
  end

  defp attach_default_handler() do
    events = [
      [:prism_ex, :lock, :success],
      [:prism_ex, :lock, :failure]
    ]

    :telemetry.attach_many("prism_ex-default-telemetry-handler", events, &handle_event/4, nil)
  end

  def handle_event([:prism_ex, :lock, event], measurements, metadata, _config) do
    IO.inspect(event, label: "event")
    IO.inspect(measurements, label: "measurements")
    IO.inspect(metadata, label: "metadata")
  end
end
