defmodule OddJob.Job do
  @moduledoc """
  The OddJob.Job struct holds all of the useful information about a job.
  """
  defstruct [:ref, :owner, :function, :results, :proxy, async: false]

  @typedoc """
  The `OddJob.Job` struct is the datatype that is passed between processes charged with performing
  the job.

  It holds all of the data that is necessary to link, monitor, perform work, and return results
  to the caller.

  The job struct is only returned to the caller when using the async/await pattern. When the caller receives
  the struct after calling `OddJob.async_perform/2` the `:results` field is always `nil`, even though the
  work could conceivably already be done. This is because the results are not waited on at the time the
  struct is created. The results are only known when passing the job to `OddJob.await/2` or matching on the
  `{ref, results}` message.

    * `:function` is the anonymous function that will be performed by the worker

    * `:results` is the term that is returned by `function`. This is only used internally by the
      processes performing the work.

    * `:async` is an boolean identifying if the job's results can be awaited on

    * `:ref` is the unique monitor reference of the job

    * `:owner` is the pid of the calling process, i.e. `self()`

    * `:proxy` is the `pid` of the proxy server that creates the job and routes the results. The `owner`
      links and monitors the `proxy`, while the `proxy` links and monitors the worker. Exit messages and failures
      cascade up to the `owner`. The worker sends results back to the `proxy`, which then sends them to the
      `owner` before exiting with reason `:normal`.
  """
  @type t :: %__MODULE__{
          async: boolean,
          ref: reference,
          owner: pid,
          proxy: pid,
          function: function,
          results: term
        }
end
