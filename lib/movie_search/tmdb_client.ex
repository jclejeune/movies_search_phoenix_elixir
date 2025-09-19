defmodule MovieSearch.TmdbClient do
  require Logger

  @base_url "https://api.themoviedb.org/3"
  @image_base_url "https://image.tmdb.org/t/p/w500"
  # Remplace par ta vraie clé API TMDB
  @api_key "7bed753dbf4a431a4f49a78ce0e95c32"

  def search_movie(title, year \\ nil) do
    params = %{
      "api_key" => @api_key,
      "query" => title
    }

    params = if year, do: Map.put(params, "year", year), else: params

    url = "#{@base_url}/search/movie?" <> URI.encode_query(params)

    # Debug - enlève cette ligne une fois que ça marche
    IO.puts("🔍 URL: #{url}")

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => [movie | _]}} ->
            poster_path = movie["poster_path"]
            if poster_path do
              {:ok, %{
                poster: @image_base_url <> poster_path,
                tmdb_id: movie["id"],
                title: movie["title"],
                year: extract_year(movie["release_date"]),
                rating: movie["vote_average"]
              }}
            else
              {:error, :no_poster}
            end
          {:ok, %{"results" => []}} ->
            {:error, :not_found}
          {:error, reason} ->
            Logger.error("JSON decode error: #{inspect(reason)}")
            {:error, reason}
        end
      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("TMDB API error: status #{status}")
        {:error, {:api_error, status}}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_year(nil), do: nil
  defp extract_year(date) when is_binary(date) do
    case String.split(date, "-") do
      [year | _] -> String.to_integer(year)
      _ -> nil
    end
  end
end
