#!/usr/bin/env zsh

# Project Context Generator - Simplified Version
# Usage: ./project_context.sh [OPTIONS]
# Generates a comprehensive project overview for current directory only

set -e

# Configuration
EXPORT_TO_FILE=false
EXPORT_TO_CLIPBOARD=false

# File extensions to ignore (binary/large files)
IGNORE_EXTENSIONS=("lock" "log" "tmp" "cache" "bin" "exe" "dll" "so" "dylib" "a" "o" "pyc" "class" "jar" "war" "ear" "zip" "tar" "gz" "rar" "7z" "pdf" "doc" "docx" "xls" "xlsx" "ppt" "pptx" "img" "jpg" "jpeg" "png" "gif" "bmp" "svg" "ico" "mp3" "mp4" "avi" "mov" "wmv" "flv" "mkv" "webm" "woff" "woff2" "ttf" "otf" "eot")

# Large auto-generated files and directories to ignore
IGNORE_PATTERNS=("node_modules" "vendor" "dist" "build" ".git" "__pycache__" ".DS_Store" "Thumbs.db" "package-lock.json" "yarn.lock" "composer.lock" "Pipfile.lock" "Gemfile.lock" ".next" ".nuxt" "coverage" ".nyc_output" ".pytest_cache" ".vscode" ".idea")

# Maximum file size (1MB)
MAX_FILE_SIZE=1048576

# Function to check if file should be ignored based on gitignore
is_gitignored() {
    local file="$1"
    if [[ -f ".gitignore" ]]; then
        # Use git check-ignore if in a git repo
        if git rev-parse --git-dir > /dev/null 2>&1; then
            git check-ignore "$file" > /dev/null 2>&1 && return 0
        else
            # Fallback: simple pattern matching against .gitignore
            while IFS= read -r pattern; do
                # Skip empty lines and comments
                [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
                # Remove leading/trailing whitespace
                pattern=$(echo "$pattern" | xargs)
                # Simple glob matching
                if [[ "$file" == $pattern || "$file" == *"$pattern"* ]]; then
                    return 0
                fi
            done < .gitignore
        fi
    fi
    return 1
}

# Function to check if file extension should be ignored
has_ignored_extension() {
    local file="$1"
    local ext="${file##*.}"
    # Convert to lowercase for comparison
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    for ignore_ext in "${IGNORE_EXTENSIONS[@]}"; do
        [[ "$ext" == "$ignore_ext" ]] && return 0
    done
    return 1
}

# Function to check if path contains ignored patterns
contains_ignored_pattern() {
    local path="$1"
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        [[ "$path" == *"$pattern"* ]] && return 0
    done
    return 1
}

# Function to check if file is text
is_text_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    
    # Check if file command is available
    if command -v file > /dev/null; then
        file -b --mime-type "$file" 2>/dev/null | grep -q "^text/" && return 0
    fi
    
    # Fallback: check for common text file extensions
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        txt|md|json|yaml|yml|xml|html|htm|css|js|ts|jsx|tsx|py|rb|php|java|c|cpp|h|hpp|cs|go|rs|sh|bash|zsh|fish|sql|r|scala|kt|swift|m|pl|lua|vim|conf|cfg|ini|toml|gradle|make|makefile|dockerfile|license|readme|gitignore|gitattributes|editorconfig|eslintrc|prettierrc|babelrc|npmrc|yarnrc)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get file size (cross-platform)
get_file_size() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f%z "$file" 2>/dev/null || echo 0
    else
        stat -c%s "$file" 2>/dev/null || echo 0
    fi
}

# Function to copy content to clipboard (cross-platform)
copy_to_clipboard() {
    local content="$1"
    
    if command -v pbcopy > /dev/null; then
        # macOS
        echo "$content" | pbcopy
        return $?
    elif command -v xclip > /dev/null; then
        # Linux with xclip
        echo "$content" | xclip -selection clipboard
        return $?
    elif command -v xsel > /dev/null; then
        # Linux with xsel
        echo "$content" | xsel --clipboard --input
        return $?
    elif command -v wl-copy > /dev/null; then
        # Wayland
        echo "$content" | wl-copy
        return $?
    else
        echo "❌ Error: No clipboard utility found (pbcopy, xclip, xsel, or wl-copy)" >&2
        return 1
    fi
}

# Function to generate filtered file list
get_filtered_files() {
    local dir="$1"
    local debug_mode="${2:-false}"
    
    find "$dir" -type f -not -path "*/.*" 2>/dev/null | while read -r file; do
        # Skip empty lines
        [[ -z "$file" ]] && continue
        
        # Skip if file doesn't exist (broken symlinks)
        [[ -f "$file" ]] || continue
        
        # Skip if gitignored
        if is_gitignored "$file"; then
            [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Skipped (gitignored): $file" >&2
            continue
        fi
        
        # Skip if has ignored extension
        if has_ignored_extension "$file"; then
            [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Skipped (extension): $file" >&2
            continue
        fi
        
        # Skip if contains ignored patterns
        if contains_ignored_pattern "$file"; then
            [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Skipped (pattern): $file" >&2
            continue
        fi
        
        # Skip if file is too large
        local file_size=$(get_file_size "$file")
        if [[ $file_size -gt $MAX_FILE_SIZE ]]; then
            [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Skipped (too large $file_size bytes): $file" >&2
            continue
        fi
        
        # Skip if not a text file
        if ! is_text_file "$file"; then
            [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Skipped (not text): $file" >&2
            continue
        fi
        
        [[ "$debug_mode" == "true" ]] && echo "# DEBUG: Including: $file" >&2
        echo "$file"
    done
}

# Function to generate project tree structure
generate_tree_structure() {
    local dir="$1"
    
    if command -v tree > /dev/null; then
        # Use tree command with ignore patterns
        local ignore_list=$(IFS='|'; echo "${IGNORE_PATTERNS[*]}")
        tree -a -I "$ignore_list" "$dir" 2>/dev/null
    else
        # Fallback: custom tree implementation
        generate_custom_tree "$dir" "" "│   "
    fi
}

# Custom tree implementation (fallback)
generate_custom_tree() {
    local dir="$1"
    local prefix="$2"
    local connector="$3"
    
    local files=()
    local dirs=()
    
    # Separate files and directories
    for item in "$dir"/*; do
        [[ -e "$item" ]] || continue
        local basename_item=$(basename "$item")
        
        # Skip if matches ignored patterns
        contains_ignored_pattern "$item" && continue
        
        if [[ -d "$item" ]]; then
            dirs+=("$item")
        else
            files+=("$item")
        fi
    done
    
    # Sort arrays
    dirs=($(printf '%s\n' "${dirs[@]}" | sort))
    files=($(printf '%s\n' "${files[@]}" | sort))
    
    # Print directories first
    local total_items=$((${#dirs[@]} + ${#files[@]}))
    local current_item=0
    
    for dir_item in "${dirs[@]}"; do
        current_item=$((current_item + 1))
        local basename_item=$(basename "$dir_item")
        
        if [[ $current_item -eq $total_items ]]; then
            echo "${prefix}└── ${basename_item}/"
            generate_custom_tree "$dir_item" "${prefix}    " "    "
        else
            echo "${prefix}├── ${basename_item}/"
            generate_custom_tree "$dir_item" "${prefix}│   " "│   "
        fi
    done
    
    # Print files
    for file_item in "${files[@]}"; do
        current_item=$((current_item + 1))
        local basename_item=$(basename "$file_item")
        
        if [[ $current_item -eq $total_items ]]; then
            echo "${prefix}└── ${basename_item}"
        else
            echo "${prefix}├── ${basename_item}"
        fi
    done
}

# Function to safely read file content
read_file_content() {
    local file="$1"
    
    # Check if file is readable
    if [[ ! -r "$file" ]]; then
        echo "# [Error: File not readable]"
        return
    fi
    
    # Try to read the file
    if ! cat "$file" 2>/dev/null; then
        echo "# [Error: Could not read file content]"
    fi
}

# Main function to generate context
generate_context() {
    local current_dir=$(pwd)
    local dir_name=$(basename "$current_dir")
    
    echo "Generating project context for: $current_dir"
    
    if [[ "$EXPORT_TO_FILE" == true && "$EXPORT_TO_CLIPBOARD" == true ]]; then
        echo "Output: File ($OUTPUT_FILE) + Clipboard"
    elif [[ "$EXPORT_TO_FILE" == true ]]; then
        echo "Output: File ($OUTPUT_FILE)"
    elif [[ "$EXPORT_TO_CLIPBOARD" == true ]]; then
        echo "Output: Clipboard only"
    fi
    echo
    
    # Count files to process
    echo "Scanning for files to include..."
    local temp_file_list=$(mktemp)
    get_filtered_files "." > "$temp_file_list"
    local total_files=$(wc -l < "$temp_file_list")
    
    echo "Found $total_files files to process"
    
    if [[ $total_files -gt 500 ]]; then
        echo "Warning: This will process $total_files files. This might take a while."
        echo "Press Ctrl+C within 5 seconds to cancel..."
        sleep 5
    fi
    
    # Generate the content
    local content=""
    content+="# Project Context: $dir_name"$'\n'
    content+="Generated on: $(date)"$'\n'
    content+="Directory: $current_dir"$'\n'
    content+=""$'\n'
    
    # 1. Project structure tree
    content+="## Project Structure"$'\n'
    content+='```'$'\n'
    content+="$(generate_tree_structure ".")"$'\n'
    content+='```'$'\n'
    content+=""$'\n'
    
    # 2. & 3. File contents
    content+="## File Contents"$'\n'
    content+=""$'\n'
    
    # Use the already created file list
    sort "$temp_file_list" > "${temp_file_list}.sorted"
    mv "${temp_file_list}.sorted" "$temp_file_list"
    
    local file_count=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Safety check: limit number of files
        if [[ $file_count -gt 10000 ]]; then
            content+="### [Warning: Limiting output to first 10,000 files]"$'\n'
            content+=""$'\n'
            break
        fi
        
        content+="### $file"$'\n'
        content+=""$'\n'
        content+='```'$'\n'
        content+="$(read_file_content "$file")"$'\n'
        content+='```'$'\n'
        content+=""$'\n'
    done < "$temp_file_list"
    
    # Output to file and/or clipboard
    if [[ "$EXPORT_TO_CLIPBOARD" == true ]]; then
        if copy_to_clipboard "$content"; then
            echo "✓ Context copied to clipboard successfully!"
        else
            echo "❌ Failed to copy to clipboard"
        fi
    fi
    
    if [[ "$EXPORT_TO_FILE" == true ]]; then
        echo "$content" > "$OUTPUT_FILE"
    fi
    
    # Clean up temp files
    rm -f "$temp_file_list"
    
    # Show completion message
    echo "✓ Context generated successfully"
    echo "✓ Processed $total_files files"
    
    if [[ "$EXPORT_TO_FILE" == true ]]; then
        local output_size=$(get_file_size "$OUTPUT_FILE")
        echo "✓ File: $OUTPUT_FILE ($((output_size / 1024))KB)"
        
        # Safety check for large files
        if [[ $output_size -gt 10485760 ]]; then  # 10MB
            echo "⚠️  Warning: Output file is larger than 10MB ($((output_size / 1024 / 1024))MB)"
        fi
    fi
    
    if [[ "$EXPORT_TO_CLIPBOARD" == true ]]; then
        local content_size=${#content}
        echo "✓ Clipboard: $((content_size / 1024))KB"
    fi
}

# Show usage information
show_usage() {
    local script_name=$(basename "$0")
    echo "Project Context Generator"
    echo ""
    echo "Usage: $script_name [OPTIONS]"
    echo ""
    echo "Generates project context for the current directory only."
    echo "Output filename: {current-directory-name}-project_context.txt"
    echo ""
    echo "Options:"
    echo "  -f           Export to file only"
    echo "  -c           Export to clipboard only" 
    echo "  -fc, -cf     Export to both file and clipboard"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $script_name         # Export to file (default)"
    echo "  $script_name -f      # Export to file only"
    echo "  $script_name -c      # Export to clipboard only"
    echo "  $script_name -fc     # Export to both file and clipboard"
    echo ""
    echo "Features:"
    echo "  • Respects .gitignore rules"
    echo "  • Filters out binary files and large files"
    echo "  • Generates comprehensive project overview"
    echo "  • Includes directory structure and file contents"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f)
            EXPORT_TO_FILE=true
            shift
            ;;
        -c)
            EXPORT_TO_CLIPBOARD=true
            shift
            ;;
        -fc|-cf)
            EXPORT_TO_FILE=true
            EXPORT_TO_CLIPBOARD=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
        *)
            echo "No positional arguments allowed. Use -f, -c, or -fc/-cf flags." >&2
            show_usage
            exit 1
            ;;
    esac
done

# Default behavior if no flags specified
if [[ "$EXPORT_TO_FILE" == false && "$EXPORT_TO_CLIPBOARD" == false ]]; then
    EXPORT_TO_FILE=true
fi

# Generate output filename based on current directory
OUTPUT_FILE="$(basename "$(pwd)")-project_context.txt"

# Run the main function
generate_context