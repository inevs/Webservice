import Foundation
import Combine

public struct HttpHeaderField {
    let field: String
    let value: String
    
    public init(field: String, value: String) {
        self.field = field
        self.value = value
    }
}

public struct QueryParameter {
    let parameter: String
    let value: String
    
    public init(parameter: String, value: String) {
        self.parameter = parameter
        self.value = value
    }
}

public enum NetworkError: Error {
    case badURL, badRequest, unknown
}

public enum APIError: Error {
    case decodingError(Error)
    case httpError(Int)
    case unknown
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public struct Webservice {
    public static var shared = Webservice()

    public func load<T>(from urlString: String, queryParameter: [QueryParameter] = [], headerFields: [HttpHeaderField] = []) -> AnyPublisher<T, APIError> where T: Decodable {
        let queryParams = buildQueryParametersFor(parameters: queryParameter)
        guard let url = URL(string: "\(urlString)\(queryParams)") else { fatalError() }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        for headerField in headerFields {
            request.addValue(headerField.value, forHTTPHeaderField: headerField.field)
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .print()
            .receive(on: DispatchQueue.main)
            .mapError { _ in .unknown }
            .flatMap { data, response -> AnyPublisher<T, APIError> in
                if let response = response as? HTTPURLResponse {
                    if (200...299).contains(response.statusCode) {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .secondsSince1970
                        return Just(data)
                            .decode(type: T.self, decoder: JSONDecoder())
                            .mapError { error in
                                return .decodingError(error) }
                            .eraseToAnyPublisher()
                    } else {
                        return Fail(error: APIError.httpError(response.statusCode))
                            .eraseToAnyPublisher()
                    }
                }
                return Fail(error: APIError.unknown)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    public func loadAsync<T>(from urlString: String, queryParameter: [QueryParameter] = [], headerFields: [HttpHeaderField] = []) async -> Result<T, APIError> where T: Decodable {
        let queryParams = buildQueryParametersFor(parameters: queryParameter)
        guard let url = URL(string: "\(urlString)\(queryParams)") else { fatalError() }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        for headerField in headerFields {
            request.addValue(headerField.value, forHTTPHeaderField: headerField.field)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(T.self, from: data)
            return .success(result)
        } catch {
            print(error.localizedDescription)
            return.failure(.decodingError(error))
        }
    }
    
    func buildQueryParametersFor(parameters: [QueryParameter]) -> String {
        if parameters.count == 0 { return "" }

        let parameterValueStrings = parameters.map { "\($0.parameter)=\($0.value)" }
        let parameterValues = parameterValueStrings.joined(separator: "&")
        return "?\(parameterValues)"
    }

    public func getKeyFor(name: String) -> String? {
        if let url = Bundle.main.url(forResource: "api-keys", withExtension: "plist") {
            do {
                let data = try Data(contentsOf: url)
                let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String:Any]
                return dict[name] as? String
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
}
