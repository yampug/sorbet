#define RAPIDJSON_HAS_STDSTRING 1

#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

// Undefine write if it conflicts with rapidjson
#ifdef write
#undef write
#endif

#include "common/common.h"
#include "rapidjson/document.h"
#include "rapidjson/error/en.h"
#include "main/lsp/wrapper.h"
#include "main/lsp/LSPMessage.h"
#include "main/options/options.h"
#include "main/pipeline/semantic_extension/SemanticExtension.h"
#include "spdlog/sinks/stdout_color_sinks.h"
#include "spdlog/spdlog.h"

extern "C" {

struct SorbetState {
    std::unique_ptr<sorbet::realmain::lsp::SingleThreadedLSPWrapper> singleThreaded;
    std::unique_ptr<sorbet::realmain::lsp::MultiThreadedLSPWrapper> multiThreaded;
    bool isMultiThreaded;
};

// Helper: Parse JSON args into a vector of strings
// Supports three formats:
// 1. Array: ["--lsp", "--disable-watchman", "."]
// 2. Object: {"args": ["--lsp", "."]}
// 3. Empty: "{}" or "[]" - uses defaults
static std::vector<std::string> parseArgsJson(const char *args_json) {
    std::vector<std::string> args;
    args.push_back("sorbet"); // argv[0] always present

    if (!args_json || strlen(args_json) == 0) {
        // No input, use defaults
        args.push_back("--lsp");
        args.push_back("--disable-watchman");
        args.push_back(".");
        return args;
    }

    rapidjson::Document doc;
    doc.Parse(args_json);

    if (doc.HasParseError()) {
        std::cerr << "JSON parse error at offset " << doc.GetErrorOffset()
                  << ": " << rapidjson::GetParseError_En(doc.GetParseError()) << std::endl;
        // Fall back to defaults
        args.push_back("--lsp");
        args.push_back("--disable-watchman");
        args.push_back(".");
        return args;
    }

    // Format 1: Direct array ["--lsp", "."]
    if (doc.IsArray()) {
        if (doc.Size() == 0) {
            // Empty array, use defaults
            args.push_back("--lsp");
            args.push_back("--disable-watchman");
            args.push_back(".");
        } else {
            for (rapidjson::SizeType i = 0; i < doc.Size(); i++) {
                if (doc[i].IsString()) {
                    args.push_back(doc[i].GetString());
                }
            }
        }
        return args;
    }

    // Format 2: Object with "args" field {"args": ["--lsp", "."]}
    if (doc.IsObject()) {
        if (doc.HasMember("args") && doc["args"].IsArray()) {
            const auto &argsArray = doc["args"];
            for (rapidjson::SizeType i = 0; i < argsArray.Size(); i++) {
                if (argsArray[i].IsString()) {
                    args.push_back(argsArray[i].GetString());
                }
            }
        } else {
            // Empty object or no "args" field, use defaults
            args.push_back("--lsp");
            args.push_back("--disable-watchman");
            args.push_back(".");
        }
        return args;
    }

    // Unknown format, use defaults
    args.push_back("--lsp");
    args.push_back("--disable-watchman");
    args.push_back(".");
    return args;
}

// Initialize a new Sorbet session
SorbetState *sorbet_new(const char *args_json) {
    std::vector<std::string> args = parseArgsJson(args_json);

    // Extract root directory from args (last argument) and remove it so it's not double-counted
    std::string root_dir = ".";
    if (!args.empty()) {
        root_dir = args.back();
        args.pop_back();
    }

    std::vector<char *> argv_ptrs;
    for (auto &arg : args) {
        argv_ptrs.push_back(&arg[0]);
    }

    // Create unique logger name to allow multiple sessions
    static int logger_counter = 0;
    std::string logger_name = "console_" + std::to_string(logger_counter++);
    auto logger = spdlog::stderr_color_mt(logger_name);
    auto opts = std::make_shared<sorbet::realmain::options::Options>();
    std::vector<std::unique_ptr<sorbet::pipeline::semantic_extension::SemanticExtension>> configuredExtensions;
    std::vector<sorbet::pipeline::semantic_extension::SemanticExtensionProvider *> semanticExtensionProviders;

    try {
        sorbet::realmain::options::readOptions(*opts, configuredExtensions, argv_ptrs.size(), argv_ptrs.data(),
                                               semanticExtensionProviders, logger);
    } catch (const std::exception &e) {
        std::cerr << "Failed to parse options: " << e.what() << std::endl;
        return nullptr;
    }

    auto wrapper = sorbet::realmain::lsp::SingleThreadedLSPWrapper::create();
    wrapper->enableAllExperimentalFeatures();

    SorbetState *state = new SorbetState();
    state->singleThreaded = std::move(wrapper);
    state->multiThreaded = nullptr;
    state->isMultiThreaded = false;
    return state;
}

// Initialize a new Sorbet session (multi-threaded)
SorbetState *sorbet_new_mt(const char *args_json, int num_threads) {
    std::vector<std::string> args = parseArgsJson(args_json);

    // Extract root directory from args (last argument) and remove it so it's not double-counted
    std::string root_dir = ".";
    if (!args.empty()) {
        root_dir = args.back();
        args.pop_back();
    }

    std::vector<char *> argv_ptrs;
    for (auto &arg : args) {
        argv_ptrs.push_back(&arg[0]);
    }

    // Create unique logger name to allow multiple sessions
    static int logger_counter_mt = 0;
    std::string logger_name = "console_mt_" + std::to_string(logger_counter_mt++);
    auto logger = spdlog::stderr_color_mt(logger_name);
    auto opts = std::make_shared<sorbet::realmain::options::Options>();
    std::vector<std::unique_ptr<sorbet::pipeline::semantic_extension::SemanticExtension>> configuredExtensions;
    std::vector<sorbet::pipeline::semantic_extension::SemanticExtensionProvider *> semanticExtensionProviders;

    try {
        sorbet::realmain::options::readOptions(*opts, configuredExtensions, argv_ptrs.size(), argv_ptrs.data(),
                                               semanticExtensionProviders, logger);
    } catch (const std::exception &e) {
        std::cerr << "Failed to parse options: " << e.what() << std::endl;
        return nullptr;
    }

    // Use specified number of threads, default to 2
    int threads = num_threads > 0 ? num_threads : 2;

// Root dir extracted earlier

    auto wrapper = sorbet::realmain::lsp::MultiThreadedLSPWrapper::create(root_dir, opts, threads);
    wrapper->enableAllExperimentalFeatures();

    SorbetState *state = new SorbetState();
    state->singleThreaded = nullptr;
    state->multiThreaded = std::move(wrapper);
    state->isMultiThreaded = true;
    return state;
}

// Send an LSP message (JSON) to Sorbet and get the response (JSON)
char *sorbet_send(SorbetState *state, const char *message) {
    if (!state) {
        return nullptr;
    }

    std::string msg(message);
    std::vector<std::unique_ptr<sorbet::realmain::lsp::LSPMessage>> responses;

    if (state->isMultiThreaded && state->multiThreaded) {
        // Multi-threaded: send and read
        state->multiThreaded->send(msg);
        // Read responses (with timeout)
        while (auto response = state->multiThreaded->read(100)) {
            responses.push_back(std::move(response));
        }
    } else if (!state->isMultiThreaded && state->singleThreaded) {
        // Single-threaded: direct call
        responses = state->singleThreaded->getLSPResponsesFor(msg);
    } else {
        return nullptr;
    }

    // Combine responses into a JSON array
    std::string result = "[";
    for (size_t i = 0; i < responses.size(); ++i) {
        result += responses[i]->toJSON();
        if (i < responses.size() - 1) {
            result += ",";
        }
    }
    result += "]";

    // Copy to a malloc'd buffer so ownership passes to C
    char *c_result = (char *)malloc(result.size() + 1);
    if (c_result) {
        memcpy(c_result, result.c_str(), result.size() + 1);
    }
    return c_result;
}

// Send multiple LSP messages in batch
char *sorbet_send_batch(SorbetState *state, const char **messages, int count) {
    if (!state || !messages || count <= 0) {
        return nullptr;
    }

    std::vector<std::unique_ptr<sorbet::realmain::lsp::LSPMessage>> lsp_messages;
    lsp_messages.reserve(count);

    // Parse all messages
    for (int i = 0; i < count; ++i) {
        try {
            std::string json_msg(messages[i]);
            auto msg = sorbet::realmain::lsp::LSPMessage::fromClient(json_msg);
            if (msg) {
                lsp_messages.push_back(std::move(msg));
            }
        } catch (const std::exception &e) {
            // Skip malformed messages, continue with valid ones
            std::cerr << "Warning: Failed to parse batch message " << i << ": " << e.what() << std::endl;
            continue;
        }
    }

    std::vector<std::unique_ptr<sorbet::realmain::lsp::LSPMessage>> responses;

    if (state->isMultiThreaded && state->multiThreaded) {
        // Multi-threaded: send all messages, then read responses
        std::vector<std::unique_ptr<sorbet::realmain::lsp::LSPMessage>> msgs_copy;
        for (auto &msg : lsp_messages) {
            msgs_copy.push_back(std::move(msg));
        }
        state->multiThreaded->send(msgs_copy);

        // Read all responses (with timeout)
        int expected_responses = count; // Approximate
        for (int i = 0; i < expected_responses * 2; ++i) { // Read extra to get all
            auto response = state->multiThreaded->read(50);
            if (response) {
                responses.push_back(std::move(response));
            } else {
                break; // Timeout, no more responses
            }
        }
    } else if (!state->isMultiThreaded && state->singleThreaded) {
        // Single-threaded: use native batch API
        responses = state->singleThreaded->getLSPResponsesFor(std::move(lsp_messages));
    } else {
        return nullptr;
    }

    // Combine responses into a JSON array
    std::string result = "[";
    for (size_t i = 0; i < responses.size(); ++i) {
        result += responses[i]->toJSON();
        if (i < responses.size() - 1) {
            result += ",";
        }
    }
    result += "]";

    char *c_result = (char *)malloc(result.size() + 1);
    if (c_result) {
        memcpy(c_result, result.c_str(), result.size() + 1);
    }
    return c_result;
}

// Free a string returned by sorbet_send or sorbet_send_batch
void sorbet_free_string(char *str) {
    if (str) {
        free(str);
    }
}

// Free the Sorbet session
void sorbet_free(SorbetState *state) {
    if (state) {
        delete state;
    }
}

} // extern "C"
