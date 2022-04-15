import Config

config :prism_ex,
  connection: [
    host: "localhost",
    port: 8379
  ],
  lock_defaults: [
    ttl: 5_000,
    namespace: "catalogx:products",
    retry_config: [
      max_retries: 0,
      backoff_type: :linear,
      backoff_base: 50,
      backoff_growth: 50
    ]
  ]
