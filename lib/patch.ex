defmodule Tus.Patch do
  @moduledoc """
  """
  import Plug.Conn

  def patch(conn, %{version: version} = config) when version == "1.0.0" do
    with {:ok, file} <- get_file(config),
         :ok <- offsets_match?(conn, file),
         {:ok, data, conn} <- get_body(conn),
         data_size <- byte_size(data),
         :ok <- valid_size?(file, data_size),
         :ok <- append_data(config, file, data) do

      file = %Tus.File{file | offset: file.offset + data_size}
      Tus.cache_put(config, file)

      if upload_completed?(file) do
        config.on_complete_upload.(file)
      end

      conn
      |> put_resp_header("tus-resumable", config.version)
      |> put_resp_header("upload-offset", "#{file.offset}")
      |> resp(:no_content, "")
    else
      :file_not_found ->
        conn |> resp(:not_found, "File not found")

      :offsets_mismatch ->
        conn |> resp(:conflict, "Offset don't match")

      :no_body ->
        conn |> resp(:bad_request, "No body")

      :too_large ->
        conn |> resp(:request_entity_too_large, "Data is larger than expected")

      {:error, _reason} ->
        conn |> resp(:bad_request, "Unable to save file")

      :too_small ->
        conn |> resp(:conflict, "Data is smaller than what the storage backend can handle")
    end
  end

  defp get_file(config) do
    file = Tus.cache_get(config)

    if file do
      {:ok, file}
    else
      :file_not_found
    end
  end

  defp offsets_match?(conn, file) do
    if file.offset == get_offset(conn) do
      :ok
    else
      :offsets_mismatch
    end
  end

  defp get_offset(conn) do
    conn
    |> get_req_header("Upload-Offset")
    |> List.first()
    |> Kernel.||("0")
    |> String.to_integer()
  end

  defp get_body(conn) do
    case read_body(conn) do
      {_, binary, conn} -> {:ok, binary, conn}
      _ -> :no_body
    end
  end

  defp valid_size?(file, data_size) do
    if file.offset + data_size > file.size do
      :too_large
    else
      :ok
    end
  end

  defp append_data(config, file, data) do
    Tus.storage_append(config, file, data)
  end

  defp upload_completed?(file) do
    file.size == file.offset
  end
end
