defmodule OddJob.Guards do
  @moduledoc """
  Defines guards for use in function definitions and other guard clauses.
  """

  @doc false
  @doc since: "0.4.0"
  defguard is_enumerable(term) when is_list(term) or is_map(term)

  @doc false
  @doc since: "0.4.0"
  defguard is_timer(timer) when is_integer(timer) and timer >= 0
end
