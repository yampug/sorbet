#ifndef SORBET_OS_H
#define SORBET_OS_H
#include <functional>
#include <memory>
#include <optional>
#ifdef _WIN32
#include <thread>
#else
#include <pthread.h>
#endif
#include <string>

std::string addr2line(std::string_view programName, void const *const *addr, int count);

std::string getProgramName();

class Joinable {
    friend std::unique_ptr<Joinable> runInAThread(std::string_view threadName, std::function<void()> function,
                                                  std::optional<int> bindToCore);
#ifdef _WIN32
    std::thread thread;
#else
    pthread_t handle;
    pthread_attr_t attr;
#endif
    std::function<void()> realFunction;
    std::string originalThreadName;

    static void *trampoline(void *);

public:
    ~Joinable() {
#ifdef _WIN32
        if (thread.joinable()) {
            thread.join();
        }
#else
        void *status;
        pthread_join(handle, &status);
        pthread_attr_destroy(&attr);
#endif
    }

    Joinable() = default;
    Joinable(const Joinable &) = delete;
    Joinable(Joinable &&) = delete;
};

// run function in a thread. Return thread handle that you can join on
std::unique_ptr<Joinable> runInAThread(std::string_view threadName, std::function<void()> function,
                                       std::optional<int> bindToCore = std::nullopt);
#ifdef _WIN32
    using NativeThreadHandle = std::thread::native_handle_type;
#else
    using NativeThreadHandle = pthread_t;
#endif

bool setCurrentThreadName(std::string_view name);
bool bindThreadToCore(NativeThreadHandle handle, int coreId);

/** The should trigger debugger breakpoint if the debugger is attached, if no debugger is attach, it should do nothing
 *  This allows to:
 *   - have "persistent" break points in development loop, that survive line changes.
 *   - test the same executable outside of debugger without rebuilding.
 * */
bool stopInDebugger();
bool amIBeingDebugged();

void intentionallyLeakMemory(void *ptr);

void initializeSymbolizer(char *argv0);
#endif // SORBET_OS_H
