defmodule K8sWebhoox.Test.AdmissionControlHelper do
  @moduledoc false
  alias K8sWebhoox.Test.PlugHelepr

  @default_resource %{
    "group" => "example.com",
    "version" => "v1alpha1",
    "resource" => "somecrds"
  }

  @spec webhook_request_conn(resource :: map(), subresource :: binary() | nil) :: Plug.Conn.t()
  def webhook_request_conn(resource \\ @default_resource, subresource \\ nil) do
    body = webhook_request(resource, subresource)
    PlugHelepr.webhook_request_conn(body)
  end

  @spec webhook_request(resource :: map(), subresource :: binary() | nil) :: map()
  def webhook_request(resource \\ @default_resource, subresource \\ nil) do
    %{
      "apiVersion" => "admission.k8s.io/v1",
      "kind" => "AdmissionReview",
      "request" => %{
        "uid" => "705ab4f5-6393-11e8-b7cc-42010a800002",
        "kind" => %{},
        "resource" => resource,
        "requestKind" => %{},
        "requestResource" => resource,
        "subResource" => subresource,
        "name" => "my-deployment",
        "namespace" => "my-namespace",
        "operation" => "UPDATE",
        "userInfo" => %{
          "username" => "admin",
          "uid" => "014fbff9a07c",
          "groups" => [
            "system =>authenticated",
            "my-admin-group"
          ],
          "extra" => %{
            "some-key" => [
              "some-value1",
              "some-value2"
            ]
          }
        },
        "object" => %{
          "apiVersion" => "autoscaling/v1",
          "kind" => "Scale"
        },
        "oldObject" => %{
          "apiVersion" => "autoscaling/v1",
          "kind" => "Scale"
        },
        "options" => %{
          "apiVersion" => "meta.k8s.io/v1",
          "kind" => "UpdateOptions"
        },
        "dryRun" => false
      }
    }
  end
end
