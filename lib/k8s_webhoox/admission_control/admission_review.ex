defmodule K8sWebhoox.AdmissionControl.AdmissionReview do
  @moduledoc """
  This module defines a struct which is used as token in the `Pluggable`
  pipeline handling an admission request. See `K8sWebhoox.AdmissionControl.Plug` for more
  information on how to set up the request handler pipeline.

  This module also defines a set of useful helpers when processing an admission
  request.
  """

  require Logger

  alias K8sWebhoox.Conn

  @doc """
  Responds by allowing the operation

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.allow(admission_review)
      %K8sWebhoox.Conn{request: %{}, response: %{"allowed" => true}, api_version: "", kind: ""}
  """
  @spec allow(Conn.t()) :: Conn.t()
  def allow(admission_review) do
    put_in(admission_review.response["allowed"], true)
  end

  @doc """
  Responds by denying the operation

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.deny(admission_review)
      %K8sWebhoox.Conn{request: %{}, response: %{"allowed" => false}, api_version: "", kind: ""}
  """
  @spec deny(Conn.t()) :: Conn.t()
  def deny(admission_review) do
    put_in(admission_review.response["allowed"], false)
  end

  @doc """
  Responds by denying the operation, returning response code and message

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.deny(admission_review, 403, "foo")
      %K8sWebhoox.Conn{request: %{}, response: %{"allowed" => false, "status" => %{"code" => 403, "message" => "foo"}}, api_version: "", kind: ""}

      iex> K8sWebhoox.AdmissionControl.AdmissionReview.deny(%K8sWebhoox.Conn{request: %{}, response: %{}, api_version: "", kind: ""}, "foo")
      %K8sWebhoox.Conn{request: %{}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => "foo"}}, api_version: "", kind: ""}
  """
  @spec deny(Conn.t(), integer(), binary()) :: Conn.t()
  @spec deny(Conn.t(), binary()) :: Conn.t()
  def deny(admission_review, code \\ 400, message) do
    admission_review
    |> deny()
    |> put_in([Access.key(:response), "status"], %{"code" => code, "message" => message})
  end

  @doc """
  Adds a warning to the admission review's response.

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.add_warning(admission_review, "warning")
      %K8sWebhoox.Conn{request: %{}, response: %{"warnings" => ["warning"]}, api_version: "", kind: ""}

      iex> admission_review = %K8sWebhoox.Conn{request: %{}, response: %{"warnings" => ["existing_warning"]}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.add_warning(admission_review, "new_warning")
      %K8sWebhoox.Conn{request: %{}, response: %{"warnings" => ["new_warning", "existing_warning"]}, api_version: "", kind: ""}
  """
  @spec add_warning(Conn.t(), binary()) :: Conn.t()
  def add_warning(admission_review, warning) do
    update_in(
      admission_review,
      [Access.key(:response), Access.key("warnings", [])],
      &[warning | &1]
    )
  end

  @doc """
  Defines a field as being immutable. Denies the request if the field was
  mutated.

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{"object" => %{"spec" => %{"immutable" => "value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.check_immutable(admission_review, ["spec", "immutable"])
      %K8sWebhoox.Conn{request: %{"object" => %{"spec" => %{"immutable" => "value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, api_version: "", kind: ""}

      iex> admission_review = %K8sWebhoox.Conn{request: %{"object" => %{"spec" => %{"immutable" => "new_value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.check_immutable(admission_review, ["spec", "immutable"])
      %K8sWebhoox.Conn{request: %{"object" => %{"spec" => %{"immutable" => "new_value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => "The field .spec.immutable is immutable."}}, api_version: "", kind: ""}
  """
  @spec check_immutable(Conn.t(), list()) :: Conn.t()
  def check_immutable(admission_review, field) do
    new_value = get_in(admission_review.request, ["object" | field])
    old_value = get_in(admission_review.request, ["oldObject" | field])

    if new_value == old_value,
      do: admission_review,
      else: deny(admission_review, "The field .#{Enum.join(field, ".")} is immutable.")
  end

  @doc """
  Checks the given field's value - if defined - against a list of allowed values. If the field is not defined, the
  request is considered valid and no error is returned. Use the CRD to define required fields.

  ## Examples

      iex> admission_review = %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "bar"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "bar"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, api_version: "", kind: ""}

      iex> admission_review = %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, api_version: "", kind: ""}

      iex> admission_review = %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "other"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, api_version: "", kind: ""}
      ...> K8sWebhoox.AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %K8sWebhoox.Conn{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "other"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => ~S(The field .metadata.annotations.some/annotation must contain one of the values in ["foo", "bar"] but it's currently set to "other".)}}, api_version: "", kind: ""}
  """
  @spec check_allowed_values(Conn.t(), list(), list()) :: Conn.t()
  def check_allowed_values(admission_review, field, allowed_values) do
    value = get_in(admission_review.request, ["object" | field])

    if is_nil(value) or value in allowed_values,
      do: admission_review,
      else:
        deny(
          admission_review,
          "The field .metadata.annotations.some/annotation must contain one of the values in #{inspect(allowed_values)} but it's currently set to #{inspect(value)}."
        )
  end
end
