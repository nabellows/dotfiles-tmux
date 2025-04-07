#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <utility>

#define printErr(...) do { printDebug(__VA_ARGS__); fprintf(stderr, __VA_ARGS__); } while (0)
#define errExit(...) do { printErr(__VA_ARGS__); exit(EXIT_FAILURE); } while (0)
#define STR_(s) #s
#define STR(s) STR_(s)

pid_t child_pid = 0;
pid_t cleanup_pid = 0;
char **before_cmd = NULL;
char **after_cmd = NULL;
char **wrapped_cmd = NULL;
#ifdef DEBUG
#include <string>
bool debug = false;
FILE* file;
#endif

#ifndef ENV_BUF
#define ENV_BUF 512
#endif
#ifndef CLEANUP_POLL_PERIOD_MILLIS
#define CLEANUP_POLL_PERIOD_MILLIS 1000
#endif

#ifdef BALANCED
#include <atomic>
#include <new>
std::atomic_bool* running_flag;
#endif

uint8_t env_buf[ENV_BUF];
int env_buf_index = 0;

// Can get interrupted by signals and return early
static void sleep_millis(int millis, bool full_wait = false) {
    struct timespec ts;
    ts.tv_sec = millis / 1000;
    ts.tv_nsec = (millis % 1000) * 1000000L;

    if (full_wait) {
        while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {
            // If interrupted by a signal, nanosleep returns the remaining time in `ts`
            // This loop ensures we sleep the full requested duration
        }
    }
    else {
        nanosleep(&ts, NULL);
    }
}

// Overcomplicated just to shush fprintf non-literal warnings
#define printDebug(fmt, ...) printDebug_([](auto file, auto...args) { fprintf(file, fmt, args...); }, ##__VA_ARGS__)

template<class F, class...T>
static void printDebug_(F fprintf_, T const&... args) {
#ifdef DEBUG
    if (debug) {
        if (!file) {
            file = fopen("/Users/nbellows/wrapper-debug.txt", "a");
        }
        if (!file) {
            fprintf(stderr, "CANNOT OPEN FILE");
            return;
        }
        fprintf_(file, args...);
        fputs("\n", file);
        fflush(file);
    }
#endif
}

void* my_alloc(int size) {
    if (env_buf_index + size > ENV_BUF) {
        printDebug("malloc %d", size);
        return malloc(size);
    }
    printDebug("my_alloc %d", size);
    return &env_buf[std::exchange(env_buf_index, env_buf_index + size)];
}

static pid_t doFork(char** cmd, bool detach=false) {
    if (cmd && cmd[0]) {
#if defined(DEBUG)
        if (debug) {
            if (strcmp(cmd[0], "/opt/homebrew/bin/fzf")) {
                std::string line = cmd[0];
                for (int i = 1; cmd[i]; ++i) {
                    line += ' ';
                    line += cmd[i];
                }
                printDebug("forking %s", line.c_str());
            } else {
                if (cmd[1]) {
                    printDebug("forking FZF ARGS %s ...", cmd[1]);
                }
                else {
                    printDebug("forking %s", cmd[0]);
                }
            }
        }
#endif
        printDebug("attempting fork");
        pid_t pid = fork();
        if (pid == 0) {
            if (detach) {
                setsid();
            }
            printDebug("Child created (%s)", cmd[0]);
            execv(cmd[0], cmd);
            printErr("Failed to run '%s': %s\n", cmd[0], strerror(errno));
            exit(EXIT_FAILURE);
        }
        else if (pid < 0) {
            errExit("Failed to fork (%s)", cmd[0]);
        }
        else {
            printDebug("Parent of fork done (%s)", cmd[0]);
        }
        return pid;
    } else {
        printDebug("(nothing to fork)");
    }
    return -1;
}

// Returns true if the flag was toggled
static bool set_running_flag(bool new_state) {
#ifdef BALANCED
    bool expected = !new_state;
    return running_flag->compare_exchange_strong(expected, new_state,
                                                 std::memory_order_acquire,
                                                 std::memory_order_relaxed);
#else
    return true;
#endif
}

static void before() {
    printDebug("before");
    if (set_running_flag(true)) {
        printDebug("(is not yet running)");
        auto pid = doFork(before_cmd, true);
#ifdef WAIT_BEFORE
        if (res > 0) {
            waitpid(pid, &status, 0);
        }
#endif
    } else {
        printDebug("SKIPPED before (is already running)");
    }
}

static void after() {
    printDebug("after");
    if (set_running_flag(false)) {
        printDebug("(is running)");
        auto pid = doFork(after_cmd, true);
#ifdef WAIT_AFTER
        if (res > 0) {
            waitpid(pid, &status, 0);
        }
#endif
    } else {
        printDebug("SKIPPED after (is not running)");
    }
}

static void registerHandler(int sig, void(*handler)(int)) {
    struct sigaction sa;
    sigemptyset(&sa.sa_mask);           /* Reestablish handler */
    sa.sa_flags = SA_RESTART;
    sa.sa_handler = handler;
    if (sigaction(sig, &sa, NULL) == -1)
        errExit("sigaction for signal %s", strsignal(sig));
}

static void tstpHandler(int sig)
{
    printDebug("TSTP");
    sigset_t tstpMask, prevMask;
    struct sigaction sa;

    if (child_pid > 0) {
        after();
        kill(child_pid, SIGTSTP);
    }
    else {
        errExit("no child pid");
    }

    if (signal(SIGTSTP, SIG_DFL) == SIG_ERR)
        errExit("signal");              /* Set handling to default */

    raise(SIGTSTP);                     /* Generate a further SIGTSTP */

    /* Unblock SIGTSTP; the pending SIGTSTP immediately suspends the program */

    sigemptyset(&tstpMask);
    sigaddset(&tstpMask, SIGTSTP);
    if (sigprocmask(SIG_UNBLOCK, &tstpMask, &prevMask) == -1)
        errExit("sigprocmask (change)");

    /* Execution resumes here after SIGCONT */

    if (sigprocmask(SIG_SETMASK, &prevMask, NULL) == -1)
        errExit("sigprocmask (revert)");         /* Reblock SIGTSTP */

    registerHandler(SIGTSTP, tstpHandler);
}

static void contHandler(int sig) {
    printDebug("CONT");
    before();
    kill(child_pid, SIGCONT);
}

static void exitHandler(int sig) {
    printDebug("error handler");
    kill(child_pid, sig);
    after();
    if (cleanup_pid > 0) {
        kill(cleanup_pid, SIGKILL);
    }
    exit(EXIT_FAILURE);
}

static char **parse_command(int argc, char **argv, int *index) {
    int start = *index;
    while (*index < argc && strcmp(argv[*index], ";") != 0) {
        (*index)++;
    }

    if (*index == argc) {
        errExit("Error: Missing ';' terminator for command.\n");
    }

    argv[*index] = NULL; // Null-terminate the command array
    (*index)++;  // Skip the semicolon
    return &argv[start];
}


static void parse_args(int argc, char *argv[]) {
    if (argc < 2) {
        errExit("Usage: %s [--before <cmd> ;] [--after <cmd> ;] <program> [args...]\n", argv[0]);
    }
    // Parse arguments
    int i = 1;
    while (i < argc) {
        if (strcmp(argv[i], "--before") == 0) {
            i++;
            before_cmd = parse_command(argc, argv, &i);
        } else
        if (strcmp(argv[i], "--after") == 0) {
            i++;
            after_cmd = parse_command(argc, argv, &i);
        } else {
            break;
        }
    }
    wrapped_cmd = &argv[i];
}


template<class T>
static T** clone_vec(T** vec) {
    int count = 0;
    while (vec[count]) ++count;
    int size = (count+1) * sizeof(T*);
    T** res = (T**) my_alloc(size);
    if (!res) {
        errExit("malloc() failed\n");
    }
    memcpy(res, vec, size);
    return res;
}

static char* clone_str(char* str) {
    int len = strlen(str) + 1;
    char* res = (char*) my_alloc(len * sizeof(char));
    memcpy(res, str, len * sizeof(char));
    return res;
}

static char** resolve_env(char** cmd) {
    if (!cmd) return NULL;
    for (int i = 0; cmd[i]; ++i) {
        printDebug("before %p : %s", cmd[i], cmd[i]);
    }
    bool cloned = false;
    for (int i = 0 ; cmd[i] ; ++i) {
        if (cmd[i][0] == '$') {
            char* resolved = getenv(cmd[i] + 1);
            if (!resolved) {
                errExit("Failed to resolve '%s' from environment\n", cmd[i]);
            }
            else {
                printDebug("RESOLVED %s ==> '%s'", cmd[i], resolved);
                // Should be fine... not technically ISO C++ compliant
                #ifdef NO_MODIFY_LITERALS
                if (!cloned) {
                    cmd = clone_vec(cmd);
                    if (!cmd) {
                        printDebug("CLONE RETURNED NULL");
                        exit(1);
                    }
                    printDebug("Cloned cmd and it is still %s", cmd[i]);
                    cloned = true;
                }
                #endif
                // Need to clone getenv()
                cmd[i] = clone_str(resolved);
                printDebug("... duped %s", cmd[i]);
            }
        }
    }
    for (int i = 0; cmd[i]; ++i) {
        printDebug("after  %p : %s", cmd[i], cmd[i]);
    }
    return cmd;
}

int main(int argc, char *argv[]) {
#ifdef DEBUG
    debug = getenv("DEBUG");
#endif
#if defined(BEFORE_CMD) || defined(AFTER_CMD) || defined(PROGRAM)
#if !(defined(BEFORE_CMD) && defined(AFTER_CMD) && defined(PROGRAM))
    #error "All or none of BEFORE_CMD/AFTER_CMD/PROGRAM need to be defined"
#endif
    static const char* _before_cmd[] = { BEFORE_CMD, 0 };
    before_cmd = (char**) _before_cmd;
    static const char* _after_cmd[] = { AFTER_CMD, 0 };
    after_cmd = (char **) _after_cmd;
    argv[0] = (char *) STR(PROGRAM) ;
    wrapped_cmd = argv;
#else
    parse_args(argc, argv);
#endif
    before_cmd = resolve_env(before_cmd);
    after_cmd = resolve_env(after_cmd);
    wrapped_cmd = resolve_env(wrapped_cmd);

#ifdef BALANCED
    // Allocate shared memory with mmap
    void* shared_mem = mmap(nullptr, sizeof(std::atomic_bool),
                            PROT_READ | PROT_WRITE,
                            MAP_SHARED | MAP_ANONYMOUS, -1, 0);

    if (shared_mem == MAP_FAILED) {
        errExit("mmap failed");
    }

    // Placement new to construct atomic_bool in shared memory
    running_flag = new(shared_mem) std::atomic_bool(false);
#endif

    registerHandler(SIGTSTP, tstpHandler);
    registerHandler(SIGCONT, contHandler);
    for (int sig : { SIGINT, SIGTERM, SIGQUIT, SIGPIPE, SIGHUP }) {
        registerHandler(sig, exitHandler);
    }

    before();

    child_pid = doFork(wrapped_cmd);
    cleanup_pid = fork();
    int status;
    // Last-ditch cleanup_pid, disowned and polling for this process
    if (cleanup_pid == 0) {
        pid_t setsid_res = setsid();
        printDebug("setsid: %d", setsid_res);
        pid_t ppid;
        // ppid 1 is the 'init' procces. thanks chat gpt
        while ((ppid=getppid()) > 1) {
            printDebug("parent alive: %d", ppid);
            #if (CLEANUP_POLL_PERIOD_MILLIS >= 1000 && CLEANUP_POLL_PERIOD_MILLIS % 1000 < 100)
                sleep(CLEANUP_POLL_PERIOD_MILLIS / 1000);
            #else
                sleep_millis(CLEANUP_POLL_PERIOD_MILLIS);
            #endif
        }
        printDebug("CLEANUP");
        kill(child_pid, SIGTERM);
        after();
    }
    // Healthy exit strategy
    else {
        do {
            printDebug("starting wait for child");
            if (waitpid(child_pid, &status, WUNTRACED) == -1) {
                printDebug("bad waitpid: %d", status);
            }
            else {
                printDebug("child exited");
            }
        } while (WIFSTOPPED(status));
        //TODO: for a while, fzf-lua was still invoking this, but now it doesn't...
        printDebug("Exiting regular flow");
        kill(cleanup_pid, SIGKILL);
        after();
        // I am a little paranoid about kill race condition with cleanup_pid - my understanding is that the kill
        // is synchronous and immediately suspends scheduling of CPU for that process, but I have doubts
        // usleep(100000); // 100 ms
#ifdef DEBUG
        if (file) {
            fclose(file);
        }
#endif
    }

    return 0;
}
