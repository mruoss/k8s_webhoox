defmodule K8sWebhoox.ResourceConversion.Handler do
  @moduledoc """
  A Helper module for resource conversion request handling.

  When `use`d, it turns the using module into a
  [`Pluggable`](https://hex.pm/packages/pluggable) step which can be used with
  `K8sWebhoox.Plug`.

  ```
  post "/k8s-webhooks/resource-conversion",
    to: K8sWebhoox.Plug,
    init_opts: [webhook_handler: MyOperator.ResourceConversionHandler]
  ```

  ## Usage

  Declare `convert` to convert a given `resource` to a `desired_api_version`.

  ```
  defmodule MyOperator.ResourceConversionHandler do
    use K8sWebhoox.AdmissionControl.Handler

    def convert(
           %{"apiVersion" => "example.com/v1beta1", "kind" => "MyResource"} = resource,
           "example.com/v1"
         ) do

      # return {:ok, mutated_resource}
      {:ok, put_in(resource, ~w(metadata labels), %{"foo" => "bar"})}
    end

    def convert(
           %{"apiVersion" => "example.com/v1alpha1", "kind" => "MyResource"} = resource,
           "example.com/v1"
         ) do

      # return {:error, message}
      {:error, "V1Alpha1 cannot be converted to V1."}
    end
  end
  ```
  """

  @doc """
  Defines a handler for a converstion request of the given `resource` to the
  given `desired_api_version`. See moduledoc for an example.
  """
  @callback convert(resource :: map(), desired_api_version :: binary()) ::
              {:ok, resource: map()} | {:error, message :: binary()}
  defmacro __using__(_) do
    quote do
      use Pluggable.StepBuilder

      alias K8sWebhoox.ResourceConversion.Handler

      @behaviour Handler

      step :handle

      @spec handle(K8sWebhoox.Conn.t(), any()) :: K8sWebhoox.Conn.t()
      def handle(conn, _), do: Handler.convert(__MODULE__, conn)
    end
  end

  @doc false
  @spec convert(handler :: module(), conn :: K8sWebhoox.Conn.t()) :: K8sWebhoox.Conn.t()
  def convert(handler, conn) do
    {converted_objects, result} =
      Enum.flat_map_reduce(conn.request["objects"], %{"status" => "Success"}, fn
        object, result ->
          case handler.convert(object, conn.request["desiredAPIVersion"]) do
            {:error, message} -> {[], %{"status" => "Failed", "message" => message}}
            {:ok, converted_object} -> {[converted_object], result}
          end
      end)

    struct!(conn,
      response:
        conn.response
        |> Map.put("result", result)
        |> Map.put("convertedObjects", converted_objects)
    )
  end
end
