## Platform
- **OS**: Ubuntu 24.04 (Noble) — Linux container
- **.NET**: 10.0
- **C#**: 14

## Tools
- For C# symbol queries in a .NET solution (find references / definitions / implementations / call hierarchy), use the LSP tool (`roslyn-lsp` plugin is enabled).
- Grep is fine for non-C# code.

## Shell
- Default shell is **zsh**; **bash** is also available. Use the Bash tool for shell commands.
- `pwsh` 7 is installed if you need it, but prefer POSIX shells inside the container.

## git commit message
- must follow semantic versioning - no (scope) segment
- short description for a simple change
- no co-author

## MCP Servers

### Microsoft Docs (plugin: microsoft-docs)
- The `plugin:microsoft-docs:microsoft-learn` server provides access to Microsoft Learn documentation
- Use it only when looking up .NET, C#, Azure, PowerShell, or other Microsoft technology documentation

## C# Coding Standards
Always use latest available features of .NET and latest libraries/packages

### dotnet commands
- Run `export MSBUILDUSESERVER=1` (or prepend `MSBUILDUSESERVER=1`) before `dotnet build` / `dotnet restore` / `dotnet test`.
- Run `dotnet restore` once before the first build (or after package changes / fresh clone).
- Build C# project or solution with `dotnet build -p:WarningLevel=0 -v:q --no-restore`.
- Test projects use `xunit.v3.mtp-v2` (MTP, `OutputType=Exe`) without `UseMicrosoftTestingPlatformRunner`. Run tests with `dotnet run --project X.Tests.csproj -- <xunit args>` — xUnit v3's native CLI (e.g. `-method "*Foo"`, `-class`, `-trait`, `-diagnostics`) rather than `dotnet test` filter syntax.

### General Style
- Prefer `var`
- File-scoped namespaces
- Always use braces on a new line for `if` / `for` / `foreach` / `while` — never single-line bodies, even for one statement.

### Performance-Critical Code
- **Hot paths must be allocation-free**
- Use `Span<T>` and `ReadOnlySpan<T>`
- Prefer `stackalloc` for small fixed-size buffers
- JSON library should be always System.Text.Json unless stated otherwise
