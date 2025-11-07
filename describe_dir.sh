#!/bin/sh
# Describe and print the total content of a directory into a text report.
# - Prints full tree (unfiltered)
# - Skips files ignored by .gitignore
# - Skips printing this script itself and the output report file
# - Includes hidden ".env.sample" files
# - Avoids infinite loops by not recursing into symlinked directories

ROOT="$(pwd)"
GITIGNORE_PATH="$ROOT/.gitignore"
SCRIPT_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
OUTPUT_FILE="$ROOT/directory_report.txt"

# Start fresh
echo "Generating directory report..."
echo "Output: $OUTPUT_FILE"
echo "===== Directory Report =====" > "$OUTPUT_FILE"
echo "Root: $ROOT" >> "$OUTPUT_FILE"
echo >> "$OUTPUT_FILE"

# ----- Tree output -----
if command -v tree >/dev/null 2>&1; then
    echo "Recording directory tree..."
    {
        echo "===== Directory Tree ====="
        tree
        echo
    } >> "$OUTPUT_FILE"
else
    echo "Recording fallback tree listing..."
    {
        echo "Command 'tree' not found. Using fallback listing:"
        find . -print | sed 's|[^/]*/|--|g'
        echo
    } >> "$OUTPUT_FILE"
fi

# ----- Helpers -----
is_gitignored() {
    if [ -f "$GITIGNORE_PATH" ] && command -v git >/dev/null 2>&1; then
        git -C "$ROOT" check-ignore -q "$1"
        return $?
    fi
    return 1
}

append_file_content() {
    file="$1"

    # Skip self and the output file to prevent self-appending loop
    [ "$file" = "$SCRIPT_PATH" ] && return 0
    [ "$file" = "$OUTPUT_FILE" ] && return 0

    # Respect .gitignore (do not override)
    if is_gitignored "$file"; then
        return 0
    fi

    echo "Recording: $file"
    {
        echo "===== Document: $file ====="
        echo
        cat "$file" 2>/dev/null || echo "[Error reading file]"
        echo
        echo "---------------------------"
        echo
    } >> "$OUTPUT_FILE"
}

print_contents() {
    dir="$1"

    # Include hidden .env.sample explicitly (without enabling dot-globs)
    if [ -f "$dir/.env.sample" ]; then
        append_file_content "$dir/.env.sample"
    fi

    # Guard for empty directories
    set -- "$dir"/*
    [ -e "$1" ] || return 0

    for item in "$dir"/*; do
        [ -e "$item" ] || continue

        # Do not recurse into symlinked directories to avoid cycles
        if [ -d "$item" ]; then
            if [ -L "$item" ]; then
                # Skip symlinked directories
                continue
            fi
            print_contents "$item"
        elif [ -f "$item" ]; then
            append_file_content "$item"
        fi
    done
}

echo "Recording file contents..."
{
    echo "===== File Contents ====="
    echo
} >> "$OUTPUT_FILE"

print_contents "$ROOT"

echo "Done!"
echo "Full report written to: $OUTPUT_FILE"
