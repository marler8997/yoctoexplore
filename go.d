#!/usr/bin/env rund
//!importPath ../maros/stdmlib
import stdm.array : contains;
import stdm.sentinel : SentinelPtr, SentinelArray, assumeSentinel, litPtr;
import stdm.c : cstring;
import stdm.mem : free;
import stdm.format : sprintMallocSentinel;
import stdm.linux.file : stdout, print, fileExists, isDir;
import stdm.linux.signals : siginfo_t;
import stdm.linux.process : pid_t, idtype_t, exit, fork, execve, waitid, WEXITED;

extern(C) extern __gshared SentinelPtr!cstring environ;
__gshared cstring PATH = cstring.nullValue;

void logError(T...)(T args)
{
    import stdm.linux.file : stderr;
    print(stderr, "Error: ", args, "\n");
}

void printArgv(SentinelPtr!cstring argv)
{
    auto prefix = "";
    for (size_t i = 0; ; i++)
    {
        auto arg = argv[i];
        if (!arg) break;
        
        print(stdout, prefix);
        prefix = " ";
        if (arg.contains(' '))
        {
            print(stdout, '"', arg, '"');
        }
        else
        {
            print(stdout, arg);
        }
    }
}

auto wait(pid_t pid)
{
    siginfo_t info;
    auto result = waitid(idtype_t.pid, pid, &info, WEXITED, null);
    if (result.failed)
    {
        logError("waitid failed, returned ", result.numval);
        //exit(result);
        exit(1);
    }
    //print(stdout, "child process status is 0x", status.formatHex, "\n");
    return info.si_status;
}

void waitEnforceSuccess(pid_t pid)
{
    auto result = wait(pid);
    if (result != 0)
    {
        logError("last program failed (exit code is ", result, " )");
        exit(1);
    }
}

// TODO: move this to maros/stdmlib
SentinelArray!(const(char)) tryFindProgram(const(char)[] name)
{
    if (PATH.isNull)
    {
        for (size_t i = 0; ; i++)
        {
            auto arg = environ[i];
            if (!arg)
            {
                PATH = litPtr!"";
                break;
            }
            if (arg.startsWith("PATH="))
            {
                PATH = (&arg[5]).assumeSentinel;
                break;
            }
        }
    }
    auto next = PATH;
    for (;;)
    {
        const(char)[] dir;
        for (size_t len = 0;; len++)
        {
            if (next[len] == ':' || next[len] == '\0')
            {
                dir = next[0 .. len];
                break;
            }
        }
        if (dir.length == 0)
            continue;
        string glue = (dir[$-1] == '/') ? "" : "/";
        auto prog = sprintMallocSentinel(dir, glue, name);
        //print(stdout, "[DEBUG] check dir '", dir, "', prog='", prog, "'\n");
        if (fileExists(prog.ptr))
            return prog;
        free(prog.ptr.raw);

        next = (dir.ptr + dir.length).assumeSentinel;
        if (next[0] == '\0')
            break;
        next++;
    }
    return typeof(return).nullValue;
}
auto findProgram(const(char)[] name)
{
    auto result = tryFindProgram(name);
    if (result.isNull)
    {
        logError("cannot find program '", name, "' in PATH");
        exit(1);
    }
    return result;
}
/*
cstring resolveProgram(cstring program)
{
    auto firstSlashIndex = program.indexOf('/');
    if (firstSlashIndex != firstSlashIndex.max)
        return program;

    auto result = findProgram(program, buffer);
    return (result == 0) ? cstring.nullValue :
        buffer.ptr.assumeSentinel;
    

}
*/

void exec(SentinelPtr!cstring argv)
{
    print(stdout, "[exec] ");
    printArgv(argv);
    print(stdout, "\n");
    auto pidResult = fork();
    if (pidResult.failed)
    {
        logError("fork failed, returned ", pidResult.numval);
        exit(1);
    }
    if (pidResult.val == 0)
    {
        auto result = execve(argv[0], argv, environ);
        logError("execve returned ", result.numval);
        exit(1);
    }
    waitEnforceSuccess(pidResult.val);
}

int main(string[] args)
{
    auto gitProgram = findProgram("git");
    print(stdout, "[DEBUG] found program: ", gitProgram, "\n");

    if (!isDir(litPtr!"poky"))
    {
        {
            static auto cloneCmd = [
                cstring.nullValue,
                cstring.assume("clone"),
                cstring.assume("git://git.yoctoproject.org/poky"),
                cstring.nullValue].assumeSentinel;
            cloneCmd[0] = gitProgram.ptr;
            exec(cloneCmd.ptr);
        }
        {
            static auto checkoutCmd = [
                cstring.nullValue,
                cstring.assume("-C"), cstring.assume("poky"),
                cstring.assume("checkout"),
                cstring.assume("tags/yocto-2.5"),
                cstring.assume("-b"), cstring.assume("yocto-2.5"),
                cstring.nullValue].assumeSentinel;
            checkoutCmd[0] = gitProgram.ptr;
            exec(checkoutCmd.ptr);
        }
    }

    return 0;
}
