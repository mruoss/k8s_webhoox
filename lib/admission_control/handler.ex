defmodule AdmissionControl.Handler do
  defmacro __using__(_) do
    quote do
      use Pluggable.StepBuilder

      import AdmissionControl.Handler,
        only: [mutate: 3, mutate: 4, validate: 3, validate: 4, build_pattern: 3]

      step :handle
    end
  end

  defp generate_handler(webhook_type, resource, kind, var_name, do: expression) do
    quote bind_quoted: [
            expression: Macro.escape(expression),
            kind: kind,
            resource: resource,
            var_name: Macro.escape(var_name),
            webhook_type: webhook_type
          ] do
      quoted_pattern = build_pattern(webhook_type, resource, kind) |> Macro.escape()

      def handle(unquote(quoted_pattern) = admission_review, _) do
        var!(unquote(var_name)) = admission_review
        unquote(expression)
      end
    end
  end

  defmacro mutate(resource, kind \\ nil, var_name, do: expression) do
    quote do: unquote(generate_handler(:mutating, resource, kind, var_name, do: expression))
  end

  @spec validate(any, any, any, [{:do, any}, ...]) ::
          {:__block__, [], [{:=, [], [...]} | {:__block__, [], [...]}, ...]}
  defmacro validate(resource, kind \\ nil, var_name, do: expression) do
    quote do: unquote(generate_handler(:validating, resource, kind, var_name, do: expression))
  end

  def build_pattern(webhook_type, resource, nil) do
    admission_review = %{webhook_type: webhook_type, request: %{}}

    {group, version, resource} =
      case parse_resource_or_kind(resource) do
        {:ok, gvk} ->
          gvk

        :error ->
          raise(
            ~s(resource has to be given in the form group/version/plural, e.g. example.com/v1/someresources or v1/pods)
          )
      end

    put_in(admission_review.request["resource"], %{
      "group" => group,
      "version" => version,
      "resource" => resource
    })
  end

  def build_pattern(webhook_type, resource, kind) do
    admission_review = build_pattern(webhook_type, resource, nil)

    {group, version, kind} =
      case parse_resource_or_kind(kind) do
        {:ok, gvk} ->
          gvk

        :error ->
          raise(
            ~s(kind has to be given in the form group/version/kind, e.g. example.com/v1/SomeResource or v1/Pod)
          )
      end

    put_in(admission_review.request["kind"], %{
      "group" => group,
      "version" => version,
      "kind" => kind
    })
  end

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

  def maybe_expand({:@, _, _} = resource_or_kind, env),
    do: Macro.expand_once(resource_or_kind, env)

  def maybe_expand(resource_or_kind, _env) when is_binary(resource_or_kind),
    do: resource_or_kind
end
