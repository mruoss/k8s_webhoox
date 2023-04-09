defmodule K8sWebhoox.Test.PlugHelepr do
  @moduledoc false
  use Plug.Test

  @spec webhook_request_conn(body :: map()) :: Plug.Conn.t()
  def webhook_request_conn(body) do
    conn("POST", "/webhook", Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
  end
end
