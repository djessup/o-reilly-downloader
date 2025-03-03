#!/bin/bash
# O'Reilly book downloader script
# Downloads books in PDF and/or EPUB format using Docker
# Supports both username/password and SSO login
# Supports batch downloading multiple books

# Exit on error, undefined variables, and propagate pipe errors
set -euo pipefail

# Default values
CURDIR=$(pwd)
CONFIG_FILE="${CURDIR}/data/user.conf"
OUTPUT_PDF="${CURDIR}/download/pdf"
OUTPUT_EPUB="${CURDIR}/download/epub"
OUTPUT_TEMP="${CURDIR}/download/tmp"
BOOKTITLE=""
TITLE=""
FORMAT=""
LOGIN_METHOD="user"  # Default to username/password login
COOKIE_FILE=""       # For SSO login
BATCH_FILE=""        # For batch downloads
print_pdf=false
print_epub=false
BATCH_MODE=false

# Function to display usage information
usage() {
    echo "Usage: $0 [-b <book_title> -t <output_filename>] [-l <batch_file>] -f <format> [-m <login_method>] [-c <cookie_file>]"
    echo "Options:"
    echo "  -b <book_title>      The O'Reilly book title or link to search for"
    echo "  -t <output_filename> Output filename (without extension)"
    echo "  -l <batch_file>      File containing list of books to download (one per line: ID,Title)"
    echo "  -f <format>          Format to download: pdf, epub, or both"
    echo "  -m <login_method>    Login method: user (default) or sso"
    echo "  -c <cookie_file>     JSON file with cookies for SSO login (required with -m sso)"
    echo "  -h                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  Single book download with username/password:"
    echo "    $0 -b 9780321635754 -t \"Art of Computer Programming\" -f pdf"
    echo ""
    echo "  Single book download with SSO:"
    echo "    $0 -b 9780321635754 -t \"Art of Computer Programming\" -f pdf -m sso -c cookies.json"
    echo ""
    echo "  Batch download multiple books:"
    echo "    $0 -l books.txt -f pdf -m sso -c cookies.json"
    echo ""
    echo "Batch file format (books.txt):"
    echo "  9780321635754,Art of Computer Programming"
    echo "  9781788298025,Mastering Kubernetes"
    echo "  <book_id_or_title>,<output_filename>"
    exit 1
}

# Function to clean up resources
cleanup() {
    # Create a sanitized container name
    CONTAINER_NAME=$(echo "$TITLE" | tr -c '[:alnum:]_.-' '_')
    
    if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
        echo "Cleaning up Docker container..."
        docker container rm -f "$CONTAINER_NAME" || echo "Warning: Failed to remove Docker container"
    fi
    
    if docker container inspect "calibre-converter" &>/dev/null; then
        echo "Cleaning up conversion container..."
        docker container rm -f "calibre-converter" || echo "Warning: Failed to remove conversion container"
    fi
    
    # Remove temporary files
    if [[ -f "${CURDIR}/${TITLE}.epub" ]]; then
        rm -f "${CURDIR}/${TITLE}.epub"
    fi
}

# Function to download and convert a single book
download_book() {
    local book_id="$1"
    local book_title="$2"
    local format="$3"
    
    echo "========================================================="
    echo "Downloading book: $book_id"
    echo "Output title: $book_title"
    echo "Format: $format"
    echo "========================================================="
    
    # Set format flags for this book
    local print_pdf_book=false
    local print_epub_book=false
    
    case "$format" in
        pdf)
            print_pdf_book=true
            ;;
        epub)
            print_epub_book=true
            ;;
        both)
            print_pdf_book=true
            print_epub_book=true
            ;;
    esac
    
    # Prepare a sanitized container name for Docker
    local container_name=$(echo "$book_title" | tr -c '[:alnum:]_.-' '_')
    
    # Temporary epub file
    local temp_epub="${OUTPUT_TEMP}/${book_title}.epub"
    
    # Download book based on login method
    if [[ "$LOGIN_METHOD" == "user" ]]; then
        echo "Starting download with username/password authentication..."
        (docker run --name "$container_name" kirinnee/orly:latest login "$book_id" "$username":"$password") > "$temp_epub" &
        download_pid=$!
        echo -n "Downloading"
        spinner $download_pid
        wait $download_pid || true
        if [[ ! -s "$temp_epub" ]]; then
            echo "Error: Download failed or resulted in empty file for '$book_id'"
            return 1
        fi
        echo "Download completed successfully!"
    else
        # SSO login
        echo "Starting download with SSO authentication..."
        (cat "$COOKIE_FILE" | docker run --name "$container_name" -i kirinnee/orly:latest sso "$book_id") > "$temp_epub" &
        download_pid=$!
        echo -n "Downloading"
        spinner $download_pid
        wait $download_pid || true
        if [[ ! -s "$temp_epub" ]]; then
            echo "Error: Download failed or resulted in empty file for '$book_id'"
            return 1
        fi
        echo "Download completed successfully!"
    fi
    
    # Clean up container
    if docker container inspect "$container_name" &>/dev/null; then
        docker container rm -f "$container_name" > /dev/null
    fi
    
    # Handle PDF conversion if requested
    if [[ "$print_pdf_book" = true ]]; then
        echo "Converting to PDF format..."
        
        # Check if the EPUB file exists and has content
        if [[ ! -s "$temp_epub" ]]; then
            echo "Error: EPUB file is empty or doesn't exist. Cannot convert to PDF."
            return 1
        fi
        
        # Check for macOS Calibre installation
        MAC_CALIBRE="/Applications/calibre.app/Contents/MacOS/ebook-convert"
        
        if [[ "$(uname)" == "Darwin" && -x "$MAC_CALIBRE" ]]; then
            # Use local macOS Calibre for conversion
            echo "Using local Calibre installation for conversion..."
            
            if ! "$MAC_CALIBRE" "$temp_epub" "${OUTPUT_TEMP}/${book_title}.pdf" \
                --pdf-page-numbers \
                --pretty-print; then
                
                echo "Error: Failed to convert EPUB to PDF using local Calibre"
                echo "Keeping EPUB file instead."
                print_epub_book=true
                mkdir -p "${OUTPUT_PDF}"
                echo "PDF conversion failed - please use the EPUB version" > "${OUTPUT_PDF}/${book_title}.txt"
                echo "EPUB file location: ${OUTPUT_EPUB}/${book_title}.epub" >> "${OUTPUT_PDF}/${book_title}.txt"
            else
                # Check if conversion was successful
                if [[ -f "${OUTPUT_TEMP}/${book_title}.pdf" ]]; then
                    # Move the converted PDF to the output directory
                    mv "${OUTPUT_TEMP}/${book_title}.pdf" "${OUTPUT_PDF}/${book_title}.pdf"
                    echo "PDF saved to: ${OUTPUT_PDF}/${book_title}.pdf"
                else
                    echo "Error: PDF file was not created. Using EPUB instead."
                    print_epub_book=true
                    mkdir -p "${OUTPUT_PDF}"
                    echo "PDF conversion failed - please use the EPUB version" > "${OUTPUT_PDF}/${book_title}.txt"
                    echo "EPUB file location: ${OUTPUT_EPUB}/${book_title}.epub" >> "${OUTPUT_PDF}/${book_title}.txt"
                fi
            fi
        else
            # Fall back to Docker-based conversion if not on macOS or Calibre not installed
            echo "Local Calibre not found, using Docker for conversion..."
            
            # Pull the rappdw/ebook-convert Docker image if needed
            if ! docker image inspect rappdw/ebook-convert:latest &>/dev/null; then
                echo "Pulling ebook-convert Docker image..."
                docker pull rappdw/ebook-convert:latest
            fi
            
            echo "Running conversion with rappdw/ebook-convert..."
            
            # Use rappdw/ebook-convert to convert EPUB to PDF
            if ! docker run --rm \
                --name calibre-converter \
                -v "${OUTPUT_TEMP}:/data" \
                rappdw/ebook-convert:latest \
                ebook-convert "/data/$(basename "$temp_epub")" "/data/${book_title}.pdf" \
                --pdf-page-numbers \
                --pretty-print; then
                
                echo "Error: Failed to convert EPUB to PDF using Docker"
                echo "Keeping EPUB file instead."
                print_epub_book=true
                mkdir -p "${OUTPUT_PDF}"
                echo "PDF conversion failed - please use the EPUB version" > "${OUTPUT_PDF}/${book_title}.txt"
                echo "EPUB file location: ${OUTPUT_EPUB}/${book_title}.epub" >> "${OUTPUT_PDF}/${book_title}.txt"
            else
                # Check if conversion was successful
                if [[ -f "${OUTPUT_TEMP}/${book_title}.pdf" ]]; then
                    # Move the converted PDF to the output directory
                    mv "${OUTPUT_TEMP}/${book_title}.pdf" "${OUTPUT_PDF}/${book_title}.pdf"
                    echo "PDF saved to: ${OUTPUT_PDF}/${book_title}.pdf"
                else
                    echo "Error: PDF file was not created. Using EPUB instead."
                    print_epub_book=true
                    mkdir -p "${OUTPUT_PDF}"
                    echo "PDF conversion failed - please use the EPUB version" > "${OUTPUT_PDF}/${book_title}.txt"
                    echo "EPUB file location: ${OUTPUT_EPUB}/${book_title}.epub" >> "${OUTPUT_PDF}/${book_title}.txt"
                fi
            fi
        fi
    fi
    
    # Handle EPUB if requested
    if [[ "$print_epub_book" = true ]]; then
        mv "$temp_epub" "${OUTPUT_EPUB}/${book_title}.epub"
        echo "EPUB saved to: ${OUTPUT_EPUB}/${book_title}.epub"
    else
        # If EPUB not requested, remove the temporary file
        rm -f "$temp_epub"
    fi
    
    echo "✓ Book '$book_id' downloaded successfully as '$book_title'!"
    return 0
}

# Function to check Docker platform
check_docker_platform() {
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if running on ARM architecture
    if [[ "$(uname -m)" == "arm64" || "$(uname -m)" == "aarch64" ]]; then
        echo "Notice: Running on ARM architecture. Some Docker images may use emulation."
        echo "This is normal and will work, but might be slower than native images."
    fi
}

# Spinner function for visual feedback during download
spinner() {
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Set up trap for cleanup on script exit, interruption or error
trap cleanup EXIT INT TERM

# Parse command-line arguments
while getopts "b:t:f:m:c:l:h" option; do
    case "${option}" in
        b) BOOKTITLE="${OPTARG}" ;;
        t) TITLE="${OPTARG}" ;;
        f) FORMAT="${OPTARG}" ;;
        m) LOGIN_METHOD="${OPTARG}" ;;
        c) COOKIE_FILE="${OPTARG}" ;;
        l) BATCH_FILE="${OPTARG}"; BATCH_MODE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [[ -z "$FORMAT" ]]; then
    echo "Error: Missing required format (-f) argument"
    usage
fi

if [[ "$BATCH_MODE" = false && (-z "$BOOKTITLE" || -z "$TITLE") ]]; then
    echo "Error: In single book mode, both book title (-b) and output filename (-t) are required"
    usage
fi

if [[ "$BATCH_MODE" = true && -z "$BATCH_FILE" ]]; then
    echo "Error: Batch file (-l) is required in batch mode"
    usage
fi

if [[ "$BATCH_MODE" = true && (! -z "$BOOKTITLE" || ! -z "$TITLE") ]]; then
    echo "Warning: Book title (-b) and output filename (-t) are ignored in batch mode"
fi

# Validate login method
if [[ "$LOGIN_METHOD" != "user" && "$LOGIN_METHOD" != "sso" ]]; then
    echo "Error: Invalid login method '$LOGIN_METHOD'. Must be 'user' or 'sso'"
    usage
fi

# Validate SSO login requirements
if [[ "$LOGIN_METHOD" == "sso" && -z "$COOKIE_FILE" ]]; then
    echo "Error: SSO login requires a cookie file specified with -c"
    usage
fi

if [[ "$LOGIN_METHOD" == "sso" && ! -f "$COOKIE_FILE" ]]; then
    echo "Error: Cookie file '$COOKIE_FILE' not found"
    exit 1
fi

# Validate batch file if in batch mode
if [[ "$BATCH_MODE" = true && ! -f "$BATCH_FILE" ]]; then
    echo "Error: Batch file '$BATCH_FILE' not found"
    exit 1
fi

# Set format flags
case "$FORMAT" in
    pdf)
        echo "Selected PDF format"
        print_pdf=true
        ;;
    epub)
        echo "Selected EPUB format"
        print_epub=true
        ;;
    both)
        echo "Selected both PDF and EPUB formats"
        print_pdf=true
        print_epub=true
        ;;
    *)
        echo "Error: Invalid format '$FORMAT'. Must be 'pdf', 'epub', or 'both'"
        usage
        ;;
esac

# Create output directories if they don't exist
mkdir -p "$OUTPUT_PDF" "$OUTPUT_EPUB" "$OUTPUT_TEMP"

# Call the platform check function early in the script
check_docker_platform

# Read credentials if using username/password login
if [[ "$LOGIN_METHOD" == "user" ]]; then
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found at $CONFIG_FILE"
        echo "Please create a file at this location with your O'Reilly credentials"
        echo "Format: first line username, second line password"
        exit 1
    fi

    # Read credentials more safely
    if [[ $(wc -l < "$CONFIG_FILE") -ne 2 ]]; then
        echo "Error: Configuration file should contain exactly 2 lines (username and password)"
        exit 1
    fi

    username=$(sed -n '1p' "$CONFIG_FILE")
    password=$(sed -n '2p' "$CONFIG_FILE")

    if [[ -z "$username" || -z "$password" ]]; then
        echo "Error: Username or password cannot be empty in $CONFIG_FILE"
        exit 1
    fi
fi

# Process batch file if in batch mode
if [[ "$BATCH_MODE" = true ]]; then
    echo "Running in batch mode with file: $BATCH_FILE"
    echo "Selected format: $FORMAT"
    echo "Login method: $LOGIN_METHOD"
    
    # Track statistics
    success_count=0
    failure_count=0
    total_books=$(grep -c -v "^#" "$BATCH_FILE" || true)
    
    echo "Found $total_books books to download"
    
    # Process each line in the batch file
    while IFS=, read -r book_id book_title || [[ -n "$book_id" ]]; do
        # Skip empty lines and comments
        if [[ -z "$book_id" || "$book_id" == \#* ]]; then
            continue
        fi
        
        # Trim whitespace
        book_id=$(echo "$book_id" | xargs)
        book_title=$(echo "$book_title" | xargs)
        
        # If no title provided, use book_id as title
        if [[ -z "$book_title" ]]; then
            book_title="$book_id"
        fi
        
        # Download the book
        if download_book "$book_id" "$book_title" "$FORMAT"; then
            ((success_count++))
        else
            ((failure_count++))
            echo "Failed to download book: $book_id"
        fi
        
        echo "Progress: $((success_count + failure_count))/$total_books completed"
        echo "-------------------------------------------------------------"
        
    done < "$BATCH_FILE"
    
    echo "Batch download complete!"
    echo "Successfully downloaded: $success_count"
    echo "Failed: $failure_count"
    echo "Total: $total_books"
    
else
    # Single book mode
    download_book "$BOOKTITLE" "$TITLE" "$FORMAT"
fi

echo "All operations completed!"