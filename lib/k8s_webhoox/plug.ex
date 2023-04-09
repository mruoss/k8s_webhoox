defmodule K8sWebhoox.Plug do
  @moduledoc """
  A Plug used to handle admission webhook requests. The Plug, when called,
  extracts the admission request from `%Plug.Conn{}` and passes a
  `%K8sWebhoox.Conn{}` to the handlers in the pipeline.

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
      to: K8sWebhoox.Plug,
      init_opts: [
        webhook_handler: {MyOperator.K8sWebhoox.AdmissionControlHandler, webhook_type: :validating}
      ]
  end
  ```

  ### Implementing the Handler

  The webhook handler (`MyOperator.K8sWebhoox.AdmissionControlHandler` in the
  example above) needs to implement the `Pluggable` behviour. `Pluggable` is
  very simliar to `Plug` but instead of a `%Plug.Conn{}`, you get a
  `%K8sWebhoox.Conn{}` struct passed to `call/2`. Use the helper functions in
  `K8sWebhoox.AdmissionControl.AdmissionReview` to process the request.

  ```
  defmodule MyOperator.K8sWebhoox.AdmissionControlHandler do
    @behaviour Pluggable

    alias K8sWebhoox.AdmissionControl.AdmissionReview

    def init(_), do: nil

    def call(%{assigns: %{webhook_type: :validation}} = conn, _) do
      case conn.request["resource"] do
        %{"group" => "my-operator.com", "version" => "v1beta1", "resource" => "mycrd"} ->
          AdmissionReview.check_immutable(conn, ["spec", "some_immutable_field"])

        _ ->
          conn
      end
    end
  ```

  ## Options

  The plug has to be initialized with to mandatory option `webhook_handler`:

  - `webhook_handler` - The `Pluggable` handling the admission request. Can be a
    module or a tuple in the form `{Handler.Module, init_opts}`. The latter
    will pass the `init_opts` to the `init/1` function of the handler:

    ```
    post "/k8s-webhook",
      to: K8sWebhoox.Plug,
      init_opts: [
        webhook_handler: {MyOperator.K8sWebhoox.RequestHandler, env: env}
      ]
    ```
  """

  use Plug.Builder

  alias K8sWebhoox.AdmissionControl.AdmissionReview
  alias K8sWebhoox.Conn

  require Logger

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason
  )

  @impl true
  def init(opts) do
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

    webhook_handler
  end

  @doc false
  @impl true
  def call(conn, {webhook_handler, opts}) do
    conn = super(conn, [])

    conn.body_params
    |> Conn.new()
    |> tap(fn review ->
      Logger.debug("Processing Admission Review Request", library: :k8s_webhoox, review: review)
    end)
    |> AdmissionReview.allow()
    |> webhook_handler.call(opts)
    |> Jason.encode!()
    |> send_response(conn)
  end

  @spec send_response(response_body :: binary(), conn :: Plug.Conn.t()) :: Plug.Conn.t()
  defp send_response(response_body, conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, response_body)
  end
end
