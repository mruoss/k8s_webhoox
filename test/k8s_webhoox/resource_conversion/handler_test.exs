# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule K8sWebhoox.ResourceConversion.HandlerTest do
  use ExUnit.Case, async: true

  alias K8sWebhoox.Conn
  alias K8sWebhoox.Test.ResourceConversionHelper
  alias K8sWebhoox.Test.ResourceHelper

  @desired_api_version "example.com/v1beta1"
  @api_version "example.com/v1"
  @first_kind "FirstResource"
  @second_kind "SecondResource"

  defmodule TestHandler do
    use K8sWebhoox.ResourceConversion.Handler

    @desired_api_version "example.com/v1beta1"
    @api_version "example.com/v1"
    @first_kind "FirstResource"
    @second_kind "SecondResource"

    def convert(
          %{"apiVersion" => @api_version, "kind" => @first_kind} = object,
          @desired_api_version
        ) do
      {:ok, put_in(object, ~w(metadata labels), %{"foo" => "first"})}
    end

    def convert(
          %{"apiVersion" => @api_version, "kind" => @second_kind} = object,
          @desired_api_version
        ) do
      {:ok, put_in(object, ~w(metadata labels), %{"foo" => "second"})}
    end
  end

  test "handles conversion review webhook requests" do
    first_resource = ResourceHelper.resource(@api_version, @first_kind)
    second_resource = ResourceHelper.resource(@api_version, @second_kind)

    request =
      ResourceConversionHelper.webhook_request(
        @desired_api_version,
        [first_resource, second_resource]
      )

    result = TestHandler.call(Conn.new(request), [])
    converted_objects = result.response["convertedObjects"]
    assert "Success" == result.response["result"]["status"]
    assert is_list(converted_objects)
    assert %{"foo" => "first"} == Enum.at(converted_objects, 0)["metadata"]["labels"]
    assert %{"foo" => "second"} == Enum.at(converted_objects, 1)["metadata"]["labels"]
  end
end
