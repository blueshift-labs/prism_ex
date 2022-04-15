defmodule PrismEx.Util do
  @moduledoc false
  @retry_on [RuntimeError, :error]

  alias PrismEx.Telemetry

  def uuid do
    :uuid.get_v4()
    |> :uuid.uuid_to_string(:binary_standard)
  end

  def retry(fun, opts, telemetry_namespace \\ [], telemetry_metadata \\ %{}) do
    retry_config = Keyword.get(opts, :retry_config)
    retries = Keyword.get(retry_config, :max_retries)

    if retries > 0 do
      do_retry(fun, opts, telemetry_namespace, telemetry_metadata)
    else
      fun.()
    end
  end

  def do_retry(fun, opts, telemetry_namespace, telemetry_metadata) do
    retry_config = Keyword.get(opts, :retry_config)
    retries = Keyword.get(retry_config, :max_retries)
    backoff_func = backoff_func(retry_config)

    after_func = fn retry_count ->
      if retry_count > 0 do
        Telemetry.count(telemetry_namespace ++ [:retries], retry_count, telemetry_metadata)
      end
    end

    Retryable.retryable(
      [
        on: @retry_on,
        tries: retries,
        sleep: backoff_func,
        after: after_func
      ],
      fn ->
        fun.()
      end
    )
  end

  defp backoff_func(opts) do
    backoff_base = Keyword.get(opts, :backoff_base)
    backoff_growth = Keyword.get(opts, :backoff_growth)

    case Keyword.get(opts, :backoff_type) do
      :linear ->
        fn retry_number -> backoff_base + retry_number * backoff_growth end

      :exponential ->
        fn retry_number -> backoff_base + :math.pow(backoff_growth, retry_number) end
    end
  end
end
