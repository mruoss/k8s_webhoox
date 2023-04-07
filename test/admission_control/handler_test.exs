defmodule AdmissionControl.HandlerTest do
  alias AdmissionControl.AdmissionReview
  use ExUnit.Case, async: true

  @pod %{"group" => "", "version" => "v1", "resource" => "pods"}
  @pod_ref "v1/pods"
  @resource %{"group" => "example.com", "version" => "v1", "resource" => "someresources"}
  @resource_ref "example.com/v1/someresources"
  @scale_kind_ref "autoscaling/v1/Scale"
  @scale_kind %{"group" => "autoscaling", "version" => "v1", "kind" => "Scale"}

  defmodule TestHander do
    use AdmissionControl.Handler

    alias AdmissionControl.AdmissionReview

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
    request1 = AdmissionControlHelper.webhook_request(@pod)
    review1 = AdmissionReview.new(request1, :mutating)
    result = TestHander.call(review1, [])
    assert %{mutate: @pod_ref} == result.assigns

    request2 = AdmissionControlHelper.webhook_request(@resource, @scale_kind)
    review2 = AdmissionReview.new(request2, :mutating)
    result = TestHander.call(review2, [])
    assert %{mutate: "#{@resource_ref}##{@scale_kind_ref}"} == result.assigns

    request3 = AdmissionControlHelper.webhook_request(@resource)
    review3 = AdmissionReview.new(request3, :mutating)
    result = TestHander.call(review3, [])
    assert %{mutate: @resource_ref} == result.assigns
  end

  test "handles validating webhooks" do
    request1 = AdmissionControlHelper.webhook_request(@pod)
    review1 = AdmissionReview.new(request1, :validating)
    result = TestHander.call(review1, [])
    assert %{validate: @pod_ref} == result.assigns

    request2 = AdmissionControlHelper.webhook_request(@resource, @scale_kind)
    review2 = AdmissionReview.new(request2, :validating)
    result = TestHander.call(review2, [])
    assert %{validate: "#{@resource_ref}##{@scale_kind_ref}"} == result.assigns

    request3 = AdmissionControlHelper.webhook_request(@resource)
    review3 = AdmissionReview.new(request3, :validating)
    result = TestHander.call(review3, [])
    assert %{validate: @resource_ref} == result.assigns
  end
end
