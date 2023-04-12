defmodule K8sWebhoox.AdmissionControl.Handler do
  @moduledoc """
  A Helper module for admission review request handling.

  When `use`d, it turns the using module into a
  [`Pluggable`](https://hex.pm/packages/pluggable) step which can be used with
  `K8sWebhoox.Plug`. The `:webhook_type` option has to be set
  to either `:validating` or `:mutating` when initializing the `Pluggable`:

  ```
  post "/k8s-webhooks/admission-review/validating",
    to: K8sWebhoox.Plug,
    init_opts: [
      webhook_handler: {MyOperator.AdmissionControlHandler, webhook_type: :validating}
    ]
  ```

  ## Usage

  ```
  defmodule MyOperator.AdmissionControlHandler do
    use K8sWebhoox.AdmissionControl.Handler

    alias K8sWebhoox.AdmissionControl.AdmissionReview

    # Mutate someresources resource
    mutate "example.com/v1/someresources", conn do
      AdmissionReview.deny(conn)
    end

    # Validate the sacle subresource of a pod
    validate "v1/pods", "scale", conn do
      conn
    end
  end
  ```
  """

  defmacro __using__(_) do
    quote do
      use Pluggable.StepBuilder, copy_opts_to_assign: :admission_control_handler

      import K8sWebhoox.AdmissionControl.Handler,
        only: [mutate: 3, mutate: 4, validate: 3, validate: 4, build_pattern: 4]

      step :handle
    end
  end

  @doc false
  @spec generate_handler(
          Macro.input(),
          Macro.input(),
          Macro.input(),
          Macro.input(),
          env :: Macro.Env.t(),
          keyword(Macro.input())
        ) ::
          Macro.output()
  defp generate_handler(webhook_type, resource, subresource, conn_var, env, do: expression) do
    quote bind_quoted: [
            expression: Macro.escape(expression),
            subresource: subresource,
            resource: resource,
            conn_var: Macro.escape(conn_var),
            webhook_type: webhook_type,
            env: Macro.escape(env)
          ] do
      quoted_pattern = build_pattern(webhook_type, resource, subresource, env) |> Macro.escape()

      @spec handle(K8sWebhoox.Conn.t(), any()) ::
              K8sWebhoox.Conn.t()
      def handle(unquote(quoted_pattern) = conn, _) do
        var!(unquote(conn_var)) = conn
        unquote(expression)
      end
    end
  end

  @doc """
  Defines a handler for mutating webhook requests. The `resource` this
  handler mutates is defined in the form "group/version/plural" (plural being
  the plural form of the resource, e.g. "deployments"). The `subresource` is
  optional. If given, the handler is only called for mutation of the given
  `subresource`. The parameter `conn_var` defines the variable name of the
  `%K8sWebhoox.Conn{}` token inside your handler.

  ### Example

  ```
  mutate "example.com/v1/myresources", conn do
    # your mutations
    conn
  end
  ```

  Validating the `scale` subresource:

  ```
  mutate "v1/pod", "scale", conn do
    # your mutations
    conn
  end
  ```
  """
  @spec mutate(Macro.input(), Macro.input(), Macro.input(), keyword(Macro.input())) ::
          Macro.output()
  defmacro mutate(resource, subresource \\ nil, conn_var, do: expression) do
    quote do
      unquote(
        generate_handler(:mutating, resource, subresource, conn_var, __ENV__, do: expression)
      )
    end
  end

  @doc """
  Defines a handler for validating webhook requests. The `resource` this
  handler validates is defined in the form "group/version/plural" (plural being
  the plural form of the resource, e.g. "deployments"). The `subresource` is
  optional. If given, the handler is only called for validation of the given
  `subresource`. The parameter `conn_var` defines the variable name of the
  `%K8sWebhoox.Conn{}` token inside your handler.

  ### Example

  ```
  validate "example.com/v1/myresources", conn do
    # your validations
    conn
  end
  ```

  Validating the "scale" subresource:
  ```
  validate "example.com/v1/myresources", "scale", conn do
    # your validations
    conn
  end
  ```

  You can use the `K8sWebhoox.AdmissionControl.AdmissionReview` helper module to
  validate the request:
  ```
  validate "v1/pod", "scale", conn do
    # the "some_label" is immutable
    K8sWebhoox.AdmissionControl.AdmissionReview.check_immutable(
      conn,
      ["metadata", "labels", "some_lable"]
    )
  end
  ```
  """
  @spec validate(Macro.input(), Macro.input(), Macro.input(), keyword(Macro.input())) ::
          Macro.output()
  defmacro validate(resource, subresource \\ nil, conn_var, do: expression) do
    quote do
      unquote(
        generate_handler(:validating, resource, subresource, conn_var, __ENV__, do: expression)
      )
    end
  end

  @doc false
  @spec build_pattern(binary(), binary(), binary() | nil, Macro.Env.t()) :: map()
  def build_pattern(webhook_type, resource, nil, env) do
    resource =
      case String.split(resource, "/") do
        [group, version, resource] ->
          %{"group" => group, "version" => version, "resource" => String.downcase(resource)}

        [version, resource] ->
          %{"group" => "", "version" => version, "resource" => String.downcase(resource)}

        _ ->
          raise CompileError,
            file: env.file,
            line: env.line,
            description:
              ~s(resource has to be given in the form group/version/plural, e.g. example.com/v1/someresources or v1/pods. You passed "#{resource}")
      end

    %{
      assigns: %{admission_control_handler: [webhook_type: webhook_type]},
      request: %{"resource" => resource}
    }
  end

  def build_pattern(webhook_type, resource, subresource, env) do
    conn = build_pattern(webhook_type, resource, nil, env)
    put_in(conn.request["subResource"], subresource)
  end
end
