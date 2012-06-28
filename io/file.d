module io.file;

import io.core;
version(Windows)
{
    import sys.windows;
}
else version(Posix)
{
    import core.sys.posix.sys.types;
    import core.sys.posix.sys.stat;
    import core.sys.posix.fcntl;
    import core.sys.posix.unistd;
    import core.stdc.errno;
    alias int HANDLE;
}

debug
{
    import std.stdio : writeln, writefln;
}

/**
File is seekable device.
*/
struct File
{
private:
  version(Windows)
  {
    HANDLE hFile = null;
  }
  version(Posix)
  {
    private HANDLE hFile = -1;
  }
    size_t* pRefCounter;

public:
    /**
    */
    this(string fname, in char[] mode = "r")
    {
      version(Posix)
      {
        int flags;
        switch (mode)
        {
            case "r":
                flags = O_RDONLY;
                break;
            case "w":
                flags = O_WRONLY;
                break;
            case "a":
            case "r+":
            case "w+":
            case "a+":
            default:
                assert(0);
                break;
        }
        attach(open(fname.ptr, flags | O_NONBLOCK));
version(none)
{
        int share = octal!666;
        int access;
        int createMode;
        if (mode & FileMode.In)
            access = O_RDONLY;
        if (mode & FileMode.Out)
        {
            createMode = O_CREAT;   // will create if not present
            access = O_WRONLY;
        }
        if (access == (O_WRONLY | O_RDONLY))
            access = O_RDWR;
        if ((mode & FileMode.OutNew) == FileMode.OutNew)
            access |= O_TRUNC;      // resets file
        attach(h = core.sys.posix.fcntl.open(toUTFz(filename),
                                             access | createMode, share));
}
      }
      version(Windows)
      {
        int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
        int access = void;
        int createMode = void;

        // fopenにはOPEN_ALWAYSに相当するModeはない？
        switch (mode)
        {
            case "r":
                access = GENERIC_READ;
                createMode = OPEN_EXISTING;
                break;
            case "w":
                access = GENERIC_WRITE;
                createMode = CREATE_ALWAYS;
                break;
            case "a":
                assert(0);

            case "r+":
                access = GENERIC_READ | GENERIC_WRITE;
                createMode = OPEN_EXISTING;
                break;
            case "w+":
                access = GENERIC_READ | GENERIC_WRITE;
                createMode = CREATE_ALWAYS;
                break;
            case "a+":
                assert(0);

            // do not have binary mode(binary access only)
        //  case "rb":
        //  case "wb":
        //  case "ab":
        //  case "rb+": case "r+b":
        //  case "wb+": case "w+b":
        //  case "ab+": case "a+b":
            default:
                break;
        }

        attach(CreateFileW(std.utf.toUTFz!(const(wchar)*)(fname),
                           access, share, null, createMode, 0, null));
      }
    }
    package this(HANDLE h)
    {
        attach(h);
    }
    this(this)
    {
        if (pRefCounter)
            ++(*pRefCounter);
    }
    ~this()
    {
        detach();
    }

    @property HANDLE handle() { return hFile; }

    //
    //@property inout(HANDLE) handle() inout { return hFile; }
    //alias handle this;

    bool opEquals(ref const File rhs) const
    {
        return hFile == rhs.hFile;
    }
    bool opEquals(HANDLE h) const
    {
        return hFile == h;
    }


    /**
    */
    void attach(HANDLE h)
    {
        if (hFile)
            detach();
        hFile = h;
        pRefCounter = new size_t;
        *pRefCounter = 1;
    }
    /// ditto
    void detach()
    {
        if (pRefCounter)
        {
            if (--(*pRefCounter) == 0)
            {
                //delete pRefCounter;   // trivial: delegate management to GC.
              version(Windows)
              {
                CloseHandle(hFile);
                hFile = null;
              }
              version(Posix)
              {
                core.sys.posix.unistd.close(hFile);
                hFile = -1;
              }
            }
            //pRefCounter = null;       // trivial: do not need
        }
    }

    //typeof(this) dup() { return this; }
    //typeof(this) dup() shared {}

    /**
    Request n number of elements.
    $(D buf) is treated as an output range.
    Returns:
        $(UL
            $(LI $(D true ) : You can request next pull.)
            $(LI $(D false) : No element exists.))
    */
    bool pull(ref ubyte[] buf)
    {
        static import std.stdio;
        debug(File)
            std.stdio.writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, buf.length);

      version(Posix)
      {
        int n = core.sys.posix.unistd.read(hFile, buf.ptr, buf.length);
        if (n >= 0)
        {
            buf = buf[n .. $];
            return (n > 0);
        }
        else
        {
            switch (errno)
            {
                case EAGAIN:
                    return true;
                default:
                    break;
            }
            throw new Exception("pull(ref buf[]) error");
        }
      }
      version(Windows)
      {
        DWORD size = void;

        // Reading console input always returns UTF-16
        if (GetFileType(hFile) == FILE_TYPE_CHAR)
        {
            if (ReadConsoleW(hFile, buf.ptr, buf.length/2, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)hFile, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("C buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size*2]);
                buf = buf[size * 2 .. $];
                return (size > 0);  // valid on only blocking read
            }
        }
        else
        {
            if (ReadFile(hFile, buf.ptr, buf.length, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)hFile, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("F buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size.. $];
                return (size > 0);  // valid on only blocking read
            }
        }

        {
            switch (GetLastError())
            {
                case ERROR_BROKEN_PIPE:
                    return false;
                default:
                    break;
            }

            debug(File)
                std.stdio.writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
                    cast(uint)hFile, size, GetLastError());
            throw new Exception("pull(ref buf[]) error");

        //  // for overlapped I/O
        //  eof = (GetLastError() == ERROR_HANDLE_EOF);
        }
      }
    }

    /**
    */
    bool push(ref const(ubyte)[] buf)
    {
      version(Posix)
      {
        int n = core.sys.posix.unistd.write(hFile, buf.ptr, buf.length);
        if (n >= 0)
        {
            buf = buf[n .. $];
            return (n > 0);
        }
        else
        {
            switch (errno)
            {
                case EAGAIN:
                    return true;
                case EPIPE:
                    return false;
                default:
                    break;
            }
            throw new Exception("push error");  //?
        }
      }
      version(Windows)
      {
        DWORD size = void;
        if (GetFileType(hFile) == FILE_TYPE_CHAR)
        {
            if (WriteConsoleW(hFile, buf.ptr, buf.length/2, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)hFile, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("C buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size * 2 .. $];
                return (size > 0);  // valid on only blocking read
            }
        }
        else
        {
            if (WriteFile(hFile, buf.ptr, buf.length, &size, null))
            {
                buf = buf[size .. $];
                return true;    // (size == buf.length);
            }
        }

        {
            throw new Exception("push error");  //?
        }
      }
    }

    bool flush()
    {
      version(Posix)
      {
        return false; //todo
      }
      version(Windows)
      {
        return FlushFileBuffers(hFile) != FALSE;
      }
    }

    /**
    */
    @property bool seekable()
    {
      version(Posix)
      {
        if (core.sys.posix.unistd.lseek(hFile, 0, SEEK_SET) == -1)
        {
            switch (errno)
            {
                case ESPIPE:
                    return false;
                default:
                    break;
            }
        }
        return true;
      }
      version(Windows)
      {
        return GetFileType(hFile) != FILE_TYPE_CHAR;
      }
    }

    /**
    */
    ulong seek(long offset, SeekPos whence)
    {
      version(Windows)
      {
        int hi = cast(int)(offset>>32);
        uint low = SetFilePointer(hFile, cast(int)offset, &hi, whence);
        if ((low == INVALID_SET_FILE_POINTER) && (GetLastError() != 0))
            throw new /*Seek*/Exception("unable to seek file pointer");
        ulong result = (cast(ulong)hi << 32) + low;
      }
      else version (Posix)
      {
        auto result = lseek(hFile, cast(int)offset, whence);
        if (result == cast(typeof(result))-1)
            throw new /*Seek*/Exception("unable to seek file pointer");
      }
      else
      {
        static assert(false, "not yet supported platform");
      }

        return cast(ulong)result;
    }
}
static assert(isSource!File);
static assert(isSink!File);

version(unittest)
{
    import std.algorithm;
}
unittest
{
    auto file = File(__FILE__);
    ubyte[] buf = new ubyte[64];
    ubyte[] b = buf;
    while (file.pull(b)) {}
    buf = buf[0 .. $-b.length];

    assert(buf.length == 64);
    debug std.stdio.writefln("buf = [%(%02x %)]\n", buf);
    assert(startsWith(buf, "module io.file;\n"));
}


/**
Wrapping array with $(I source) interface.
*/
struct ArraySource(E)
{
    const(E)[] array;

    @property auto handle() { return array; }

    bool pull(ref E[] buf)
    {
        if (array.length == 0)
            return false;
        if (buf.length <= array.length)
        {
            buf[] = array[0 .. buf.length];
            array = array[buf.length .. $];
            buf = buf[$ .. $];
        }
        else
        {
            buf[0 .. array.length] = array[];
            buf = buf[array.length .. $];
            array = array[$ .. $];
        }
        return true;
    }
}

unittest
{
    import io.port;

    auto r = ArraySource!char("10\r\ntest\r\n").buffered.ranged;
    long num;
    string str;
    readf(r, "%s\r\n", &num);
    readf(r, "%s\r\n", &str);
    assert(num == 10);
    assert(str == "test");
}
