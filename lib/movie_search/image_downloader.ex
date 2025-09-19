# lib/movie_search/image_downloader.ex
defmodule MovieSearch.ImageDownloader do
  require Logger

  @images_dir "priv/static/images/posters"
  @web_path "/images/posters"

  def setup_directory do
    File.mkdir_p!(@images_dir)
  end

  @doc """
  Télécharge une image depuis une URL et la sauvegarde localement
  Retourne le chemin web local ou nil si erreur
  """
  def download_and_save(image_url, movie_id) when is_binary(image_url) do
    setup_directory()

    # Génère un nom de fichier unique basé sur l'ID du film
    extension = get_extension(image_url)
    filename = "movie_#{movie_id}#{extension}"
    local_path = Path.join(@images_dir, filename)
    web_path = "#{@web_path}/#{filename}"

    # Vérifie si l'image existe déjà
    if File.exists?(local_path) do
      Logger.info("Image already cached: #{web_path}")
      {:ok, web_path}
    else
      case download_image(image_url, local_path) do
        :ok ->
          Logger.info("Downloaded image: #{web_path}")
          {:ok, web_path}
        {:error, reason} ->
          Logger.error("Failed to download image #{image_url}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp download_image(url, local_path) do
    case HTTPoison.get(url, [], timeout: 15_000, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        File.write(local_path, body)
      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_extension(url) do
    case Path.extname(url) do
      "" -> ".jpg"  # Défaut si pas d'extension
      ext -> ext
    end
  end
end
