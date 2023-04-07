defmodule K8sWebhoox.Conn do
  @moduledoc """
  This module defines a struct which is used as token in the `Pluggable`
  pipeline handling of webhook requests.

  There are several modules defining helpers that operate on these tokens:

  - `K8sWebhoox.AdmissionControl.AdmissionReview` - Helpers when handling
    admission control webhook requests
  """

  @derive Pluggable.Token

  @enforce_keys [:api_version, :kind, :request, :response]
  defstruct [:api_version, :kind, :request, :response, halted: false, assigns: %{}]

  @typedoc """
  The struct used as token in the request handler pipeline.

  ## Fields

  - `api_version` - The API Version of the received resource
  - `kind` - The Kind of the received resource
  - `request` - The body of the HTTPS request representing the admission
    request.
  - `response` - The resposne the request handler pipeline is suposed to define.

  ## Internal Fields

  - `halted` - Whether the pipeline is halted or not. Defaults to `false`.
  - `assigns` - A map used to internally forward data within the pipeline.
    Defaults to `%{}`.
  """
  @type t :: %__MODULE__{
          api_version: binary(),
          kind: binary(),
          request: map(),
          response: map(),
          halted: boolean(),
          assigns: map()
        }

  @spec new(resource :: map(), assigns :: keyword() | map()) :: t()
  def new(request, assigns \\ []) do
    struct!(__MODULE__,
      api_version: request["apiVersion"],
      kind: request["kind"],
      request: request["request"],
      response: %{"uid" => request["request"]["uid"]},
      assigns: Map.new(assigns)
    )
  end
end

defimpl Jason.Encoder, for: K8sWebhoox.Conn do
  @spec encode(K8sWebhoox.Conn.t(), Jason.Encode.opts()) :: binary()
  def encode(conn, opts) do
    conn
    |> Map.take([:kind, :response])
    |> Map.put("apiVersion", conn.api_version)
    |> Jason.Encode.map(opts)
  end
end
