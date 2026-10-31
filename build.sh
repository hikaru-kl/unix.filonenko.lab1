
#!/bin/sh

# POSIX Shell build script.
# Exit codes:
# 0 - success
# 2 - invalid arguments
# 3 - source file not found
# 4 - Output: marker missing or invalid
# 5 - unsupported source extension
# 6 - required compiler not found
# 7 - compilation failed
# 8 - output installation failed

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 source-file" >&2
    exit 2
fi

src=$1

if [ ! -f "$src" ] || [ ! -r "$src" ]; then
    echo "Error: source file does not exist or is unreadable: $src" >&2
    exit 3
fi

src_dir=$(dirname "$src") || exit 3
src_base=$(basename "$src") || exit 3

src_dir=$(CDPATH= cd "$src_dir" && pwd) || exit 3
src="$src_dir/$src_base"

# Extract the first token after Output:.
output_name=$(
    awk '
    {
        pos = index($0, "Output:")
        if (pos > 0) {
            s = substr($0, pos + 7)
            sub(/\r$/, "", s)
            sub(/[[:space:]]*\*\/.*/, "", s)
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]].*$/, "", s)
            if (s != "") {
                print s
                exit
            }
        }
    }' "$src"
) || exit 4

case "$output_name" in
    ""|.*|*/*|*\\*|*[!A-Za-z0-9._-]*)
        echo "Error: missing or invalid Output: filename" >&2
        exit 4
        ;;
esac

if [ "$output_name" = "$src_base" ]; then
    echo "Error: output must not overwrite the source file" >&2
    exit 4
fi

case "$src_base" in
    *.c)
        compiler=cc
        ;;
    *.cc|*.cpp|*.cxx|*.C)
        compiler=c++
        ;;
    *.tex)
        compiler=pdflatex
        ;;
    *)
        echo "Error: unsupported source extension: $src_base" >&2
        exit 5
        ;;
esac

if ! command -v "$compiler" >/dev/null 2>&1; then
    echo "Error: required compiler not found: $compiler" >&2
    exit 6
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/unix-build.XXXXXX") || {
    echo "Error: cannot create temporary directory" >&2
    exit 8
}

# Remove the temporary directory on normal exit.
trap 'rm -rf "$tmp"' 0

# Handle catchable termination signals.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$src_base" in
    *.c)
        if ! "$compiler" "$src" -o "$tmp/result"; then
            echo "Error: C compilation failed" >&2
            exit 7
        fi
        ;;
    *.cc|*.cpp|*.cxx|*.C)
        if ! "$compiler" "$src" -o "$tmp/result"; then
            echo "Error: C++ compilation failed" >&2
            exit 7
        fi
        ;;
    *.tex)
        if ! (
            cd "$src_dir" &&
            "$compiler" \
                -interaction=nonstopmode \
                -halt-on-error \
                -jobname=result \
                -output-directory="$tmp" \
                "$src_base"
        ); then
            echo "Error: TeX compilation failed" >&2
            exit 7
        fi

        if [ ! -f "$tmp/result.pdf" ]; then
            echo "Error: compiler did not produce a PDF" >&2
            exit 7
        fi
        ;;
esac

# Install the result next to the source file.
if ! mv "$tmp/result" "$src_dir/$output_name" 2>/dev/null; then
    if ! mv "$tmp/result.pdf" "$src_dir/$output_name" 2>/dev/null; then
        echo "Error: cannot install output file" >&2
        exit 8
    fi
fi

echo "Build successful: $src_dir/$output_name"
exit 0

