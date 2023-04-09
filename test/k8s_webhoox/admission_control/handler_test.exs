defmodule K8sWebhoox.AdmissionControl.HandlerTest do
  use ExUnit.Case, async: true

  alias K8sWebhoox.Conn
  alias K8sWebhoox.Test.AdmissionControlHelper

  @pod %{"group" => "", "version" => "v1", "resource" => "pods"}
  @pod_ref "v1/pods"
  @resource %{"group" => "example.com", "version" => "v1", "resource" => "someresources"}
  @resource_ref "example.com/v1/someresources"
  @subresource "scale"

  defmodule TestHandler do
    use K8sWebhoox.AdmissionControl.Handler
    @pod_ref "v1/pods"
    @resource_ref "example.com/v1/someresources"
    @subresource "scale"

    mutate @pod_ref, conn do
      struct!(conn, assigns: %{mutate: @pod_ref})
    end

    mutate @resource_ref, @subresource, conn do
      struct!(conn,
        assigns: %{mutate: "#{@resource_ref}##{@subresource}"}
      )
    end

    mutate @resource_ref, conn do
      struct!(conn, assigns: %{mutate: @resource_ref})
    end

    validate @resource_ref, @subresource, conn do
      struct!(conn,
        assigns: %{validate: "#{@resource_ref}##{@subresource}"}
      )
    end

    validate @resource_ref, conn do
      struct!(conn, assigns: %{validate: @resource_ref})
    end

    validate @pod_ref, conn do
      struct!(conn, assigns: %{validate: @pod_ref})
    end
  end

  test "handles mutating webhooks" do
    opts = TestHandler.init(webhook_type: :mutating)
    request1 = AdmissionControlHelper.webhook_request(@pod)
    review1 = Conn.new(request1)
    result = TestHandler.call(review1, opts)
    assert %{mutate: @pod_ref} == result.assigns

    request2 = AdmissionControlHelper.webhook_request(@resource, @subresource)
    review2 = Conn.new(request2)
    result = TestHandler.call(review2, opts)
    assert %{mutate: "#{@resource_ref}##{@subresource}"} == result.assigns

    request3 = AdmissionControlHelper.webhook_request(@resource)
    review3 = Conn.new(request3)
    result = TestHandler.call(review3, opts)
    assert %{mutate: @resource_ref} == result.assigns
  end

  test "handles validating webhooks" do
    opts = TestHandler.init(webhook_type: :validating)
    request1 = AdmissionControlHelper.webhook_request(@pod)
    review1 = Conn.new(request1)
    result = TestHandler.call(review1, opts)
    assert %{validate: @pod_ref} == result.assigns

    request2 = AdmissionControlHelper.webhook_request(@resource, @subresource)
    review2 = Conn.new(request2)
    result = TestHandler.call(review2, opts)
    assert %{validate: "#{@resource_ref}##{@subresource}"} == result.assigns

    request3 = AdmissionControlHelper.webhook_request(@resource)
    review3 = Conn.new(request3)
    result = TestHandler.call(review3, opts)
    assert %{validate: @resource_ref} == result.assigns
  end
end
