defmodule K8sWebhoox.Test.PlugHelepr do
  @moduledoc false
  import Plug.Test
  import Plug.Conn

  @spec webhook_request_conn(body :: map()) :: Plug.Conn.t()
  def webhook_request_conn(body) do
    conn("POST", "/webhook", Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
  end
end
