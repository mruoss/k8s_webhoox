defmodule AdmissionControl.AdmissionReview do
  @moduledoc """
  This module defines a struct which is used as token in the `Pluggable`
  pipeline handling an admission request. See `AdmissionControl.Plug` for more
  information on how to set up the request handler pipeline.

  This module also defines a set of useful helpers when processing an admission
  request.
  """

  require Logger

  @derive Pluggable.Token

  @typedoc """
  Currently validating and mutating webhooks are supported.
  """
  @type webhook_type :: :mutating | :validating

  @typedoc """
  The struct used as token in the request handler pipeline.

  ## Fields

  - `request` - The body of the HTTPS request representing the admission
    request.
  - `response` - The resposne the request handler pipeline is suposed to define.
  - `webhook_type` - Whether this request was sent to the validating or mutating
    webhook.

  ## Internal Fields

  - `halted` - Whether the pipeline is halted or not. Defaults to `false`.
  - `assigns` - A map used to internally forward data within the pipeline.
    Defaults to `%{}`.
  """
  @type t :: %__MODULE__{
          request: map(),
          response: map(),
          webhook_type: webhook_type(),
          halted: boolean(),
          assigns: map()
        }

  @enforce_keys [:request, :response, :webhook_type]
  defstruct [:request, :response, :webhook_type, halted: false, assigns: %{}]

  @spec new(resource :: map(), webhook_type :: binary()) :: t()
  def new(%{"kind" => "AdmissionReview", "request" => request}, webhook_type) do
    struct!(__MODULE__,
      request: request,
      response: %{"uid" => request["uid"]},
      webhook_type: webhook_type
    )
  end

  @doc """
  Responds by allowing the operation

  ## Examples

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.allow(admission_review)
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"allowed" => true}, webhook_type: :validating}
  """
  @spec allow(t()) :: t()
  def allow(admission_review) do
    put_in(admission_review.response["allowed"], true)
  end

  @doc """
  Responds by denying the operation

  ## Examples

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.deny(admission_review)
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"allowed" => false}, webhook_type: :validating}
  """
  @spec deny(t()) :: t()
  def deny(admission_review) do
    put_in(admission_review.response["allowed"], false)
  end

  @doc """
  Responds by denying the operation, returning response code and message

  ## Examples

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.deny(admission_review, 403, "foo")
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"allowed" => false, "status" => %{"code" => 403, "message" => "foo"}}, webhook_type: :validating}

      iex> AdmissionControl.AdmissionReview.deny(%AdmissionControl.AdmissionReview{request: %{}, response: %{}, webhook_type: :validating}, "foo")
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => "foo"}}, webhook_type: :validating}
  """
  @spec deny(t(), integer(), binary()) :: t()
  @spec deny(t(), binary()) :: t()
  def deny(admission_review, code \\ 400, message) do
    admission_review
    |> deny()
    |> put_in([Access.key(:response), "status"], %{"code" => code, "message" => message})
  end

  @doc """
  Adds a warning to the admission review's response.

  ## Examples

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.add_warning(admission_review, "warning")
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"warnings" => ["warning"]}, webhook_type: :validating}

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{}, response: %{"warnings" => ["existing_warning"]}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.add_warning(admission_review, "new_warning")
      %AdmissionControl.AdmissionReview{request: %{}, response: %{"warnings" => ["new_warning", "existing_warning"]}, webhook_type: :validating}
  """
  @spec add_warning(t(), binary()) :: t()
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

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{"object" => %{"spec" => %{"immutable" => "value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.check_immutable(admission_review, ["spec", "immutable"])
      %AdmissionControl.AdmissionReview{request: %{"object" => %{"spec" => %{"immutable" => "value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, webhook_type: :validating}

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{"object" => %{"spec" => %{"immutable" => "new_value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.check_immutable(admission_review, ["spec", "immutable"])
      %AdmissionControl.AdmissionReview{request: %{"object" => %{"spec" => %{"immutable" => "new_value"}}, "oldObject" => %{"spec" => %{"immutable" => "value"}}}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => "The field .spec.immutable is immutable."}}, webhook_type: :validating}
  """
  @spec check_immutable(t(), list()) :: t()
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

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "bar"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "bar"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, webhook_type: :validating}

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, webhook_type: :validating}

      iex> admission_review = %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "other"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{}, webhook_type: :validating}
      ...> AdmissionControl.AdmissionReview.check_allowed_values(admission_review, ~w(metadata annotations some/annotation), ["foo", "bar"])
      %AdmissionControl.AdmissionReview{request: %{"object" => %{"metadata" => %{"annotations" => %{"some/annotation" => "other"}}, "spec" => %{}}, "oldObject" => %{"spec" => %{}}}, response: %{"allowed" => false, "status" => %{"code" => 400, "message" => ~S(The field .metadata.annotations.some/annotation must contain one of the values in ["foo", "bar"] but it's currently set to "other".)}}, webhook_type: :validating}
  """
  @spec check_allowed_values(t(), list(), list()) :: t()
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
