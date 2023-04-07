# K8sWebhoox - Kubernetes Webhooks SDK for Elixir

[![Build Status](https://travis-ci.org/mruoss/k8s_webhoox.svg?branch=main)](https://travis-ci.org/mruoss/k8s_webhoox)
[![Coverage Status](https://coveralls.io/repos/github/mruoss/k8s_webhoox/badge.svg?branch=main)](https://coveralls.io/github/mruoss/k8s_webhoox?branch=main)
[![Module Version](https://img.shields.io/hexpm/v/k8s_webhoox.svg)](https://hex.pm/packages/k8s_webhoox)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/k8s_webhoox/)
[![Total Download](https://img.shields.io/hexpm/dt/k8s_webhoox.svg)](https://hex.pm/packages/k8s_webhoox)
[![License](https://img.shields.io/hexpm/l/k8s_webhoox.svg)](https://github.com/mruoss/k8s_webhoox/blob/main/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/mruoss/k8s_webhoox.svg)](https://github.com/mruoss/k8s_webhoox/commits/main)

## Installation

```elixir
def deps do
  [
    {:k8s_webhoox, "~> 1.0"}
  ]
end
```

## Prerequisites

In order to process Kubernetes webhook requests, your endpoint needs TLS
termination. You can use the `K8sWebhoox` helper module to bootstrap TLS using
an `initContainer`. Once the certificates are generated and mouned (e.g. to
`/mnt/cert/cert.pem` and `/mnt/cert/key.pem`), you can initialize
[`Bandit`](https://github.com/mtrudel/bandit) or
[`Cowboy`](https://github.com/ninenines/cowboy) in your `application.ex` to
serve your webhook requests via HTTPS:

```
defmodule MyOperator.Application do
  @k8s_webhoox_server_opts [
    port: 4000,
    transport_options: [
      certfile: "/mnt/cert/cert.pem",
      keyfile: "/mnt/cert/key.pem"
    ]
  ]

  def start(_type, env: env) do
    children = [
      {Bandit, plug: MyOperator.Router, scheme: :https, options: @k8s_webhoox_server_opts}
    ]

    opts = [strategy: :one_for_one, name: MyOperator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```
