defmodule K8sWebhoox.AdmissionControl.HandlerTest do
  alias K8sWebhoox.Conn
  use ExUnit.Case, async: true

  @pod %{"group" => "", "version" => "v1", "resource" => "pods"}
  @pod_ref "v1/pods"
  @resource %{"group" => "example.com", "version" => "v1", "resource" => "someresources"}
  @resource_ref "example.com/v1/someresources"
  @scale_kind_ref "autoscaling/v1/Scale"
  @scale_kind %{"group" => "autoscaling", "version" => "v1", "kind" => "Scale"}

  defmodule TestHandler do
    use K8sWebhoox.AdmissionControl.Handler

    @pod "v1/pods"
    @resource "example.com/v1/someresources"
    @scale_kind "autoscaling/v1/Scale"

    mutate @pod, admission_review do
      struct!(admission_review, assigns: %{mutate: @pod})
    end

    mutate @resource, @scale_kind, admission_review do
      struct!(admission_review,
        assigns: %{mutate: "#{@resource}##{@scale_kind}"}
      )
    end

    mutate @resource, admission_review do
      struct!(admission_review, assigns: %{mutate: @resource})
    end

    validate @resource, @scale_kind, admission_review do
      struct!(admission_review,
        assigns: %{validate: "#{@resource}##{@scale_kind}"}
      )
    end

    validate @resource, admission_review do
      struct!(admission_review, assigns: %{validate: @resource})
    end

    validate @pod, admission_review do
      struct!(admission_review, assigns: %{validate: @pod})
    end
  end

  test "handles mutating webhooks" do
    opts = TestHandler.init(webhook_type: :mutating)
    request1 = AdmissionControlHelper.webhook_request(@pod)
    review1 = Conn.new(request1)
    result = TestHandler.call(review1, opts)
    assert %{mutate: @pod_ref} == result.assigns

    request2 = AdmissionControlHelper.webhook_request(@resource, @scale_kind)
    review2 = Conn.new(request2)
    result = TestHandler.call(review2, opts)
    assert %{mutate: "#{@resource_ref}##{@scale_kind_ref}"} == result.assigns

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

    request2 = AdmissionControlHelper.webhook_request(@resource, @scale_kind)
    review2 = Conn.new(request2)
    result = TestHandler.call(review2, opts)
    assert %{validate: "#{@resource_ref}##{@scale_kind_ref}"} == result.assigns

    request3 = AdmissionControlHelper.webhook_request(@resource)
    review3 = Conn.new(request3)
    result = TestHandler.call(review3, opts)
    assert %{validate: @resource_ref} == result.assigns
  end
end
