# K8sWebhoox - Kubernetes Webhooks SDK for Elixir

[![Module Version](https://img.shields.io/hexpm/v/k8s_webhoox.svg)](https://hex.pm/packages/k8s_webhoox)
[![Coverage Status](https://coveralls.io/repos/github/mruoss/k8s_webhoox/badge.svg?branch=main)](https://coveralls.io/github/mruoss/k8s_webhoox?branch=main)
[![Last Updated](https://img.shields.io/github/last-commit/mruoss/k8s_webhoox.svg)](https://github.com/mruoss/k8s_webhoox/commits/main)

[![Build Status Code Qualits](https://github.com/mruoss/k8s_webhoox/actions/workflows/code_quality.yaml/badge.svg)](https://github.com/mruoss/k8s_webhoox/actions/workflows/code_quality.yaml)
[![Build Status Elixir](https://github.com/mruoss/k8s_webhoox/actions/workflows/elixir_matrix.yaml/badge.svg)](https://github.com/mruoss/k8s_webhoox/actions/workflows/elixir_matrix.yaml)

[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/k8s_webhoox/)
[![Total Download](https://img.shields.io/hexpm/dt/k8s_webhoox.svg)](https://hex.pm/packages/k8s_webhoox)
[![License](https://img.shields.io/hexpm/l/k8s_webhoox.svg)](https://github.com/mruoss/k8s_webhoox/blob/main/LICENSE)

## Installation

```elixir
def deps do
  [
    {:k8s_webhoox, "~> 0.2.0"}
  ]
end
```

## Prerequisites

In order to process Kubernetes webhook requests, your endpoint needs TLS
termination. You can use the `K8sWebhoox` helper module to bootstrap TLS using
an `initContainer`. Once the certificates are generated and mounted (e.g. to
`/mnt/cert/tls.crt` and `/mnt/cert/tls.key`), you can initialize
[`Bandit`](https://github.com/mtrudel/bandit) or
[`Cowboy`](https://github.com/ninenines/cowboy) in your `application.ex` to
serve your webhook requests via HTTPS:

```elixir
defmodule MyOperator.Application do
  def start(_type, env: env) do
    children = [
      {Bandit,
       plug: MyOperator.Router,
       port: 4000,
       certfile: "/mnt/cert/tls.crt",
       keyfile: "/mnt/cert/tls.key",
       scheme: :https}
    ]

    opts = [strategy: :one_for_one, name: MyOperator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Router Implementation

In your router Plug, you can forward webhook requests to `K8sWebhoox.Plug` as
follows:

```elixir
defmodule MyOperator.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  post "/admission-review/mutating",
    to: K8sWebhoox.Plug,
    init_opts: [
      webhook_handler: {MyOperator.K8sWebhoox.AdmissionControlHandler, webhook_type: :mutating}
    ]

  post "/admission-review/validating",
    to: K8sWebhoox.Plug,
    init_opts: [
      webhook_handler: {MyOperator.K8sWebhoox.AdmissionControlHandler, webhook_type: :validating}
    ]

  post "/resource-conversion",
    to: K8sWebhoox.Plug,
    init_opts: [
      webhook_handler: MyOperator.K8sWebhoox.ResourceConversionHandler
    ]
end
```

## Handler Implementation

Webhook request handlers are [`Pluggable`](https://hex.pm/packages/pluggable)
steps with a `%K8sWebhoox.Conn{}` struct passed as token. You can ipmlement
them from scratch or use the helper modules as described below.

### Admission Control Handlers

You may `use K8sWebhoox.AdmissionControl.Handler` in your module to simplify
the implementation of an admission webhook request handler.

```elixir
defmodule MyOperator.AdmissionControlHandler do
  use K8sWebhoox.AdmissionControl.Handler

  alias K8sWebhoox.AdmissionControl.AdmissionReview

  # Mutate someresources resource
  mutate "example.com/v1/someresources", conn do
    AdmissionReview.deny(conn)
  end

  # Validate the sacle subresource of a pod
  validate "v1/pods", "scale", conn do
    # Use the helper functions defined in `K8sWebhoox.AdmissionControl.AdmissionReview`.
    conn
  end
end
```

### Resource Conversion Handlers

You may `use K8sWebhoox.ResourceConversion.Handler` in your module to simplify
the implementation of a resource conversion webhook request handler.

```elixir
defmodule MyOperator.ResourceConversionHandler do
  use K8sWebhoox.AdmissionControl.Handler

  def convert(
          %{"apiVersion" => "example.com/v1beta1", "kind" => "MyResource"} = resource,
          "example.com/v1"
        ) do

    # return {:ok, mutated_resource}
    {:ok, put_in(resource, ~w(metadata labels), %{"foo" => "bar"})}
  end

  def convert(
          %{"apiVersion" => "example.com/v1alpha1", "kind" => "MyResource"} = resource,
          "example.com/v1"
        ) do

    # return {:error, message}
    {:error, "V1Alpha1 cannot be converted to V1."}
  end
end
```
