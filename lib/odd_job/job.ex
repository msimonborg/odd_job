defmodule OddJob.Job do
  defstruct [:ref, :worker, :owner, :function, :results]

  @type t :: %__MODULE__{
          ref: reference,
          worker: pid,
          owner: pid,
          function: function,
          results: term
        }
end
