defmodule OddJob.Job do
  defstruct [:owner, :function, :results, async: false]

  @type t :: %__MODULE__{
          async: boolean,
          owner: pid,
          function: function,
          results: term
        }
end
