defmodule OddJob.Job do
  defstruct [:ref, :owner, :function, :results, :proxy, async: false]

  @type t :: %__MODULE__{
          async: boolean,
          ref: reference,
          owner: pid,
          proxy: pid,
          function: function,
          results: term
        }
end
