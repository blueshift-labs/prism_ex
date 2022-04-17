defmodule PrismEx.Option do
  @moduledoc """
  option validations with nimble_options to give library users good error messages when they startup prism_ex
  with bad config values
  """

  def validate!(opts) do
    schema(opts)
    |> NimbleOptions.docs()
    NimbleOptions.validate!(opts, schema(opts))
  end

  def schema(opts) do
    [
      lock_defaults: [
        required: true,
        type: :non_empty_keyword_list,
        keys: [
          retry_config: [
            required: false,
            type: :non_empty_keyword_list,
            default: [
              backoff_growth: 50
            ],
            keys: [
              max_retries: [
                default: 5,
                type: :integer,
                required: false
              ],
              backoff_type: [
                default: :linear,
                type: {:in, [:linear, :exponential]},
                required: false,
                doc: """
                linear: backoff_base + (attempt_int * backoff_growth)
                exponential: backoff_base + (backoff_growth ^ attempt_int)
                """
              ],
              backoff_base: [
                default: 50,
                type: :integer,
                required: false,
                doc: "in milliseconds"
              ],
              backoff_growth: [
                default: 200,
                type: :integer,
                required: false,
                doc: "in milliseconds"
              ]
            ]
          ],
          ttl: [
            type: :integer,
            required: true,
            doc: """
            default ttl will be used to expire locks unless overriden
            ttl is in milliseconds
            """
          ],
          namespace: [
            type: :string,
            required: true,
            doc: """
            namespace should usually give application metadata concerning the caller.
            e.g. "your_app_name:module_name"
            """
          ],
          caching: [
            required: false,
            default: :on,
            type: {:in, [:on, :off]},
            doc: """
            note: only the global_id API supports turning off caching.
            without caching then it's impossible to use the pid API because it requires
            caching state to assocaite a pid to a uuid.

            you can turn caching off entirely so that every call hits prism
            """
          ]
        ]
      ],
      connection: [
        required: true,
        type: :non_empty_keyword_list,
        keys: [
          host: [
            required: true,
            type: :string
          ],
          port: [
            required: true,
            type: :integer
          ],
          pool_size: [
            required: false,
            type: :integer,
            default: 5,
            doc: """
            defines how many connections to open to prism and will distribute requests over
            those connections.
            """
          ]
        ]
      ],
      testing: [
        required: false,
        type: :boolean,
        doc: """
        when testing is true all calls to prism will be successful and no prism service will need to be running
        """
      ]
    ]
  end
end
