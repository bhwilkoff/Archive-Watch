import Foundation

// MARK: - TMDb response types

// MARK: /find — match by external ID

struct TMDbFindResponse: Codable, Sendable {
    let movieResults: [TMDbMovieSummary]
    let tvResults: [TMDbTVSummary]

    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

struct TMDbMovieSummary: Codable, Sendable {
    let id: Int
    let title: String?
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIDs: [Int]?
    let adult: Bool?
    let originalLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, adult
        case originalTitle = "original_title"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
    }
}

struct TMDbTVSummary: Codable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
    }
}

// MARK: /movie/{id} — full detail (with append_to_response)

struct TMDbMovieDetail: Codable, Sendable {
    let id: Int
    let imdbID: String?
    let title: String?
    let originalTitle: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?              // minutes
    let genres: [TMDbGenre]?
    let productionCountries: [TMDbCountry]?
    let voteAverage: Double?
    let voteCount: Int?
    let adult: Bool?

    // Appended via ?append_to_response=credits,images,external_ids
    let credits: TMDbCredits?
    let images: TMDbImages?
    let externalIDs: TMDbExternalIDs?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, tagline, runtime, genres
        case adult, credits, images
        case imdbID = "imdb_id"
        case originalTitle = "original_title"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case productionCountries = "production_countries"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case externalIDs = "external_ids"
    }
}

struct TMDbGenre: Codable, Sendable, Hashable {
    let id: Int
    let name: String
}

struct TMDbCountry: Codable, Sendable {
    let iso3166_1: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case name
    }
}

struct TMDbCredits: Codable, Sendable {
    let cast: [TMDbCastMember]?
    let crew: [TMDbCrewMember]?
}

struct TMDbCastMember: Codable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let order: Int?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }
}

struct TMDbCrewMember: Codable, Sendable {
    let id: Int
    let name: String
    let job: String?
    let department: String?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, job, department
        case profilePath = "profile_path"
    }
}

struct TMDbImages: Codable, Sendable {
    let posters: [TMDbImage]?
    let backdrops: [TMDbImage]?
}

struct TMDbImage: Codable, Sendable {
    let filePath: String
    let aspectRatio: Double?
    let width: Int?
    let height: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let iso639_1: String?         // language code, nil = no language (e.g. textless)

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case aspectRatio = "aspect_ratio"
        case width, height
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case iso639_1 = "iso_639_1"
    }
}

struct TMDbExternalIDs: Codable, Sendable {
    let imdbID: String?
    let wikidataID: String?
    let facebookID: String?
    let instagramID: String?
    let twitterID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
        case wikidataID = "wikidata_id"
        case facebookID = "facebook_id"
        case instagramID = "instagram_id"
        case twitterID = "twitter_id"
    }
}
