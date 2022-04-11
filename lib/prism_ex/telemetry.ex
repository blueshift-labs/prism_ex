defmodule PrismEx.Telemetry do
  def span(namespace, func, metadata) do
    start = System.monotonic_time()

    try do
      return = func.()
      :telemetry.execute(
        namespace ++ [:success],
        %{count: 1, duration: System.monotonic_time() - start},
        metadata
      )
      return
    rescue
      exception ->
        :telemetry.execute(
          namespace ++ [:failure],
          %{count: 1, duration: System.monotonic_time() - start},
          metadata
        )
        reraise exception, __STACKTRACE__
    end
  end
end
