defmodule K8sWebhoox.Test.ResourceHelper do
  @moduledoc false

  @spec resource(binary(), binary(), keyword) :: map()
  def resource(api_version, kind, opts \\ []) do
    %{
      "apiVersion" => api_version,
      "kind" => kind,
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "foo"),
        "namespace" => Keyword.get(opts, :name, "default"),
        "uid" => "foo-uid",
        "generation" => 1
      },
      "spec" => Keyword.get(opts, :spec, %{"foo" => "lorem ipsum"})
    }
  end
end
