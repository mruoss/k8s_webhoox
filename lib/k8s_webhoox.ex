defmodule K8sWebhoox do
  @moduledoc ~S"""
  Kubernetes webhook endpoints need to be TLS terminated. This
  module and the only exported functions `ensure_certificates/5`,
  `update_admission_webhook_configs/3` and `update_crd_conversion_configs/3`
  help initializing TLS termination for your webhook endpoint.

  ## How it works

  The function `ensure_certificates/5` generates a CA and a SSL certificate and
  stores them in a secret, together with their private keys. If the secret
  already exists, it reads the certificates from that secret and doesn't
  generate them again.

  `update_admission_webhook_configs/3` searches the cluster for resources of
  type `admissionregistration.k8s.io/v1/ValidatingWebhookConfiguration` and
  `admissionregistration.k8s.io/v1/MutatingWebhookConfiguration` and updates
  them in place, setting the `caBundle` entry to the value of the generated CA
  certificate.

  `update_crd_conversion_configs/3` searches the cluster for resources of
  type `apiextensions.k8s.io/v1/CustomResourceDefinition` and updates
  them in place, setting the `caBundle` entry to the value of the generated CA
  certificate.

  ## Usage

  ### RBAC

  I assume you already have a Kubernetes deployment running your applicaiton
  bundled with this library. Make sure the service account used by the pods can
  read and patch secrets and webhook configurations. You can create and assign
  it the following RBAC role:

  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: your-operator
    namespace: default
  rules:
    - apiGroups:
        - admissionregistration.k8s.io
      resources:
        - validatingwebhookconfigurations
        - mutatingwebhookconfigurations
      verbs: ["*"]
    - apiGroups: [""]
      resources: ["secrets", "customresourcedefinitions"]
      verbs: ["*"]
  ```

  ### Mounting the certificates

  In the main container of your deployment, mount a secret as volume. In the
  example below, the secret is called `admission-webhook-cert` and is mounted to
  `/mnt/cert`. The path should correlate to where you load the certificate from
  in your HTTP Server configuration (see `K8sWebhoox.Plug`).

  The secret does not exist at this moment which is why we set `optional: true`:

  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  ...
  spec:
    template:
      spec:
        containers:
          - name: your-operator
            ...
            volumeMounts:
              - name: cert
                mountPath: "/mnt/cert"
                readOnly: true
        volumes:
          - name: cert
            secret:
              secretName: admission-webhook-cert
              optional: true
  ```

  ### Use Init Container to Create Certificates

  In your code base, implement a function that calls the functions of this
  module in order to initialize the TLS configuration:

  ```
  defmodule MyOperator.K8sWebhooxTLS do
    def bootstrap_tls() do
      # Initialize connection to Kubernetes
      conn = ...

      # Create certificates if necessary
      {:ok, ca_bundle_base_64} =
        K8sWebhoox.ensure_certificates(
          conn,
          "default",
          "my-operator",
          "default",
          "webhook-tls-certificate"
        )

      # Patch admission webhook configurations
      :ok = K8sWebhoox.update_admission_webhook_configs(conn, "my-operator", ca_bundle_base_64)

      # Patch conversion webhook configurations in CRDs
      :ok = K8sWebhoox.update_crd_conversion_configs(conn, "myoperator.com", ca_bundle_base_64)
    end
  end
  ```

  In your deployment, add an init container with the same `image` as the main
  container and call your TLS bootstrap function using `eval`:

  ```yaml
        ...
        initContainers:
          - name: bootstrap-tls
            image: SAME_AS_MAIN_CONTAINER
            args: ["eval", "MyOperator.K8sWebhooxTLS.bootstrap_tls()"]
            ...
  ```
  """

  require Logger

  @crd_api_version "apiextensions.k8s.io/v1"
  @admission_webhook_config_api_version "admissionregistration.k8s.io/v1"
  @default_validity_days 365 + 30

  @doc """
  Gets the certificate bundle from the Kubernetes Secret. Creates new
  CA and certificate if necessary. Returns the CA bundle Base64 encoded.
  """
  @spec ensure_certificates(
          conn :: K8s.Conn.t(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary(),
          opts :: keyword()
        ) :: :error | {:ok, binary()}
  def ensure_certificates(
        conn,
        service_namespace,
        service_name,
        secret_namespace,
        secret_name,
        opts \\ []
      ) do
    case get_or_create_cert_bundle(
           conn,
           service_namespace,
           service_name,
           secret_namespace,
           secret_name,
           opts
         ) do
      {:ok, %{"ca.crt" => ca}} ->
        {:ok, Base.encode64(ca)}

      # coveralls-ignore-next-line
      :error ->
        :error
    end
  end

  @doc """
  Searches the cluster for `ValidatingWebhookConfiguration` and
  `MutatingWebhookConfiguration` resources with the given
  `admission_config_name` and sets the `.webhooks[*].clientConfig.caBundle`
  fields to `ca_bundle_base_64`
  """
  @spec update_admission_webhook_configs(
          conn :: K8s.Conn.t(),
          admission_config_name :: binary(),
          ca_bundle_base_64 :: binary()
        ) :: :ok | :error
  def update_admission_webhook_configs(conn, admission_config_name, ca_bundle_base_64) do
    case get_admission_config(conn, admission_config_name) do
      [_ | _] = admission_configurations ->
        admission_configurations
        |> Enum.reject(fn config ->
          Enum.all?(
            List.wrap(config["webhooks"]),
            &(&1["clientConfig"]["caBundle"] == ca_bundle_base_64)
          )
        end)
        |> Enum.map(fn config ->
          put_in(
            config,
            ["webhooks", Access.all(), "clientConfig", "caBundle"],
            ca_bundle_base_64
          )
        end)
        |> Enum.each(&apply_resource(conn, &1))

      [] ->
        # coveralls-ignore-next-line
        Logger.error("No admission configuration was found on the cluster.")
        :error
    end
  end

  @doc """
  Searches the cluster for `CustomResourceDefinition` resources for the given
  `group` and sets the `.spec.conversion.webhook.clientConfig.caBundle` fields
  to `ca_bundle_base_64`.
  """
  @spec update_crd_conversion_configs(
          conn :: K8s.Conn.t(),
          group :: binary(),
          ca_bundle_base_64 :: binary()
        ) :: :ok | :error
  def update_crd_conversion_configs(conn, group, ca_bundle_base_64) do
    with {:ok, crd_stream} <-
           K8s.Client.list(@crd_api_version, "CustomResourceDefinition")
           |> K8s.Client.put_conn(conn)
           |> K8s.Client.stream() do
      crd_stream
      |> Stream.filter(fn crd ->
        # coveralls-ignore-next-line - not sure why...
        crd["spec"]["group"] == group and
          crd["spec"]["conversion"]["strategy"] == "Webhook" and
          crd["spec"]["conversion"]["webhook"]["clientConfig"]["caBundle"] != ca_bundle_base_64
      end)
      |> Stream.map(fn crd ->
        crd
        |> put_in(
          ~w(spec conversion webhook clientConfig caBundle),
          ca_bundle_base_64
        )
        |> Map.put("apiVersion", @crd_api_version)
        |> Map.put("kind", "CustomResourceDefinition")
        |> Map.update!("metadata", &Map.delete(&1, "managedFields"))
      end)
      |> Stream.each(&apply_resource(conn, &1))
      |> Stream.run()
    end
  end

  @spec get_or_create_cert_bundle(
          conn :: K8s.Conn.t(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | :error
  defp get_or_create_cert_bundle(
         conn,
         service_namespace,
         service_name,
         secret_namespace,
         secret_name,
         opts
       ) do
    with {:secret, {:ok, secret}} <-
           {:secret, get_secret(conn, secret_namespace, secret_name)},
         {:cert_bundle,
          %{"tls.key" => _key, "tls.crt" => _cert, "ca.key" => _ca_key, "ca.crt" => _ca} =
            cert_bundle} <-
           {:cert_bundle, decode_secret(secret)},
         {:cert_too_old, _, _, false} <-
           {:cert_too_old, secret, cert_bundle, cert_too_old?(cert_bundle["tls.crt"])} do
      {:ok, cert_bundle}
    else
      {:secret, {:error, %K8s.Client.APIError{reason: "NotFound"}}} ->
        Logger.info("Secret with certificate bundle was not found. Attempting to create it.")

        # coveralls-ignore-next-line
        create_cert_bundle_and_secret(
          conn,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name,
          Keyword.get(opts, :validity, @default_validity_days)
        )

      {:cert_too_old, cert_secret, cert_bundle, true} ->
        Logger.info("Certificate is too old. Renewing it")

        renewed_cert_bundle =
          renew_cert_bundle(
            cert_bundle,
            Keyword.get(opts, :validity, @default_validity_days)
          )

        cert_secret
        |> Map.delete("data")
        |> Map.put("stringData", renewed_cert_bundle)
        |> then(&apply_resource(conn, &1))

        {:ok, renewed_cert_bundle}

      {:secret, {:error, exception}}
      when is_exception(exception) ->
        # coveralls-ignore-next-line
        Logger.error("Can't get secret with certificate bundle: #{Exception.message(exception)}")
        :error

      {:secret, {:error, _}} ->
        # coveralls-ignore-next-line
        Logger.error("Can't get secret with certificate bundle.")
        :error

      {:cert_bundle, _} ->
        # coveralls-ignore-next-line
        Logger.warning("Certificate secret exists but has the wrong shape.")
        :error
    end
  end

  @spec get_secret(conn :: K8s.Conn.t(), namespace :: binary(), name :: binary()) ::
          {:ok, map()} | {:error, any}
  defp get_secret(conn, namespace, name) do
    K8s.Client.get("v1", "secret", name: name, namespace: namespace)
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  @spec cert_too_old?(pem :: binary()) :: boolean()
  defp cert_too_old?(pem) do
    {:Validity, _from, {:utcTime, to}} =
      pem
      |> X509.Certificate.from_pem!()
      |> X509.Certificate.validity()

    reference =
      DateTime.utc_now()
      |> DateTime.add(30, :day)
      |> Calendar.strftime("%y%m%d%H%M%SZ")
      |> String.to_charlist()

    to < reference
  end

  @spec decode_secret(secret :: map()) :: map()
  defp decode_secret(secret) do
    Map.new(secret["data"], fn {key, value} -> {key, Base.decode64!(value)} end)
  end

  @spec create_cert_bundle_and_secret(
          conn :: K8s.Conn.t(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary(),
          validity :: integer()
        ) :: {:ok, map()}
  defp create_cert_bundle_and_secret(
         conn,
         service_namespace,
         service_name,
         secret_namespace,
         secret_name,
         validity
       ) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)

    ca =
      X509.Certificate.self_signed(
        ca_key,
        "/C=CH/ST=ZH/L=Zurich/O=Operator/CN=Operator Root CA",
        template: :root_ca
      )

    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=CH/ST=ZH/L=Zurich/O=Operator/CN=Operator Admission Control Cert",
        ca,
        ca_key,
        extensions: [
          subject_alt_name:
            X509.Certificate.Extension.subject_alt_name([
              service_name,
              "#{service_name}.#{service_namespace}",
              "#{service_name}.#{service_namespace}.svc"
            ])
        ],
        validity: validity
      )

    cert_bundle = %{
      "tls.key" => X509.PrivateKey.to_pem(key),
      "tls.crt" => X509.Certificate.to_pem(cert),
      "ca.key" => X509.PrivateKey.to_pem(ca_key),
      "ca.crt" => X509.Certificate.to_pem(ca)
    }

    case create_secret(conn, secret_namespace, secret_name, cert_bundle) do
      {:ok, _} ->
        {:ok, cert_bundle}

      {:error, %K8s.Client.APIError{reason: "AlreadyExists"}} ->
        # Looks like another pod was faster. Let's just start over:

        # coveralls-ignore-next-line
        get_or_create_cert_bundle(
          conn,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name,
          validity: validity
        )

      {:error, exception} when is_exception(exception) ->
        # coveralls-ignore-next-line
        raise "Secret creation failed: #{Exception.message(exception)}"

      {:error, _} ->
        # coveralls-ignore-next-line
        raise "Secret creation failed."
    end
  end

  @spec renew_cert_bundle(cert_bundle :: map(), validity :: integer()) :: map()
  defp renew_cert_bundle(cert_bundle, validity) do
    %{"ca.crt" => ca_pem, "ca.key" => ca_key_pem, "tls.crt" => cert_pem} = cert_bundle
    ca = X509.Certificate.from_pem!(ca_pem)
    ca_key = X509.PrivateKey.from_pem!(ca_key_pem)
    old_cert = X509.Certificate.from_pem!(cert_pem)
    public_key = X509.Certificate.public_key(old_cert)
    subject_rdn = X509.Certificate.subject(old_cert)
    subject_alt_name = X509.Certificate.extension(old_cert, :subject_alt_name)

    new_cert =
      X509.Certificate.new(public_key, subject_rdn, ca, ca_key,
        extension: [subject_alt_name: subject_alt_name],
        validity: validity
      )

    Map.put(cert_bundle, "tls.crt", X509.Certificate.to_pem(new_cert))
  end

  @spec create_secret(
          conn :: K8s.Conn.t(),
          namespace :: binary(),
          name :: binary(),
          data :: map()
        ) :: {:ok, any} | {:error, any}
  defp create_secret(conn, namespace, name, data) do
    %{
      "apiVersion" => "v1",
      "kind" => "Secret",
      "metadata" => %{
        "name" => name,
        "namespace" => namespace
      }
    }
    |> Map.put("stringData", data)
    |> K8s.Client.create()
    |> K8s.Client.put_conn(conn)
    |> K8s.Client.run()
  end

  @spec get_admission_config(conn :: K8s.Conn.t(), admission_config_name :: binary()) :: [map()]
  defp get_admission_config(conn, admission_config_name) do
    validating_webhook_config =
      K8s.Client.get(@admission_webhook_config_api_version, "ValidatingWebhookConfiguration",
        name: "#{admission_config_name}"
      )
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    mutating_webhook_config =
      K8s.Client.get(@admission_webhook_config_api_version, "MutatingWebhookConfiguration",
        name: "#{admission_config_name}"
      )
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    [validating_webhook_config, mutating_webhook_config]
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  @spec apply_resource(conn :: K8s.Conn.t(), resource :: map()) :: :ok
  defp apply_resource(conn, resource) do
    result =
      resource
      |> Map.update!("metadata", &Map.delete(&1, "managedFields"))
      |> K8s.Client.apply()
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    case result do
      {:ok, _} ->
        :ok

      {:error, error} ->
        # coveralls-ignore-next-line
        raise "Could not patch Kubernetes resource resource. " <> Exception.message(error)
    end
  end
end
