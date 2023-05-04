import SuggestionModel
import Foundation
import LanguageClient
import LanguageServerProtocol
import Logger
import Preferences
import XPCShared

public protocol GitHubCopilotAuthServiceType {
    func checkStatus() async throws -> GitHubCopilotAccountStatus
    func signInInitiate() async throws -> (verificationUri: String, userCode: String)
    func signInConfirm(userCode: String) async throws -> (username: String, status: GitHubCopilotAccountStatus)
    func signOut() async throws -> GitHubCopilotAccountStatus
    func version() async throws -> String
}

public protocol GitHubCopilotSuggestionServiceType {
    func getCompletions(
        fileURL: URL,
        content: String,
        cursorPosition: CursorPosition,
        tabSize: Int,
        indentSize: Int,
        usesTabsForIndentation: Bool,
        ignoreSpaceOnlySuggestions: Bool
    ) async throws -> [CodeSuggestion]
    func notifyAccepted(_ completion: CodeSuggestion) async
    func notifyRejected(_ completions: [CodeSuggestion]) async
    func notifyOpenTextDocument(fileURL: URL, content: String) async throws
    func notifyChangeTextDocument(fileURL: URL, content: String) async throws
    func notifyCloseTextDocument(fileURL: URL) async throws
    func notifySaveTextDocument(fileURL: URL) async throws
}

protocol GitHubCopilotLSP {
    func sendRequest<E: GitHubCopilotRequestType>(_ endpoint: E) async throws -> E.Response
    func sendNotification(_ notif: ClientNotification) async throws
}

public class GitHubCopilotBaseService {
    let projectRootURL: URL
    var server: GitHubCopilotLSP

    init(designatedServer: GitHubCopilotLSP) {
        projectRootURL = URL(fileURLWithPath: "/")
        server = designatedServer
    }

    init(projectRootURL: URL) {
        self.projectRootURL = projectRootURL
        server = {
            let supportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("com.intii.CopilotForXcode")
            if !FileManager.default.fileExists(atPath: supportURL.path) {
                try? FileManager.default
                    .createDirectory(at: supportURL, withIntermediateDirectories: false)
            }
            var userEnvPath = ProcessInfo.processInfo.userEnvironment["PATH"] ?? ""
            if userEnvPath.isEmpty {
                userEnvPath = "/usr/bin:/usr/local/bin" // fallback
            }
            let executionParams: Process.ExecutionParameters
            let runner = UserDefaults.shared.value(for: \.runNodeWith)

            switch runner {
            case .bash:
                let nodePath = UserDefaults.shared.value(for: \.nodePath)
                let command = [
                    nodePath.isEmpty ? "node" : nodePath,
                    "\"\(Bundle.main.url(forResource: "agent", withExtension: "js", subdirectory: "copilot/dist")!.path)\"",
                    "--stdio",
                ].joined(separator: " ")
                executionParams = {
                    Process.ExecutionParameters(
                        path: "/bin/bash",
                        arguments: ["-i", "-l", "-c", command],
                        environment: [:],
                        currentDirectoryURL: supportURL
                    )
                }()
            case .shell:
                let shell = ProcessInfo.processInfo.userEnvironment["SHELL"] ?? "/bin/bash"
                let nodePath = UserDefaults.shared.value(for: \.nodePath)
                let command = [
                    nodePath.isEmpty ? "node" : nodePath,
                    "\"\(Bundle.main.url(forResource: "agent", withExtension: "js", subdirectory: "copilot/dist")!.path)\"",
                    "--stdio",
                ].joined(separator: " ")
                executionParams = {
                    Process.ExecutionParameters(
                        path: shell,
                        arguments: ["-i", "-l", "-c", command],
                        environment: [:],
                        currentDirectoryURL: supportURL
                    )
                }()
            case .env:
                executionParams = {
                    let nodePath = UserDefaults.shared.value(for: \.nodePath)
                    return Process.ExecutionParameters(
                        path: "/usr/bin/env",
                        arguments: [
                            nodePath.isEmpty ? "node" : nodePath,
                            Bundle.main.url(
                                forResource: "agent",
                                withExtension: "js",
                                subdirectory: "copilot/dist"
                            )!.path,
                            "--stdio",
                        ],
                        environment: [
                            "PATH": userEnvPath,
                        ],
                        currentDirectoryURL: supportURL
                    )
                }()
            }
            let localServer = CopilotLocalProcessServer(executionParameters: executionParams)
            localServer.logMessages = false
            localServer.notificationHandler = { _, respond in
                respond(.timeout)
            }
            let server = InitializingServer(server: localServer)

            server.initializeParamsProvider = {
                let capabilities = ClientCapabilities(
                    workspace: nil,
                    textDocument: nil,
                    window: nil,
                    general: nil,
                    experimental: nil
                )

                return InitializeParams(
                    processId: Int(ProcessInfo.processInfo.processIdentifier),
                    clientInfo: .init(name: "Copilot for Xcode"),
                    locale: nil,
                    rootPath: projectRootURL.path,
                    rootUri: projectRootURL.path,
                    initializationOptions: nil,
                    capabilities: capabilities,
                    trace: .off,
                    workspaceFolders: nil
                )
            }

            return server
        }()
    }
}

public final class GitHubCopilotAuthService: GitHubCopilotBaseService, GitHubCopilotAuthServiceType {
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        super.init(projectRootURL: home)
        Task {
            try? await server.sendRequest(GitHubCopilotRequest.SetEditorInfo())
        }
    }

    public func checkStatus() async throws -> GitHubCopilotAccountStatus {
        try await server.sendRequest(GitHubCopilotRequest.CheckStatus()).status
    }

    public func signInInitiate() async throws -> (verificationUri: String, userCode: String) {
        let result = try await server.sendRequest(GitHubCopilotRequest.SignInInitiate())
        return (result.verificationUri, result.userCode)
    }

    public func signInConfirm(userCode: String) async throws
        -> (username: String, status: GitHubCopilotAccountStatus)
    {
        let result = try await server.sendRequest(GitHubCopilotRequest.SignInConfirm(userCode: userCode))
        return (result.user, result.status)
    }

    public func signOut() async throws -> GitHubCopilotAccountStatus {
        try await server.sendRequest(GitHubCopilotRequest.SignOut()).status
    }

    public func version() async throws -> String {
        try await server.sendRequest(GitHubCopilotRequest.GetVersion()).version
    }
}

public final class GitHubCopilotSuggestionService: GitHubCopilotBaseService, GitHubCopilotSuggestionServiceType {
    override public init(projectRootURL: URL = URL(fileURLWithPath: "/")) {
        super.init(projectRootURL: projectRootURL)
    }

    override init(designatedServer: GitHubCopilotLSP) {
        super.init(designatedServer: designatedServer)
    }

    public func getCompletions(
        fileURL: URL,
        content: String,
        cursorPosition: CursorPosition,
        tabSize: Int,
        indentSize: Int,
        usesTabsForIndentation: Bool,
        ignoreSpaceOnlySuggestions: Bool
    ) async throws -> [CodeSuggestion] {
        let languageId = languageIdentifierFromFileURL(fileURL)

        let relativePath = {
            let filePath = fileURL.path
            let rootPath = projectRootURL.path
            if let range = filePath.range(of: rootPath),
               range.lowerBound == filePath.startIndex
            {
                let relativePath = filePath.replacingCharacters(
                    in: filePath.startIndex..<range.upperBound,
                    with: ""
                )
                return relativePath
            }
            return filePath
        }()

        let completions = try await server
            .sendRequest(GitHubCopilotRequest.GetCompletionsCycling(doc: .init(
                source: content,
                tabSize: tabSize,
                indentSize: indentSize,
                insertSpaces: !usesTabsForIndentation,
                path: fileURL.path,
                uri: fileURL.path,
                relativePath: relativePath,
                languageId: languageId,
                position: cursorPosition
            )))
            .completions
            .filter { completion in
                if ignoreSpaceOnlySuggestions {
                    return !completion.text.allSatisfy { $0.isWhitespace || $0.isNewline }
                }
                return true
            }

        return completions
    }

    public func notifyAccepted(_ completion: CodeSuggestion) async {
        _ = try? await server.sendRequest(
            GitHubCopilotRequest.NotifyAccepted(completionUUID: completion.uuid)
        )
    }

    public func notifyRejected(_ completions: [CodeSuggestion]) async {
        _ = try? await server.sendRequest(
            GitHubCopilotRequest.NotifyRejected(completionUUIDs: completions.map(\.uuid))
        )
    }

    public func notifyOpenTextDocument(
        fileURL: URL,
        content: String
    ) async throws {
        let languageId = languageIdentifierFromFileURL(fileURL)
        let uri = "file://\(fileURL.path)"
//        Logger.service.debug("Open \(uri), \(content.count)")
        try await server.sendNotification(
            .didOpenTextDocument(
                DidOpenTextDocumentParams(
                    textDocument: .init(
                        uri: uri,
                        languageId: languageId.rawValue,
                        version: 0,
                        text: content
                    )
                )
            )
        )
    }

    public func notifyChangeTextDocument(fileURL: URL, content: String) async throws {
        let uri = "file://\(fileURL.path)"
//        Logger.service.debug("Change \(uri), \(content.count)")
        try await server.sendNotification(
            .didChangeTextDocument(
                DidChangeTextDocumentParams(
                    uri: uri,
                    version: 0,
                    contentChange: .init(
                        range: nil,
                        rangeLength: nil,
                        text: content
                    )
                )
            )
        )
    }

    public func notifySaveTextDocument(fileURL: URL) async throws {
        let uri = "file://\(fileURL.path)"
//        Logger.service.debug("Save \(uri)")
        try await server.sendNotification(.didSaveTextDocument(.init(uri: uri)))
    }

    public func notifyCloseTextDocument(fileURL: URL) async throws {
        let uri = "file://\(fileURL.path)"
//        Logger.service.debug("Close \(uri)")
        try await server.sendNotification(.didCloseTextDocument(.init(uri: uri)))
    }
}

extension InitializingServer: GitHubCopilotLSP {
    func sendRequest<E: GitHubCopilotRequestType>(_ endpoint: E) async throws -> E.Response {
        try await sendRequest(endpoint.request)
    }
}
