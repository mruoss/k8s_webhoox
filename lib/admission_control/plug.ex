defmodule AdmissionControl.Plug do
  @moduledoc """
  A Plug used to handle admission webhook requests. The Plug, when called,
  extracts the admission request from `%Plug.Conn{}` and passes a
  `%AdmissionControl.AdmissionReview` to further handlers.

  ## Prerequisites

  In order to process admission webhook requests, your endpoint needs TLS
  termination. You can use the `AdmissionControl` helper module to bootstrap TLS
  using an `initContainer`. Once the certificates are generated and mouned (e.g.
  to `/mnt/cert/cert.pem` and `/mnt/cert/key.pem`), you can initialize
  [`Bandit`](https://github.com/mtrudel/bandit) or
  [`Cowboy`](https://github.com/ninenines/cowboy) in your `application.ex` to
  serve your webhook requests via HTTPS:

  ```
  defmodule MyOperator.Application do
    @admission_control_server_opts [
      port: 4000,
      transport_options: [
        certfile: "/mnt/cert/cert.pem",
        keyfile: "/mnt/cert/key.pem"
      ]
    ]

    def start(_type, env: env) do
      children = [
        {Bandit, plug: MyOperator.Router, scheme: :https, options: @admission_control_server_opts}
      ]

      opts = [strategy: :one_for_one, name: MyOperator.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  ```

  ## Usage

  ### Plug it in

  Once your endpoint serves via HTTPS, you can route admission webhook requests
  to this Plug as follows:

  ```
  defmodule MyOperator.Router do
    use Plug.Router

    plug :match
    plug :dispatch

    post "/admission-review/validating",
      to: Bonny.AdmissionControl.Plug,
      init_opts: [
        webhook_type: :validating,
        webhook_handler: MyOperator.AdmissionControlHandler
      ]
  end
  ```

  ### Implementing the Handler

  The webhook handler (`MyOperator.AdmissionControlHandler` in the example
  above) needs to implement the `Pluggable` behviour. `Pluggable` is very
  simliar to `Plug` but instead of a `%Plug.Conn{}`, you get a
  `%AdmissionControl.AdmissionReview{}` struct passed to `call/2`. Use the
  functions in `AdmissionControl.AdmissionReview` to process the request.

  ```
  defmodule MyOperator.AdmissionControlHandler do
    @behaviour Pluggable

    alias AdmissionControl.AdmissionReview

    def init(_), do: nil

    def call(%{webhook_type: :validation} = admission_review, _) do
      case admission_review.request["resource"] do
        %{"group" => "my-operator.com", "version" => "v1beta1", "resource" => "mycrd"} ->
          AdmissionReview.check_immutable(admission_review, ["spec", "some_immutable_field"])

        _ ->
          admission_review
      end
    end
  ```

  ## Options

  The plug has to be initialized with to mandatory options:

  - `webhook_type` - The type of the webhook. Has to be `:mutating` or
    `:validating`
  - `webhook_handler` - The `Pluggable` handling the admission request. Can be a
    module or a tuple in the form `{Handler.Module, init_opts]}`. The latter
    will pass the `init_opts` to the `init/1` function of the handler:
    ```
    post "/admission-review/validating",
      to: Bonny.AdmissionControl.Plug,
      init_opts: [
        webhook_type: :validating,
        webhook_handler: {MyOperator.AdmissionControlHandler, env: env}
      ]

    ```
  """

  use Plug.Builder

  alias AdmissionControl.AdmissionReview

  require Logger

  @api_version "admission.k8s.io/v1"
  @kind "AdmissionReview"

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason
  )

  @impl true
  def init(opts) do
    if opts[:webhook_type] not in [:mutating, :validating] do
      raise(CompileError,
        file: __ENV__.file,
        line: __ENV__.line,
        description:
          "#{__MODULE__} requires you to define the :webhook_type option as :mutating or :validating when plugged."
      )
    end

    webhook_handler =
      case opts[:webhook_handler] do
        {module, init_opts} ->
          {module, module.init(init_opts)}

        nil ->
          raise(CompileError,
            file: __ENV__.file,
            line: __ENV__.line,
            description: "#{__MODULE__} requires you to set the :webhook_handler option."
          )

        module ->
          {module, []}
      end

    %{
      webhook_type: opts[:webhook_type],
      webhook_handler: webhook_handler
    }
  end

  @doc false
  @impl true
  def call(conn, webhook_config) do
    %{
      webhook_type: webhook_type,
      webhook_handler: {webhook_handler, opts}
    } = webhook_config

    conn = super(conn, [])

    conn.body_params
    |> AdmissionReview.new(webhook_type)
    |> tap(fn review ->
      Logger.debug("Processing Admission Review Request", library: :bonny_plug, review: review)
    end)
    |> AdmissionReview.allow()
    |> webhook_handler.call(opts)
    |> encode_response()
    |> send_response(conn)
  end

  @spec send_response(response_body :: binary(), conn :: Plug.Conn.t()) :: Plug.Conn.t()
  defp send_response(response_body, conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, response_body)
  end

  @spec encode_response(AdmissionReview.t()) :: binary()
  defp encode_response(admission_review) do
    %{"apiVersion" => @api_version, "kind" => @kind}
    |> Map.put("response", admission_review.response)
    |> Jason.encode!()
  end
end
