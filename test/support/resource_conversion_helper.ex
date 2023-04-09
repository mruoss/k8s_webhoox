defmodule K8sWebhoox.Test.ResourceConversionHelper do
  @moduledoc false
  use Plug.Test

  @spec webhook_request(api_version :: binary(), objects :: list(map())) :: map()
  def webhook_request(desired_api_version, objects) do
    %{
      "apiVersion" => "apiextensions.k8s.io/v1",
      "kind" => "ConversionReview",
      "request" => %{
        "uid" => "705ab4f5-6393-11e8-b7cc-42010a800002",
        "desiredAPIVersion" => desired_api_version,
        "objects" => objects
      }
    }
  end
end
