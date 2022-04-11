defmodule PrismEx.Util do
  @moduledoc false
  def uuid do
    :uuid.get_v4()
    |> :uuid.uuid_to_string(:binary_standard)
  end
end
