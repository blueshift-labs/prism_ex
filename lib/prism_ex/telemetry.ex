defmodule PrismEx.Telemetry do
  def count(namespace, count \\ 1, metadata \\ %{}) do
    :telemetry.execute(namespace, %{count: count}, metadata)
  end

  def measure(namespace, words \\ 1, metadata \\ %{}) do
    bytes = words * 8
    :telemetry.execute(namespace, %{total: bytes}, metadata)
  end

  def span(namespace, func, metadata) do
    start = System.monotonic_time()

    try do
      return = func.()

      case return do
        :ok ->
          success(start, namespace, metadata)

        {:ok, _} ->
          success(start, namespace, metadata)

        :error ->
          failure(start, namespace, metadata)

        {:error, _} ->
          failure(start, namespace, metadata)
      end

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

  defp success(start, namespace, metadata) do
    :telemetry.execute(
      namespace ++ [:success],
      %{count: 1, duration: System.monotonic_time() - start},
      metadata
    )
  end

  defp failure(start, namespace, metadata) do
    :telemetry.execute(
      namespace ++ [:failure],
      %{count: 1, duration: System.monotonic_time() - start},
      metadata
    )
  end
end
