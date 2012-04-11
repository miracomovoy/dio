module io.text;

import io.core;
import io.file;
import std.traits;
import std.range;

version(Windows)
{
    enum NativeNewLine = "\r\n";
    import core.sys.windows.windows, std.windows.syserror;
}
else version(Posix)
{
    enum NativeNewLine = "\n";
}
else
{
    static assert(0, "not yet supported");
}

/**
Lined receives pool of char, and makes input range of lines separated $(D delim).
Naming:
    LineReader?
    LineStream?
Examples:
----
foreach (line; File("foo.txt").lined!string("\n"))
{
    writeln(line);
}
----
*/
@property auto lined(String = string, Source)(Source source, size_t bufferSize=2048)
    if (isSource!Source)
{
    return .lined!String(source, cast(String)NativeNewLine, bufferSize);
}

/// ditto
auto lined(String = string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
    if (isSource!Source && isInputRange!Delim)
{
    static struct Lined(Dev, Delim, String : Char[], Char)
        if (isPool!Dev && isSomeChar!Char)
    {
    private:
        static assert(is(DeviceElementType!Dev == Unqual!Char));
        alias Unqual!Char MutableChar;

        import std.array : Appender;

        Dev device;
        Delim delim;
        Appender!(MutableChar[]) buffer;
        String line;
        bool eof;

    public:
        this(Dev dev, Delim delim)
        {
            this.device = dev;
            this.delim = delim;
            popFront();
        }

        @property bool empty() const
        {
            return eof;
        }
        @property String front() const
        {
            return line;
        }
        void popFront()
        in { assert(!empty); }
        body
        {
            const(MutableChar)[] view;
            const(MutableChar)[] nextline;

            bool fetchExact()   // fillAvailable?
            {
                view = device.available;
                while (view.length == 0)
                {
                    if (!device.fetch())
                        return false;
                    view = device.available;
                }
                return true;
            }
            if (!fetchExact())
            {
                eof = true;
                return;
            }

            buffer.clear();

            for (size_t vlen=0, dlen=0; ; )
            {
                if (vlen == view.length)
                {
                    buffer.put(view);
                    nextline = buffer.data;
                    device.consume(vlen);
                    if (!fetchExact())
                        break;

                    vlen = 0;
                    continue;
                }

                auto e = view[vlen];
                ++vlen;
                if (e == delim[dlen])
                {
                    ++dlen;
                    if (dlen == delim.length)
                    {
                        if (buffer.data.length)
                        {
                            buffer.put(view[0 .. vlen]);
                            nextline = (buffer.data[0 .. $ - dlen]);
                        }
                        else
                            nextline = view[0 .. vlen - dlen];

                        device.consume(vlen);
                        break;
                    }
                }
                else
                    dlen = 0;
            }

          static if (is(Char == immutable))
            line = nextline.idup;
          else
            line = nextline;
        }
    }

    alias Unqual!(ForeachType!String) Char;
    auto p = source.coerced!Char.buffered(bufferSize);

    return Lined!(typeof(p), Delim, String)(p, delim);
}

version(unittest)
{
    import io.file;
    import std.stdio : writeln, writefln;
}
unittest
{
    foreach (ln; File(__FILE__).lined!string){}

    string line;
    foreach (ln; File(__FILE__).lined!string("\n"))
    {
        line = ln;
        break;
    }
    assert(line == "module io.text;");
}

version(Windows)
{
    import sys.windows;

    static File _win_cstdin;
    static File _win_fstdin;
    static InputRange!dchar _win_cin;
    static InputRange!dchar _win_fin;

    static initializeStdIn()
    {
        _win_cin = new StdInRange!true();
        _win_fin = new StdInRange!false();

        HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
        if (GetFileType(hFile) == FILE_TYPE_CHAR)
        {
            _win_cstdin.attach(hFile);
            return _win_cin;
        }
        else
        {
            _win_fstdin.attach(hFile);
            return _win_fin;
        }
    }

    class StdInRange(bool console) : InputRange!dchar
    {
    private:
        static if (console)
        {
            enum RangedDevice = q{ (&_win_cstdin).coerced!wchar.sourced.buffered.ranged };
            alias Ranged!(Buffered!(Sourced!(Coerced!(wchar, File*)))) InputType;
            alias _win_cstdin file;
        }
        else
        {
            enum RangedDevice = q{ (&_win_fstdin).coerced!char.sourced.buffered.ranged };
            alias Ranged!(Buffered!(Sourced!(Coerced!( char, File*)))) InputType;
            alias _win_fstdin file;
        }

        InputType input;

        this()
        {
            input = mixin(RangedDevice);
        }

    public:
        bool empty()
        {
            if (!input.empty)
                return false;

            /*
            If cannot read any characters, check redirection.
            */
            bool nextEmpty()
            {
                HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
                if (hFile == file)
                    return true;    // continue

                if (console && GetFileType(hFile) != FILE_TYPE_CHAR)
                {   // switch console to non-console
                    assert(this is _win_cin);
                    _win_cstdin.detach();
                    _win_fstdin.attach(hFile);
                    .din = _win_fin;
                }
                else if (!console && GetFileType(hFile) == FILE_TYPE_CHAR)
                {   // switch non-console to console
                    assert(this is din);
                    _win_fstdin.detach();
                    _win_cstdin.attach(hFile);
                    .din = _win_cin;
                }
                else
                {
                    file.attach(hFile);
                }
                return .din.empty;
            }
            return nextEmpty();
        }

        @property dchar front()
        {
            return input.front;
        }

        dchar moveFront()
        {
            return .moveFront(input);
        }

        void popFront()
        {
            input.popFront();
        }

        int opApply(int delegate(dchar) dg)
        {
            for(; !input.empty; input.popFront())
            {
                if (auto r = dg(input.front))
                    return r;
            }
            return 0;
        }
        int opApply(int delegate(size_t, dchar) dg)
        {
            
            for(size_t i = 0; !input.empty; input.popFront())
            {
                if (auto r = dg(i++, input.front))
                    return r;
            }
            return 0;
        }
    }

    unittest
    {
        HANDLE hStdIn = GetStdHandle(STD_INPUT_HANDLE);
        assert(GetFileType(hStdIn) == FILE_TYPE_CHAR);
        auto str = "Ma Chérieあいうえお";

        // console input emulation
        DWORD nwritten;
        foreach (wchar wc; str~"\r\n")
        {
            INPUT_RECORD irec;
            irec.EventType = KEY_EVENT;
            irec.KeyEvent.wRepeatCount = 1;
            irec.KeyEvent.wVirtualKeyCode = 0;   // todo
            irec.KeyEvent.wVirtualScanCode = 0;  // todo
            irec.KeyEvent.UnicodeChar = wc;
            irec.KeyEvent.dwControlKeyState = 0; // todo

            irec.KeyEvent.bKeyDown = TRUE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);

            irec.KeyEvent.bKeyDown = FALSE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);
        }

        import io.wrapper;
        string s;
        readf("%s\r\n", &s);

        //writefln("s   = [%(%02X %)]\r\n", s);   // as Unicode code points
        //writefln("s   = [%(%02X %)]\r\n", cast(ubyte[])s);    // as UTF-8
        //writefln("str = [%(%02X %)]\r\n", cast(ubyte[])str);  // as UTF-8
        assert(s == str);
    }
}

//__gshared
//{
    // /**
    // Pre-defined devices for standard input, output, and error output.
    // */
    // SourceDevice!ubyte stdin;
      SinkDevice!ubyte stdout;  /// ditto
      SinkDevice!ubyte stderr;  /// ditto

    /**
    Pre-defined text range interface for standard input, output, and error output.
    */
     InputRange!dchar din;
    OutputRange!dchar dout;     /// ditto
    OutputRange!dchar derr;     /// ditto
//}
/*shared */static this()
{
    import util.typecons;

  version(Windows)
  {
  //stdin  = adaptTo!(SourceDevice!ubyte)(File(GetStdHandle(STD_INPUT_HANDLE )).sourced);
    stdout = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_OUTPUT_HANDLE)).sinked);
    stderr = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_ERROR_HANDLE )).sinked);

    din  = initializeStdIn();// inputRangeObject      (stdin   .buffered  .coerced!char.ranged);
    dout = outputRangeObject!dchar(stdout/*.buffered*/.coerced!char.ranged);
    derr = outputRangeObject!dchar(stderr/*.buffered*/.coerced!char.ranged);
  }
}
static ~this()
{
    derr.clear();
    dout.clear();
    din.clear();

    stderr.clear();
    stdout.clear();
    //stdin.clear();
}
