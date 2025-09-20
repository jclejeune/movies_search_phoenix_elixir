# 🎬 MovieSearch

MovieSearch est une application Phoenix qui permet de rechercher des films grâce à l’API [The Movie Database (TMDB)](https://www.themoviedb.org/).

---

## ⚙️ Installation

### Prérequis

- [Elixir](https://elixir-lang.org/install.html) ≥ 1.14  
- [Phoenix](https://hexdocs.pm/phoenix/installation.html) ≥ 1.7  
- [PostgreSQL](https://www.postgresql.org/download/) (si utilisé pour le projet)

### Vérifiez vos versions
`
    elixir -v  
    mix phx.new -v  
`


### Installer le projet

Clonez le dépôt et installez les dépendances :
`
    git clone https://github.com/jclejeune/movies_search_phoenix_elixir.git  
    cd movie_search  
    mix setup  
`

---

## 🔑 Configuration de l’API TMDB

1. Créez un compte sur https://www.themoviedb.org/  

2. Allez dans Settings > API et générez une clé API v3.  

3. Créez un fichier `config/secrets.exs` (⚠️ ajoutez-le dans `.gitignore`) :

    ```elixir
        # config/secrets.exs
        import Config

        config :movie_search, :tmdb,
            api_key: "VOTRE_CLE_API_ICI"
    ```

4. Importez ce fichier dans `config/config.exs` :

    ```elixir
        # config/config.exs
        import_config "secrets.exs"
    ```

5. Dans le client TMDB, récupérez la clé via `Application.get_env/2` :

    ```elixir
        defmodule MovieSearch.TmdbClient do
        require Logger

        @base_url "https://api.themoviedb.org/3"
        @image_base_url "https://image.tmdb.org/t/p/w500"

        def api_key do
            Application.get_env(:movie_search, :tmdb)[:api_key]
        end

        def search_movie(query) do
            url = "#{@base_url}/search/movie?api_key=#{api_key()}&query=#{URI.encode(query)}"
            # ...
        end
        end
    ```

---

## 🚀 Lancer l’application

### Installez les dépendances et configurez le projet :  

    `
        mix setup
    `

### Lancez le serveur Phoenix :  

    `
        iex -S mix phx.server 
    `

### Ouvrez http://localhost:4000 dans votre navigateur.

---

## 🧪 Tests

### Lancer les tests :  

    `
        mix test
    `

### Vérifier le formatage du code :  

    `
        mix format --check-formatted 
    `
---

## 📚 Ressources utiles

- Phoenix Framework : https://www.phoenixframework.org/  
- Guides Phoenix : https://hexdocs.pm/phoenix/overview.html  
- Documentation Elixir : https://hexdocs.pm/elixir/  
- Forum Phoenix : https://elixirforum.com/c/phoenix-forum  
- API TMDB : https://developer.themoviedb.org/docs  

---

## 📜 Licence

Ce projet est distribué sous licence MIT.  


