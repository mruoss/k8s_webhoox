defmodule K8sWebhoox.PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias K8sWebhoox.AdmissionControl.AdmissionReview
  alias K8sWebhoox.Plug, as: MUT

  describe "init/1" do
    test "raises if webhook_handler is not declared" do
      assert_raise(CompileError, ~r/requires you to set the :webhook_handler option/, fn ->
        MUT.init([])
      end)
    end

    test "turns webhook_handler into {module, opts} tuple" do
      opts = MUT.init(webhook_handler: SomeModule)
      assert opts == {SomeModule, []}
    end

    defmodule InitTestHandler do
      # credo:disable-for-next-line
      def init(:foo), do: :bar
    end

    test "calls handler's init function if tuple is given" do
      opts = MUT.init(webhook_handler: {InitTestHandler, :foo})
      assert opts == {InitTestHandler, :bar}
    end
  end

  defmodule CallTestHandler do
    # credo:disable-for-next-line
    def call(admission_review, opts) do
      case opts[:result] do
        :deny -> AdmissionReview.deny(admission_review)
        _ -> admission_review
      end
    end
  end

  describe "call/2" do
    test "calls the handler and returns plug" do
      response =
        AdmissionControlHelper.webhook_request_conn()
        |> MUT.call({CallTestHandler, []})
        |> Map.get(:resp_body)
        |> Jason.decode!()

      assert %{
               "apiVersion" => "admission.k8s.io/v1",
               "kind" => "AdmissionReview",
               "response" => %{
                 "allowed" => true
               }
             } = response
    end

    test "calls the handler and returns allowed false" do
      response =
        AdmissionControlHelper.webhook_request_conn()
        |> MUT.call({CallTestHandler, [result: :deny]})
        |> Map.get(:resp_body)
        |> Jason.decode!()

      assert false == response["response"]["allowed"]
    end
  end
end
