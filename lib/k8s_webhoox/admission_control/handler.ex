defmodule K8sWebhoox.AdmissionControl.Handler do
  @moduledoc """
  A Helper module for handling admission review requests.

  When `use`d, it turns the using module into a
  [`Pluggable`](https://hex.pm/packages/pluggable) step which can be used with
  `K8sWebhoox.AdmissionControl.Plug`. The `:webhook_type` option has to be set
  to either `:validating` or `:mutating` when initializing the `Pluggable`:

  ```
  post "/admission-review/validating",
    to: K8sWebhoox.AdmissionControl.Plug,
    init_opts: [
      webhook_handler: {MyOperator.AdmissionControlHandler, webhook_type: :validating}
    ]
  ```
  """

  defmacro __using__(_) do
    quote do
      use Pluggable.StepBuilder, copy_opts_to_assign: :admission_control_handler

      import K8sWebhoox.AdmissionControl.Handler,
        only: [mutate: 3, mutate: 4, validate: 3, validate: 4, build_pattern: 3]

      step :handle
    end
  end

  @spec generate_handler(
          Macro.input(),
          Macro.input(),
          Macro.input(),
          Macro.input(),
          keyword(Macro.input())
        ) ::
          Macro.output()
  defp generate_handler(webhook_type, resource, kind, var_name, do: expression) do
    quote bind_quoted: [
            expression: Macro.escape(expression),
            kind: kind,
            resource: resource,
            var_name: Macro.escape(var_name),
            webhook_type: webhook_type
          ] do
      quoted_pattern = build_pattern(webhook_type, resource, kind) |> Macro.escape()

      @spec handle(K8sWebhoox.Conn.t(), any()) ::
              K8sWebhoox.Conn.t()
      def handle(unquote(quoted_pattern) = conn, _) do
        var!(unquote(var_name)) = conn
        unquote(expression)
      end
    end
  end

  @spec mutate(Macro.input(), Macro.input(), Macro.input(), keyword(Macro.input())) ::
          Macro.output()
  defmacro mutate(resource, kind \\ nil, var_name, do: expression) do
    quote do: unquote(generate_handler(:mutating, resource, kind, var_name, do: expression))
  end

  @spec validate(Macro.input(), Macro.input(), Macro.input(), keyword(Macro.input())) ::
          Macro.output()
  defmacro validate(resource, kind \\ nil, var_name, do: expression) do
    quote do: unquote(generate_handler(:validating, resource, kind, var_name, do: expression))
  end

  @spec build_pattern(binary(), binary(), binary() | nil) :: map()
  def build_pattern(webhook_type, resource, nil) do
    conn = %{assigns: %{admission_control_handler: [webhook_type: webhook_type]}, request: %{}}

    {group, version, resource} =
      case parse_resource_or_kind(resource) do
        {:ok, gvk} ->
          gvk

        :error ->
          raise(
            ~s(resource has to be given in the form group/version/plural, e.g. example.com/v1/someresources or v1/pods)
          )
      end

    put_in(conn.request["resource"], %{
      "group" => group,
      "version" => version,
      "resource" => resource
    })
  end

  def build_pattern(webhook_type, resource, kind) do
    conn = build_pattern(webhook_type, resource, nil)

    {group, version, kind} =
      case parse_resource_or_kind(kind) do
        {:ok, gvk} ->
          gvk

        :error ->
          raise(
            ~s(kind has to be given in the form group/version/kind, e.g. example.com/v1/SomeResource or v1/Pod)
          )
      end

    put_in(conn.request["kind"], %{
      "group" => group,
      "version" => version,
      "kind" => kind
    })
  end

  @spec parse_resource_or_kind(resource_or_kind :: binary()) ::
          {:ok, {group :: binary(), verison :: binary(), resource_or_kind :: binary()}} | :error
  defp parse_resource_or_kind(resource_or_kind) do
    case String.split(resource_or_kind, "/") do
      [group, version, resource_or_kind] ->
        {:ok, {group, version, resource_or_kind}}

      [version, resource_or_kind] ->
        {:ok, {"", version, resource_or_kind}}

      _ ->
        :error
    end
  end
end
