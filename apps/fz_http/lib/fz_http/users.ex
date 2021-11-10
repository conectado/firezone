defmodule FzHttp.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query, warn: false
  alias FzHttp.Repo

  alias FzCommon.FzCrypto
  alias FzHttp.{Devices.Device, Users.User}

  # one hour
  @sign_in_token_validity_secs 3600

  def consume_sign_in_token(token) when is_binary(token) do
    case find_token_transaction(token) do
      {:ok, {:ok, user}} -> {:ok, user}
      {:ok, {:error, msg}} -> {:error, msg}
    end
  end

  def exists?(user_id) when is_nil(user_id) do
    false
  end

  def exists?(user_id) do
    Repo.exists?(from u in User, where: u.id == ^user_id)
  end

  def get_user!(email: email) do
    Repo.get_by!(User, email: email)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def create_user(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> create_user()
  end

  def create_user(attrs) when is_map(attrs) do
    struct(User, sign_in_keys())
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  def sign_in_keys do
    %{
      sign_in_token: FzCrypto.rand_string(),
      sign_in_token_created_at: DateTime.utc_now()
    }
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user) do
    User.changeset(user, %{})
  end

  def new_user do
    change_user(%User{})
  end

  def list_users do
    Repo.all(User)
  end

  def list_users(:with_device_counts) do
    query =
      from(
        user in User,
        left_join: device in Device,
        on: device.user_id == user.id,
        group_by: user.id,
        select_merge: %{device_count: count(device.id)}
      )

    Repo.all(query)
  end

  # XXX: For now assume first user is the admin.
  def admin do
    User |> first |> Repo.one()
  end

  defp find_by_token(token) do
    validity_secs = -1 * @sign_in_token_validity_secs
    now = DateTime.utc_now()

    Repo.one(
      from(u in User,
        where:
          u.sign_in_token == ^token and
            u.sign_in_token_created_at > datetime_add(^now, ^validity_secs, "second")
      )
    )
  end

  defp find_token_transaction(token) do
    Repo.transaction(fn ->
      case find_by_token(token) do
        nil -> {:error, "Token invalid."}
        user -> token_update_fn(user)
      end
    end)
  end

  defp token_update_fn(user) do
    result =
      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [sign_in_token: nil, sign_in_token_created_at: nil]
      )

    case result do
      {1, _result} -> {:ok, user}
      _ -> {:error, "Unexpected error attempting to clear sign in token."}
    end
  end
end
