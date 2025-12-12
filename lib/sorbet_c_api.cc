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

#include "main/lsp/wrapper.h"
#include "main/options/options.h"
#include "main/pipeline/semantic_extension/SemanticExtension.h"
#include "spdlog/sinks/stdout_color_sinks.h"
#include "spdlog/spdlog.h"

extern "C" {

struct SorbetState {
    std::unique_ptr<sorbet::realmain::lsp::SingleThreadedLSPWrapper> wrapper;
};

// Initialize a new Sorbet session
SorbetState *sorbet_new(const char *args_json) {
    // 1. Parse args_json into an argc/argv equivalent
    // Minimal JSON parsing or just splitting by space if assuming simple generic usage
    // For now, let's assume we pass raw arguments separated by nulls or something similar
    // Actually, to keep it simple for the C API, let's just pass a helper function
    // or assume the input is NOT json but just a string of args.
    // However, the interface says `args_json`.
    // Let's rely on the caller to pass proper args via some mechanism.
    // For this POC, let's change the API to take argc/argv or just assume standard args.
    // But sticking to the previous design:
    // We will simulate argc/argv.

    // Allow parsing a simple JSON array of strings if we had a json parser.
    // Since we don't want to introduce complex json parsing just for this init unless needed,
    // let's assume the input is a newline-separated list of arguments for now,
    // or arguably just hardcode a few things for the test, OR simpler:
    // Accept standard argc/argv in the C API?
    // Let's stick to the "args_json" idea but treating it as a space separated string for simplicity
    // or just hardcoding the critical ones. Note: The crystal side sends specific args.

    // REVISIT: The Crystal side sends nothing right now in `sorbet_new`.
    // "args" => "{}".

    std::vector<std::string> args;
    args.push_back("sorbet"); // argv[0]
    args.push_back("--lsp");
    args.push_back("--disable-watchman");
    args.push_back(".");
    // Note: In a real implementation we would parse the input string.

    std::vector<char *> argv_ptrs;
    for (auto &arg : args) {
        argv_ptrs.push_back(&arg[0]);
    }

    auto logger = spdlog::stderr_color_mt("console");
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
    state->wrapper = std::move(wrapper);
    return state;
}

// Send an LSP message (JSON) to Sorbet and get the response (JSON)
char *sorbet_send(SorbetState *state, const char *message) {
    if (!state || !state->wrapper) {
        return nullptr;
    }

    std::string msg(message);
    auto responses = state->wrapper->getLSPResponsesFor(msg);

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

// Free the Sorbet session
void sorbet_free(SorbetState *state) {
    if (state) {
        delete state;
    }
}

} // extern "C"
