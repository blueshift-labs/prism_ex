defmodule PrismEx.Option do
  @moduledoc """
  option validations with nimble_options to give library users good error messages when they startup prism_ex
  with bad config values
  """
  def schema do
    [
      lock_defaults: [
        required: true,
        type: :non_empty_keyword_list,
        keys: [
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
      ]
    ]
  end

  def validate(opts) do
    NimbleOptions.validate(opts, schema())
  end
end
