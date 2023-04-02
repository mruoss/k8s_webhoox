defmodule AdmissionControl do
  @moduledoc ~S"""
  Admission configuration webhook endpoints need to be TLS terminated. This
  module and the only exported function `bootstrap_tls/6` help initializing TLS
  termination for your admission webhook configuration.

  ## How it works

  The function generates a CA and a SSL certificate and stores them in a secret,
  together with their private keys. If the secret already exists, it reads the
  certificates from that secret and doesn't generate them again.

  Next, it searches the cluster for resources of type
  `admissionregistration.k8s.io/v1/ValidatingWebhookConfiguration` and
  `admissionregistration.k8s.io/v1/MutatingWebhookConfiguration` and updates
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
      resources: ["secrets"]
      verbs: ["*"]
  ```

  ### Mounting the certificates

  In the main container of your deployment, mount a secret as volume. In the
  example below, the secret is called `admission-webhook-cert` and is mounted to
  `/mnt/cert`. The path should correlate to where you load the certificate from
  in your HTTP Server configuration (see `AdmissionControl.Plug`).

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

  In your deployment, add an init container and call this function or a function
  in a module in your code base which prepares the arguments and calls this
  function.

  The function expects 6 arguments which you can either pass directly or as
  environment variables:

  - `conn` - A `%K8s.Conn{}` struct. If none is given, the service account is
    used.
  - `admission_config_name` - The name of the
    `admissionregistration.k8s.io/v1/ValidatingWebhookConfiguration` and/or
    `admissionregistration.k8s.io/v1/MutatingWebhookConfiguration` resources.
    (env: `ADMISSION_CONFIG_NAME`)
  - `secret_namespace` - The namespace of the secret used to store the
    certificates. Usually the same as the deployment. (env: `SECRET_NAMESPACE`
  - `secret_name` - The name of the secret used to store the certificates. (env:
    `SECRET_NAME`)
  - `service_namespace` - The namespace of the kubernetes service which is going
    to serve the webhook requests. Usually the same as the deployment. (env:
    `SERVICE_NAMESPACE`
  - `service_name` - The name of the kubernetes service which is going
    to serve the webhook requests.
    (env: `SERVICE_NAME`)

  ```yaml
        ...
        initContainers:
          - name: bootstrap-tls
            image: SAME_AS_CONTAINER
            args: ["eval", "AdmissionControl.bootstrap_tls()"]
            env:
              - name: ADMISSION_CONFIG_NAME
                value: name-of-admission-configuration-resource
              - name: SECRET_NAMESPACE
                value: default
              - name: SECRET_NAME
                value: admission-webhook-cert # same as in volume definition
              - name: SERVICE_NAMESPACE
                value: default # serving the the webhook calls
              - name: SERVICE_NAME
                value: my-operator
            ...
  ```

  Alternatively, you can implement your own module which prepares the arguments:

  ```
  defmodule MyOperator.AdmissionControlTLS do
    def bootstrap() do
      conn = ...
      AdmissionControl.bootstrap_tls(conn, "admission-config", "default", "my-operator", "default", "admission-config")
    end
  end
  ```

  You can then call this function in your init controller:

  ```yaml
        ...
        initContainers:
          - name: bootstrap-tls
            image: SAME_AS_CONTAINER
            args: ["eval", "AdmissionControl.bootstrap_tls()"]
  ```
  """
  require Logger

  @doc """
  Initializes the `%K8s.Conn{}` using the service account and loads the other
  variables from environment.

  See `bootstrap_tls/6`
  """
  @spec bootstrap_tls() :: :error | :ok
  def bootstrap_tls() do
    with {:conn, {:ok, conn}} <- {:conn, K8s.Conn.from_service_account()},
         {:vars,
          {admission_config_name, service_namespace, service_name, secret_namespace, secret_name}} <-
           {:vars, get_vars_from_env()} do
      bootstrap_tls(
        conn,
        admission_config_name,
        service_namespace,
        service_name,
        secret_namespace,
        secret_name
      )
    else
      {:conn, {:error, exception}} when is_exception(exception) ->
        Logger.error(
          "Could not initialize connection to Kubernetes API: #{Exception.message(exception)}"
        )

        :error

      {:conn, _} ->
        Logger.error("Could not initialize connection to Kubernetes API.")
        :error

      {:vars, :error} ->
        :error
    end
  end

  @doc """
  Expects a `%K8s.Conn{}` and loads the other variables from environment.

  See `bootstrap_tls/6`
  """
  @spec bootstrap_tls(conn :: K8s.Conn.t()) :: :error | :ok
  def bootstrap_tls(conn) do
    case get_vars_from_env() do
      {admission_config_name, service_namespace, service_name, secret_namespace, secret_name} ->
        bootstrap_tls(
          conn,
          admission_config_name,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name
        )

      :error ->
        :error
    end
  end

  @doc """
  Initializes the `%K8s.Conn{}` using the service account.

  See `bootstrap_tls/6`
  """
  @spec bootstrap_tls(
          admission_config_name :: binary(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary()
        ) :: :error | :ok
  def bootstrap_tls(
        admission_config_name,
        service_namespace,
        service_name,
        secret_namespace,
        secret_name
      ) do
    case K8s.Conn.from_service_account() do
      {:ok, conn} ->
        bootstrap_tls(
          conn,
          admission_config_name,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name
        )

      {:error, exception} when is_exception(exception) ->
        Logger.error(
          "Could not initialize connection to Kubernetes API: #{Exception.message(exception)}"
        )

      _ ->
        Logger.error("Could not initialize connection to Kubernetes API.")
        :error
    end
  end

  @doc """
  Bootstrap the TLS certificates as described in the module documentation.
  """
  @spec bootstrap_tls(
          conn :: K8s.Conn.t(),
          admission_config_name :: binary(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary()
        ) :: :error | :ok
  def bootstrap_tls(
        conn,
        admission_config_name,
        service_namespace,
        service_name,
        secret_namespace,
        secret_name
      ) do
    with {:admission_config, [_ | _] = admission_configurations} <-
           {:admission_config, get_admission_config(conn, admission_config_name)},
         {:cert_bundle, {:ok, cert_bundle}} <-
           {:cert_bundle,
            get_or_create_cert_bundle(
              conn,
              service_namespace,
              service_name,
              secret_namespace,
              secret_name
            )} do
      encoded_ca = Base.encode64(cert_bundle["ca.pem"])

      admission_configurations
      |> Enum.reject(fn config ->
        Enum.all?(
          List.wrap(config["webhooks"]),
          &(&1["clientConfig"]["caBundle"] == encoded_ca)
        )
      end)
      |> Enum.map(fn config ->
        put_in(
          config,
          ["webhooks", Access.all(), "clientConfig", "caBundle"],
          encoded_ca
        )
      end)
      |> Enum.each(&apply_admission_config(conn, &1))

      :ok
    else
      {:admission_config, []} ->
        Logger.error("No admission configuration was found on the cluster.")
        :error

      {:cert_bundle, :error} ->
        # System.halt(1)
        :error
    end
  end

  @spec get_vars_from_env() :: {binary(), binary(), binary(), binary(), binary()} | :error
  defp get_vars_from_env() do
    with {:admission_config_name, admission_config_name} when is_binary(admission_config_name) <-
           {:admission_config_name, System.get_env("ADMISSION_CONFIG_NAME")},
         {:secret_namespace, secret_namespace} when is_binary(secret_namespace) <-
           {:secret_namespace, System.get_env("SECRET_NAMESPACE")},
         {:secret_name, secret_name} when is_binary(secret_name) <-
           {:secret_name, System.get_env("SECRET_NAME")},
         {:service_namespace, service_namespace} when is_binary(service_namespace) <-
           {:service_namespace, System.get_env("SERVICE_NAMESPACE")},
         {:service_name, service_name} when is_binary(service_name) <-
           {:service_name, System.get_env("SERVICE_NAME")} do
      {admission_config_name, service_namespace, service_name, secret_namespace, secret_name}
    else
      {:admission_config_name, nil} ->
        Logger.error("Env variable ADMISSION_CONFIG_NAME is not defined.")
        :error

      {:secret_namespace, nil} ->
        Logger.error("Env variable SECRET_NAMESPACE is not defined.")
        :error

      {:secret_name, nil} ->
        Logger.error("Env variable SECRET_NAME is not defined.")
        :error

      {:service_namespace, nil} ->
        Logger.error("Env variable SERVICE_NAMESPACE is not defined.")
        :error

      {:service_name, nil} ->
        Logger.error("Env variable SERVICE_NAME is not defined.")
        :error
    end
  end

  @spec get_or_create_cert_bundle(
          conn :: K8s.Conn.t(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary()
        ) :: {:ok, map()} | :error
  defp get_or_create_cert_bundle(
         conn,
         service_namespace,
         service_name,
         secret_namespace,
         secret_name
       ) do
    with {:secret, {:ok, secret}} <-
           {:secret, get_secret(conn, secret_namespace, secret_name)},
         {:cert_bundle,
          %{"key.pem" => _key, "cert.pem" => _cert, "ca_key.pem" => _ca_key, "ca.pem" => _ca} =
            cert_bundle} <-
           {:cert_bundle, decode_secret(secret)} do
      {:ok, cert_bundle}
    else
      {:secret, {:error, %K8s.Client.APIError{reason: "NotFound"}}} ->
        Logger.info("Secret with certificate bundle was not found. Attempting to create it.")

        create_cert_bundle_and_secret(
          conn,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name
        )

      {:secret, {:error, exception}}
      when is_exception(exception) ->
        Logger.error("Can't get secret with certificate bundle: #{Exception.message(exception)}")
        :error

      {:secret, {:error, _}} ->
        Logger.error("Can't get secret with certificate bundle.")
        :error

      {:cert_bundle, _} ->
        Logger.error("Certificate secret exists but has the wrong shape.")
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

  @spec decode_secret(secret :: map()) :: map()
  defp decode_secret(secret) do
    Map.new(secret["data"], fn {key, value} -> {key, Base.decode64!(value)} end)
  end

  @spec create_cert_bundle_and_secret(
          conn :: K8s.Conn.t(),
          service_namespace :: binary(),
          service_name :: binary(),
          secret_namespace :: binary(),
          secret_name :: binary()
        ) :: {:ok, map()}
  defp create_cert_bundle_and_secret(
         conn,
         service_namespace,
         service_name,
         secret_namespace,
         secret_name
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
        ]
      )

    cert_bundle = %{
      "key.pem" => X509.PrivateKey.to_pem(key),
      "cert.pem" => X509.Certificate.to_pem(cert),
      "ca_key.pem" => X509.PrivateKey.to_pem(ca_key),
      "ca.pem" => X509.Certificate.to_pem(ca)
    }

    case create_secret(conn, secret_namespace, secret_name, cert_bundle) do
      {:ok, _} ->
        {:ok, cert_bundle}

      {:error, %K8s.Client.APIError{reason: "AlreadyExists"}} ->
        # Looks like another pod was faster. Let's just start over:
        get_or_create_cert_bundle(
          conn,
          service_namespace,
          service_name,
          secret_namespace,
          secret_name
        )

      {:error, exception} when is_exception(exception) ->
        raise "Secret creation failed: #{Exception.message(exception)}"

      {:error, _} ->
        raise "Secret creation failed."
    end
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
      K8s.Client.get("admissionregistration.k8s.io/v1", "ValidatingWebhookConfiguration",
        name: "#{admission_config_name}"
      )
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    mutating_webhook_config =
      K8s.Client.get("admissionregistration.k8s.io/v1", "MutatingWebhookConfiguration",
        name: "#{admission_config_name}"
      )
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    [validating_webhook_config, mutating_webhook_config]
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  @spec apply_admission_config(conn :: K8s.Conn.t(), admission_config :: map()) :: :ok
  defp apply_admission_config(conn, admission_config) do
    result =
      admission_config
      |> Map.update!("metadata", &Map.delete(&1, "managedFields"))
      |> K8s.Client.apply()
      |> K8s.Client.put_conn(conn)
      |> K8s.Client.run()

    case result do
      {:ok, _} -> :ok
      {:error, _} -> raise "Could not patch admission config"
    end
  end
end
