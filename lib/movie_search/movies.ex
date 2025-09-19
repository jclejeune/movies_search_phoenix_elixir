defmodule MovieSearch.Movies do
  @moduledoc """
  Module pour gérer les opérations sur les films
  """
  alias MovieSearch.{TmdbClient, ImageDownloader}

  defstruct [
    :id,
    :title,
    :year,
    :genre,
    :director,
    :rating,
    :duration,
    :description,
    :poster,
    :imdb_updated
  ]

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          year: integer(),
          genre: [String.t()],
          director: String.t(),
          rating: float(),
          duration: integer(),
          description: String.t(),
          poster: String.t(),
          imdb_updated: boolean()
        }

  @doc """
  Charge tous les films depuis le fichier JSON
  """
  def load_movies do
    case File.read("priv/movies.json") do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Map.get("movies")
        |> Enum.map(&struct(__MODULE__, atomize_keys(&1)))

      {:error, _} ->
        []
    end
  end

  @doc """
  Sauvegarde les films dans le fichier JSON (pour persister les changements)
  """
  def save_movies(movies) do
    movies_data = %{
      "movies" => Enum.map(movies, &struct_to_map/1)
    }

    json_content = Jason.encode!(movies_data, pretty: true)

    case File.write("priv/movies.json", json_content) do
      :ok ->
        IO.puts("💾 Films sauvegardés avec succès !")
        :ok

      {:error, reason} ->
        IO.puts("❌ Erreur sauvegarde: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Recherche des films par titre, genre ou réalisateur
  """
  def search_movies(movies, query) when is_binary(query) and query != "" do
    query_lower = String.downcase(query)

    Enum.filter(movies, fn movie ->
      String.contains?(String.downcase(movie.title), query_lower) ||
        String.contains?(String.downcase(movie.director), query_lower) ||
        Enum.any?(movie.genre, &String.contains?(String.downcase(&1), query_lower))
    end)
  end

  def search_movies(movies, _), do: movies

  @doc """
  Filtre les films par genre
  """
  def filter_by_genre(movies, genre) when is_binary(genre) and genre != "" do
    Enum.filter(movies, fn movie ->
      Enum.member?(movie.genre, genre)
    end)
  end

  def filter_by_genre(movies, _), do: movies

  @doc """
  Filtre les films par note minimale
  """
  def filter_by_rating(movies, min_rating) when is_number(min_rating) do
    Enum.filter(movies, fn movie ->
      movie.rating >= min_rating
    end)
  end

  def filter_by_rating(movies, _), do: movies

  @doc """
  Trie les films par différents critères
  """
  def sort_movies(movies, "title"), do: Enum.sort_by(movies, &String.downcase(&1.title))
  def sort_movies(movies, "year"), do: Enum.sort_by(movies, & &1.year, :desc)
  def sort_movies(movies, "rating"), do: Enum.sort_by(movies, & &1.rating, :desc)
  def sort_movies(movies, "duration"), do: Enum.sort_by(movies, & &1.duration, :desc)
  def sort_movies(movies, _), do: movies

  @doc """
  Récupère tous les genres uniques
  """
  def get_all_genres(movies) do
    movies
    |> Enum.flat_map(& &1.genre)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Enrichit un film avec les données TMDB ET retélécharge si l'image locale manque
  """
  def enrich_with_imdb(%__MODULE__{} = movie) do
    # ✅ Vérifie si on a une image locale ET qu'elle existe vraiment
    if has_valid_local_image?(movie.poster) do
      IO.puts("✅ Image locale OK pour: #{movie.title}")
      %{movie | imdb_updated: true}
    else
      IO.puts("🔄 Retéléchargement nécessaire pour: #{movie.title}")

      case TmdbClient.search_movie(movie.title, movie.year) do
        {:ok, %{poster: tmdb_poster_url}} when not is_nil(tmdb_poster_url) ->
          # Force le retéléchargement avec l'ID du film
          case ImageDownloader.download_and_save(tmdb_poster_url, movie.id) do
            {:ok, local_web_path} ->
              IO.puts("📥 Image retéléchargée: #{local_web_path}")
              %{movie | poster: local_web_path, imdb_updated: true}

            {:error, reason} ->
              IO.puts("❌ Échec téléchargement: #{inspect(reason)}")
              %{movie | poster: tmdb_poster_url, imdb_updated: true}
          end

        {:error, reason} ->
          require Logger

          Logger.info(
            "TMDB fetch failed pour '#{movie.title}' (#{movie.year}): #{inspect(reason)}"
          )

          %{movie | poster: get_placeholder_poster(movie), imdb_updated: false}
      end
    end
  end

  # ✅ Fonction qui vérifie VRAIMENT si l'image locale existe
  defp has_valid_local_image?(poster_path) when is_binary(poster_path) do
    cond do
      # Si c'est un chemin local /images/posters/
      String.starts_with?(poster_path, "/images/posters/") ->
        local_file_path = "priv/static#{poster_path}"
        file_exists = File.exists?(local_file_path)

        if file_exists do
          IO.puts("✅ Fichier trouvé: #{local_file_path}")
        else
          IO.puts("❌ Fichier manquant: #{local_file_path}")
        end

        file_exists

      # Si c'est encore un placeholder ou une URL externe
      true ->
        false
    end
  end

  defp has_valid_local_image?(_), do: false

  @doc """
  Génère un placeholder basé sur le genre
  """
  def get_placeholder_poster(%__MODULE__{genre: genres}) when is_list(genres) do
    primary_genre = List.first(genres) |> String.downcase()

    case primary_genre do
      "action" -> "https://picsum.photos/300/450?random=action"
      "drama" -> "https://picsum.photos/300/450?random=drama"
      "comedy" -> "https://picsum.photos/300/450?random=comedy"
      "horror" -> "https://picsum.photos/300/450?random=horror"
      "sci-fi" -> "https://picsum.photos/300/450?random=scifi"
      "romance" -> "https://picsum.photos/300/450?random=romance"
      _ -> "https://picsum.photos/300/450?random=default"
    end
  end

  # Convertit une struct en map pour la sauvegarde JSON
  defp struct_to_map(%__MODULE__{} = movie) do
    %{
      "id" => movie.id,
      "title" => movie.title,
      "year" => movie.year,
      "genre" => movie.genre,
      "director" => movie.director,
      "rating" => movie.rating,
      "duration" => movie.duration,
      "description" => movie.description,
      "poster" => movie.poster
    }
  end

  # Fonction utilitaire pour convertir les clés en atomes
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  @doc """
  Calcule le prochain ID disponible
  """
  def get_next_id(movies) do
    case movies do
      [] ->
        1

      movies ->
        movies
        |> Enum.map(& &1.id)
        |> Enum.max()
        |> Kernel.+(1)
    end
  end

  @doc """
  Ajoute un nouveau film avec ID auto-généré
  """
  def add_movie(movies, movie_params) do
    new_id = get_next_id(movies)

    new_movie = %__MODULE__{
      id: new_id,
      title: movie_params["title"],
      year: String.to_integer(movie_params["year"]),
      genre: String.split(movie_params["genre"], ",") |> Enum.map(&String.trim/1),
      director: movie_params["director"],
      rating: String.to_float(movie_params["rating"]),
      duration: String.to_integer(movie_params["duration"]),
      description: movie_params["description"],
      poster: get_placeholder_poster_for_genre(movie_params["genre"]),
      imdb_updated: false
    }

    updated_movies = movies ++ [new_movie]
    save_movies(updated_movies)

    {:ok, updated_movies, new_movie}
  end

  # Helper pour placeholder basé sur le premier genre
  defp get_placeholder_poster_for_genre(genre_string) do
    primary_genre =
      genre_string
      |> String.split(",")
      |> List.first()
      |> String.trim()
      |> String.downcase()

    case primary_genre do
      "action" -> "https://picsum.photos/300/450?random=action"
      "drama" -> "https://picsum.photos/300/450?random=drama"
      "comedy" -> "https://picsum.photos/300/450?random=comedy"
      "horror" -> "https://picsum.photos/300/450?random=horror"
      "sci-fi" -> "https://picsum.photos/300/450?random=scifi"
      "romance" -> "https://picsum.photos/300/450?random=romance"
      _ -> "https://picsum.photos/300/450?random=default"
    end
  end
end
