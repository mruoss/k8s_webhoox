defmodule AdmissionControlHelper do
  @moduledoc false
  use Plug.Test

  @default_resource %{
    "group" => "example.com",
    "version" => "v1alpha1",
    "resource" => "somecrds"
  }

  @default_kind %{
    "group" => "example.com",
    "version" => "v1alpha1",
    "kind" => "SomeCRD"
  }

  @spec webhook_request_conn(resource :: map(), kind :: map()) :: Plug.Conn.t()
  def webhook_request_conn(resource \\ @default_resource, kind \\ @default_kind) do
    body = webhook_request(resource, kind)

    conn("POST", "/webhook", Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
  end

  @spec webhook_request(resource :: map(), kind :: map()) :: map()
  def webhook_request(resource \\ @default_resource, kind \\ @default_kind) do
    %{
      "apiVersion" => "admission.k8s.io/v1",
      "kind" => "AdmissionReview",
      "request" => %{
        "uid" => "705ab4f5-6393-11e8-b7cc-42010a800002",
        "kind" => kind,
        "resource" => resource,
        "requestKind" => kind,
        "requestResource" => resource,
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
