//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreImage
import Foundation
#if canImport(FastVLM)
import FastVLM
#endif
import MLX
import MLXLMCommon
import MLXRandom
import MLXVLM

actor FastVLMUnityRunner {

    private enum LoadState {
        case idle
        case loading(Task<ModelContainer, Error>)
        case loaded(ModelContainer)
    }

    private var loadState: LoadState = .idle
    private var modelConfiguration: ModelConfiguration?
    private var modelDirectoryURL: URL?
    private var generateParameters = GenerateParameters(temperature: 0.0)
    private var maxTokens: Int = 240
    private var cancelOnNewRequest = true
    private var currentTask: Task<String, Error>?

    init() {
        #if canImport(FastVLM)
        FastVLM.register(modelFactory: VLMModelFactory.shared)
        #endif
        setDefaultModelDirectory()
    }

    func configure(modelDirectoryPath: String) {
        if case .loading(let task) = loadState {
            task.cancel()
        }

        if modelDirectoryPath.isEmpty {
            setDefaultModelDirectory()
        } else {
            let url = URL(fileURLWithPath: modelDirectoryPath, isDirectory: true)
            modelDirectoryURL = url
            modelConfiguration = ModelConfiguration(directory: url)
        }

        loadState = .idle
        currentTask?.cancel()
        currentTask = nil
    }

    func setGenerationOptions(temperature: Float, maxTokens: Int) {
        generateParameters = GenerateParameters(temperature: temperature)
        self.maxTokens = max(1, maxTokens)
    }

    func setCancelOnNewRequest(_ cancel: Bool) {
        cancelOnNewRequest = cancel
    }

    func loadModel() async throws {
        _ = try await loadContainer()
    }

    func generate(ciImage: CIImage, prompt: String) async throws -> String {
        if cancelOnNewRequest {
            currentTask?.cancel()
            currentTask = nil
        }

        let container = try await loadContainer()
        let userInput = UserInput(prompt: .text(prompt), images: [.ciImage(ciImage)])

        let task = Task<String, Error> {
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            let result = try await container.perform { context -> GenerateResult in
                let input = try await context.processor.prepare(input: userInput)
                return try MLXLMCommon.generate(
                    input: input,
                    parameters: generateParameters,
                    context: context
                ) { tokens in
                    if Task.isCancelled {
                        return .stop
                    }

                    return tokens.count >= maxTokens ? .stop : .more
                }
            }

            return result.output
        }

        currentTask = task

        do {
            let output = try await task.value
            if currentTask === task {
                currentTask = nil
            }
            return output
        } catch is CancellationError {
            if currentTask === task {
                currentTask = nil
            }
            throw FastVLMUnityError.cancelled
        } catch {
            if currentTask === task {
                currentTask = nil
            }
            throw error
        }
    }

    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func loadContainer() async throws -> ModelContainer {
        guard let modelConfiguration, let modelDirectoryURL else {
            throw FastVLMUnityError.modelDirectoryMissing
        }

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: modelDirectoryURL.path, isDirectory: &isDirectory)
            || !isDirectory.boolValue
        {
            throw FastVLMUnityError.modelResourcesMissing(modelDirectoryURL.path)
        }

        switch loadState {
        case .idle:
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let task = Task { () throws -> ModelContainer in
                try await VLMModelFactory.shared.loadContainer(configuration: modelConfiguration)
            }
            loadState = .loading(task)

            do {
                let container = try await task.value
                loadState = .loaded(container)
                return container
            } catch {
                loadState = .idle
                throw error
            }

        case .loading(let task):
            return try await task.value

        case .loaded(let container):
            return container
        }
    }

    private func setDefaultModelDirectory() {
        #if canImport(FastVLM)
        let bundle = Bundle(for: FastVLM.self)
        let defaultDirectory = bundle
            .url(forResource: "config", withExtension: "json")?
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        if let defaultDirectory {
            modelDirectoryURL = defaultDirectory
            modelConfiguration = ModelConfiguration(directory: defaultDirectory)
        } else {
            modelDirectoryURL = nil
            modelConfiguration = nil
        }
        #else
        modelDirectoryURL = nil
        modelConfiguration = nil
        #endif
    }
}

extension FastVLMUnityRunner.LoadState: @unchecked Sendable {}
