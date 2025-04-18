defmodule K8sWebhooxTest do
  use ExUnit.Case, async: true

  alias K8sWebhoox, as: MUT

  import ExUnit.CaptureLog
  import YamlElixir.Sigil

  @dummy_cert """
              -----BEGIN CERTIFICATE-----
              MIIBczCCARmgAwIBAgIUWFceRftDPs5uwudLK+oJWuMVzRYwCgYIKoZIzj0EAwIw
              DzENMAsGA1UEAwwETXlDQTAeFw0yNTA0MTgwNzM5MDNaFw0zNTA0MTYwNzM5MDNa
              MA8xDTALBgNVBAMMBE15Q0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQNlMDX
              ZMNZPYzZnPml1qQ6YscmdNNxJGxztEF5GN15EEDtysznZ/mBa9zJ0T2JnF4juhjV
              +YDWU1uIDRi3t3J6o1MwUTAdBgNVHQ4EFgQUkwBownwIX2SAsqD7I+FnhLWI+w8w
              HwYDVR0jBBgwFoAUkwBownwIX2SAsqD7I+FnhLWI+w8wDwYDVR0TAQH/BAUwAwEB
              /zAKBggqhkjOPQQDAgNIADBFAiEAxotf50VpiLnfq2IvNF+T+0ZcUBUUhmWX0OXB
              juYQXJ4CICJv83uuSvBmRbZoqhcch69IIVhGM9lyCE8pp1gxnPKw
              -----END CERTIFICATE-----
              """
              |> Base.encode64()

  setup_all do
    {:ok, conn} =
      "KUBECONFIG"
      |> System.get_env()
      |> K8s.Conn.from_file(insecure_skip_tls_verify: true)

    on_exit(fn ->
      K8s.Client.delete("v1", "Secret", namespace: "default", name: "tls-certificates")
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

      K8s.Client.delete("v1", "Secret", namespace: "default", name: "tls-certificates-validity")
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

      K8s.Client.delete_all("apiextensions.k8s.io/v1", "CustomResourceDefinition")
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

      K8s.Client.delete_all("admissionregistration.k8s.io/v1", "ValidatingWebhookConfiguration")
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

      K8s.Client.delete_all("admissionregistration.k8s.io/v1", "MutatingWebhookConfiguration")
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()
    end)

    [conn: conn]
  end

  describe "ensure_certifiates/5" do
    @tag :integration
    test "generates the cert secret", %{conn: conn} do
      result =
        MUT.ensure_certificates(
          conn,
          "default",
          "k8s-webhoox-test",
          "default",
          "tls-certificates"
        )

      assert {:ok, _} = result

      {:ok, secret} =
        K8s.Client.get("v1", "Secret", namespace: "default", name: "tls-certificates")
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      assert %{
               "data" => %{
                 "ca.crt" => _,
                 "ca.key" => _,
                 "tls.crt" => _,
                 "tls.key" => _
               }
             } = secret
    end

    @tag :integration
    test "returns the ca_bundle from the existing secret", %{conn: conn} do
      {:ok, ca_bundle} =
        MUT.ensure_certificates(
          conn,
          "default",
          "k8s-webhoox-test",
          "default",
          "tls-certificates"
        )

      {:ok, ^ca_bundle} =
        MUT.ensure_certificates(
          conn,
          "default",
          "k8s-webhoox-test",
          "default",
          "tls-certificates"
        )
    end

    @tag :integration
    test "renews the cert if invalid", %{conn: conn} do
      {:ok, _} =
        MUT.ensure_certificates(
          conn,
          "default",
          "k8s-webhoox-test",
          "default",
          "tls-certificates-validity",
          validity: 10
        )

      {:ok, %{"data" => %{"tls.crt" => cert_pem}}} =
        K8s.Client.get("v1", "Secret", namespace: "default", name: "tls-certificates-validity")
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      validity =
        cert_pem
        |> Base.decode64!()
        |> X509.Certificate.from_pem!()
        |> X509.Certificate.validity()

      assert {:Validity, {:utcTime, from}, {:utcTime, to}} = validity

      ts_to_int =
        &(&1
          |> Enum.take(12)
          |> List.to_string()
          |> String.to_integer())

      assert ts_to_int.(to) - ts_to_int.(from) >= 10_000_500

      fun = fn ->
        MUT.ensure_certificates(
          conn,
          "default",
          "k8s-webhoox-test",
          "default",
          "tls-certificates-validity"
        )
      end

      assert(capture_log(fun) =~ "Certificate is too old. Renewing it")

      {:ok, %{"data" => %{"tls.crt" => cert_pem}}} =
        K8s.Client.get("v1", "Secret", namespace: "default", name: "tls-certificates-validity")
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      validity =
        cert_pem
        |> Base.decode64!()
        |> X509.Certificate.from_pem!()
        |> X509.Certificate.validity()

      assert {:Validity, {:utcTime, from}, {:utcTime, to}} = validity

      ts_to_int =
        &(&1
          |> Enum.take(12)
          |> List.to_string()
          |> String.to_integer())

      assert ts_to_int.(to) - ts_to_int.(from) > 10_000_500
    end
  end

  describe "update_crd_conversion_configs/3" do
    @tag :integration
    test "updates CRD conversion configs with caBundle", %{conn: conn} do
      {:ok, crd} =
        K8s.Client.apply(~y"""
          apiVersion: apiextensions.k8s.io/v1
          kind: CustomResourceDefinition
          metadata:
            name: cogs.example.com
          spec:
            group: example.com
            versions:
              - name: v1
                served: true
                storage: true
                schema:
                  openAPIV3Schema:
                    type: object
                    properties:
                      spec:
                        type: object
                        properties:
                          foo:
                            type: string
            conversion:
              strategy: Webhook
              webhook:
                conversionReviewVersions: ["v1","v1beta1"]
                clientConfig:
                  service:
                    namespace: default
                    name: k8s-webhoox-test
                    path: /crdconvert
            scope: Namespaced
            names:
              plural: cogs
              singular: cog
              kind: Cog
              shortNames: []
        """)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      #  wait for k8s to update the CRD
      K8s.Client.get(crd)
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.wait_until(find: ["status"], eval: &(not is_nil(&1)))

      ca_bundle_base_64 = @dummy_cert

      assert :ok ==
               MUT.update_crd_conversion_configs(
                 conn,
                 "example.com",
                 ca_bundle_base_64
               )

      {:ok, crd} =
        K8s.Client.get(crd)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      assert ca_bundle_base_64 == crd["spec"]["conversion"]["webhook"]["clientConfig"]["caBundle"]
    end
  end

  describe "update_admission_webhook_configs/3" do
    @tag :integration
    test "updates admission webhook configs with caBundle", %{conn: conn} do
      {:ok, mutating_webhook_config} =
        K8s.Client.apply(~y"""
        apiVersion: admissionregistration.k8s.io/v1
        kind: MutatingWebhookConfiguration
        metadata:
          name: cog.example.com
        webhooks:
        - name: cog.example.com
          admissionReviewVersions: [v1, v1beta1]
          sideEffects: None
          clientConfig:
            service:
              namespace: default
              name: my-service-name
              path: /my-path
              port: 1234
        """)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      {:ok, validating_webhook_config} =
        K8s.Client.apply(~y"""
        apiVersion: admissionregistration.k8s.io/v1
        kind: ValidatingWebhookConfiguration
        metadata:
          name: cog.example.com
        webhooks:
        - name: cog.example.com
          admissionReviewVersions: [v1, v1beta1]
          sideEffects: None
          clientConfig:
            service:
              namespace: default
              name: my-service-name
              path: /my-path
              port: 1234
        """)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      ca_bundle_base_64 = Base.encode64("some-ca-bundle")

      assert :ok ==
               MUT.update_admission_webhook_configs(
                 conn,
                 "cog.example.com",
                 ca_bundle_base_64
               )

      {:ok, mutating_webhook_config} =
        K8s.Client.get(mutating_webhook_config)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      assert is_list(mutating_webhook_config["webhooks"])

      assert ca_bundle_base_64 ==
               hd(mutating_webhook_config["webhooks"])["clientConfig"]["caBundle"]

      {:ok, validating_webhook_config} =
        K8s.Client.get(validating_webhook_config)
        |> K8s.Client.put_conn(conn)
        |> K8s.Client.run()

      assert is_list(validating_webhook_config["webhooks"])

      assert ca_bundle_base_64 ==
               hd(validating_webhook_config["webhooks"])["clientConfig"]["caBundle"]
    end
  end
end
