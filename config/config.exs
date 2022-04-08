import Config

config :prism_ex,
  connection: [
    name: :prism_conn,
    host: "localhost",
    port: 8379
  ],
  lock_defaults: [
    ttl: 5_000,
    namespace: "catalogx:products"
  ]
