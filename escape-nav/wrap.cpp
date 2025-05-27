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

//TODO: fix fzf --become logic being interpreted as "child exited, Exiting regular flow (use better logic than WIFSTOPED)"
//Not sure the above applies anymore...
//
//TODO: perhaps if environment vars fail, can specify an option to skip the wrapper! Useful in cases like fzf-tab-tmux popup which obviously doesn't set TMUX_PANE

#define print_err(...) do { print_debug(__VA_ARGS__); fprintf(stderr, __VA_ARGS__); } while (0)
#define err_exit(...) do { print_err(__VA_ARGS__); exit(EXIT_FAILURE); } while (0)
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
#define print_debug(fmt, ...) print_debug_([](auto file, auto...args) { fprintf(file, fmt, args...); }, ##__VA_ARGS__)

template<class F, class...T>
static void print_debug_(F fprintf_, T const&... args) {
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
        print_debug("malloc %d", size);
        return malloc(size);
    }
    print_debug("my_alloc %d", size);
    return &env_buf[std::exchange(env_buf_index, env_buf_index + size)];
}

static pid_t do_fork(char** cmd, bool detach=false) {
    if (cmd && cmd[0]) {
#if defined(DEBUG)
        if (debug) {
            if (strcmp(cmd[0], "/opt/homebrew/bin/fzf")) {
                std::string line = cmd[0];
                for (int i = 1; cmd[i]; ++i) {
                    line += ' ';
                    line += cmd[i];
                }
                print_debug("forking %s", line.c_str());
            } else {
                if (cmd[1]) {
                    print_debug("forking FZF ARGS %s ...", cmd[1]);
                }
                else {
                    print_debug("forking %s", cmd[0]);
                }
            }
        }
#endif
        print_debug("attempting fork");
        pid_t pid = fork();
        if (pid == 0) {
            if (detach) {
                setsid();
            }
            print_debug("Child created (%s)", cmd[0]);
            execv(cmd[0], cmd);
            print_err("Failed to run '%s': %s\n", cmd[0], strerror(errno));
            exit(EXIT_FAILURE);
        }
        else if (pid < 0) {
            err_exit("Failed to fork (%s)", cmd[0]);
        }
        else {
            print_debug("Parent of fork done (%s)", cmd[0]);
        }
        return pid;
    } else {
        print_debug("(nothing to fork)");
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
    print_debug("before");
    if (set_running_flag(true)) {
        print_debug("(is not yet running)");
        auto pid = do_fork(before_cmd, true);
#ifdef WAIT_BEFORE
        if (res > 0) {
            waitpid(pid, &status, 0);
        }
#endif
    } else {
        print_debug("SKIPPED before (is already running)");
    }
}

static void after() {
    print_debug("after");
    if (set_running_flag(false)) {
        print_debug("(is running)");
        //TODO: to be honest detaching all of these without a cleanup strategy is a bit risky. In reality, probably just at least need a wait on after() even if not before() (or when exiting, a wait on all PIDs)
        //For the current tmux one, its totally fine since there isn't really a way for it to be long lived
        auto pid = do_fork(after_cmd, true);
#ifdef WAIT_AFTER
        if (res > 0) {
            waitpid(pid, &status, 0);
        }
#endif
    } else {
        print_debug("SKIPPED after (is not running)");
    }
}

static void register_handler(int sig, void(*handler)(int)) {
    struct sigaction sa;
    sigemptyset(&sa.sa_mask);           /* Reestablish handler */
    sa.sa_flags = SA_RESTART;
    sa.sa_handler = handler;
    if (sigaction(sig, &sa, NULL) == -1)
        err_exit("sigaction for signal %s", strsignal(sig));
}

static void tstp_handler(int sig)
{
    print_debug("TSTP");
    sigset_t tstp_mask, prev_mask;
    struct sigaction sa;

    if (child_pid > 0) {
        after();
        kill(child_pid, SIGTSTP);
    }
    else {
        err_exit("no child pid");
    }

    if (signal(SIGTSTP, SIG_DFL) == SIG_ERR)
        err_exit("signal");              /* Set handling to default */

    raise(SIGTSTP);                     /* Generate a further SIGTSTP */

    /* Unblock SIGTSTP; the pending SIGTSTP immediately suspends the program */

    sigemptyset(&tstp_mask);
    sigaddset(&tstp_mask, SIGTSTP);
    if (sigprocmask(SIG_UNBLOCK, &tstp_mask, &prev_mask) == -1)
        err_exit("sigprocmask (change)");

    /* Execution resumes here after SIGCONT */

    if (sigprocmask(SIG_SETMASK, &prev_mask, NULL) == -1)
        err_exit("sigprocmask (revert)");         /* Reblock SIGTSTP */

    register_handler(SIGTSTP, tstp_handler);
}

//TODO: Just forward signals and make sure that the main() exit will stil happen, if so, exit there and cleanup there (with exit codes)
static constexpr int forwarded_signals[] = {
    SIGHUP, SIGINT, SIGTERM, SIGQUIT, SIGPIPE,
    SIGUSR1, SIGUSR2, SIGALRM, SIGCHLD,
    // SIGTSTP, SIGCONT, // Handled already
    SIGWINCH
    // add more if needed
};

static void forward_signal(int sig) {
    if (child_pid > 0) {
        kill(child_pid, sig);
    }
    else {
        err_exit("no child pid");
    }
}

static void cont_handler(int sig) {
    print_debug("CONT");
    before();
    forward_signal(sig);
}

static char **parse_command(int argc, char **argv, int *index) {
    int start = *index;
    while (*index < argc && strcmp(argv[*index], ";") != 0) {
        (*index)++;
    }

    if (*index == argc) {
        err_exit("Error: Missing ';' terminator for command.\n");
    }

    argv[*index] = NULL; // Null-terminate the command array
    (*index)++;  // Skip the semicolon
    return &argv[start];
}


static void parse_args(int argc, char *argv[]) {
    if (argc < 2) {
        err_exit("Usage: %s [--before <cmd> ;] [--after <cmd> ;] <program> [args...]\n", argv[0]);
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
        err_exit("malloc() failed\n");
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
        print_debug("before %p : %s", cmd[i], cmd[i]);
    }
    bool cloned = false;
    for (int i = 0 ; cmd[i] ; ++i) {
        if (cmd[i][0] == '$') {
            char* resolved = getenv(cmd[i] + 1);
            if (!resolved) {
                #ifdef ENV_ERRORS
                err_exit("Failed to resolve '%s' from environment\n", cmd[i]);
                #else
                return NULL;
                #endif
            }
            else {
                print_debug("RESOLVED %s ==> '%s'", cmd[i], resolved);
                // Should be fine... not technically ISO C++ compliant
                #ifdef NO_MODIFY_LITERALS
                if (!cloned) {
                    cmd = clone_vec(cmd);
                    if (!cmd) {
                        print_debug("CLONE RETURNED NULL");
                        exit(1);
                    }
                    print_debug("Cloned cmd and it is still %s", cmd[i]);
                    cloned = true;
                }
                #endif
                // Need to clone getenv()
                cmd[i] = clone_str(resolved);
                print_debug("... duped %s", cmd[i]);
            }
        }
    }
    for (int i = 0; cmd[i]; ++i) {
        print_debug("after  %p : %s", cmd[i], cmd[i]);
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
        err_exit("mmap failed");
    }

    // Placement new to construct atomic_bool in shared memory
    running_flag = new(shared_mem) std::atomic_bool(false);
#endif

    register_handler(SIGTSTP, tstp_handler);
    register_handler(SIGCONT, cont_handler);
    for (int sig : forwarded_signals) {
        register_handler(sig, forward_signal);
    }

    before();

    child_pid = do_fork(wrapped_cmd);
    cleanup_pid = fork();
    int status;
    // Last-ditch cleanup_pid, disowned and polling for this process
    if (cleanup_pid == 0) {
        pid_t setsid_res = setsid();
        print_debug("setsid: %d", setsid_res);
        pid_t ppid;
        // ppid 1 is the 'init' procces. thanks chat gpt
        while ((ppid=getppid()) > 1) {
            print_debug("parent alive: %d", ppid);
            #if (CLEANUP_POLL_PERIOD_MILLIS >= 1000 && CLEANUP_POLL_PERIOD_MILLIS % 1000 < 100)
                sleep(CLEANUP_POLL_PERIOD_MILLIS / 1000);
            #else
                sleep_millis(CLEANUP_POLL_PERIOD_MILLIS);
            #endif
        }
        print_debug("CLEANUP");
        kill(child_pid, SIGTERM);
        after();
    }
    // Healthy exit strategy
    else {
        do {
            print_debug("starting wait for child");
            if (waitpid(child_pid, &status, WUNTRACED) == -1) {
                print_debug("bad waitpid: %d", status);
            }
            else {
                print_debug("child exited with status %d (%d)", status, WEXITSTATUS(status));
            }
        } while (WIFSTOPPED(status));
        print_debug("Exiting regular flow");
        kill(cleanup_pid, SIGKILL);
        after();
        if (WIFSIGNALED(status)) {
            exit(128 + WTERMSIG(status));
        }
        exit(WEXITSTATUS(status));
#ifdef DEBUG
        if (file) {
            fclose(file);
        }
#endif
    }

    return 0;
}
