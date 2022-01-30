defmodule OddJob.Job do
  defstruct [:ref, :owner, :function, :results, async: false]

  @type t :: %__MODULE__{
          async: boolean,
          ref: reference,
          owner: pid,
          function: function,
          results: term
        }
end
