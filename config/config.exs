import Config

# Configure jobs to supervise under the OddJob application tree
# Top level config options will apply to all pools as the default
# config unless they are explicitly overridden.

# config :odd_job,
#   # This is the default value
#   default_pool: :job,
#   # :pool_size defaults to 5
#   pool_size: 10,
#   # :max_restarts defaults to the Supervisor default: 3
#   max_restarts: 20,
#   # :max_seconds defaults to the Supervisor default: 5
#   max_seconds: 2,
#   # :extra_pools defaults to an empty list
#   extra_pools: [
#     # An atom will create a pool by that name with the default config
#     :email,
#     # Pass a keyword list to override the default config options for the :work pool
#     work: [
#       pool_size: 5,
#       max_restarts: 2
#     ]
#   ]

if Mix.env() == :test, do: import_config("test.exs")
