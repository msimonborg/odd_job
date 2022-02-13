import Config

config :odd_job,
  extra_pools: [
    :worker_test,
    :macros_test,
    :scheduler_test,
    :async_test,
    odd_job_test: [
      pool_size: 5
    ]
  ]
