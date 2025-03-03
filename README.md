# O'Reilly Book Downloader

A powerful bash script to download books from the O'Reilly Learning Platform in PDF and/or EPUB format.

## Features

- Download books in PDF and/or EPUB format
- Support for both username/password and SSO login methods
- Batch downloading capability for multiple books
- EPUB to PDF conversion using:
  - Local Calibre installation on macOS (if available)
  - Docker-based conversion as fallback
- Progress indicators and detailed output

## Prerequisites

- **Docker**: Required for downloading books from O'Reilly
- **Bash shell**: To run the script
- **O'Reilly subscription**: Either personal account or organizational SSO access
- **Calibre** *(optional)*: For local PDF conversion on macOS

## Installation

1. Clone or download this repository
2. Make the script executable:

   ```bash
   chmod +x oreilly-downloader.sh
   ```

3. Set up authentication (see below)

## Authentication Setup

### Method 1: Username/Password Authentication

1. Create `data` directory:

   ```bash
   mkdir -p data
   ```

2. Create a configuration file with your O'Reilly credentials:

   ```bash
   cp user.conf.sample data/user.conf
   ```

3. Edit `data/user.conf` with your actual username and password:

   ```text
   your_oreilly_username@example.com
   your_password_here
   ```

### Method 2: SSO Authentication

1. Log in to O'Reilly using your organization's SSO
2. Navigate to <https://learning.oreilly.com/profile/> (or any authenticated page, really)
3. Extract cookies from your browser:
   - Open Developer Tools (F12)
   - Run this code snippet from Console to copy your cookies as JSON:

   ```javascript
    copy(JSON.stringify(document.cookie.split(';').map(c => c.split('=')).map(i => [i[0].trim(), i[1].trim()]).reduce((r, i) => {r[i[0]] = i[1]; return r;}, {})))
    ```

4. Save the cookies JSON to a file (e.g., `cookies.json`)

## Usage

### Download a single book

```bash
./oreilly-downloader.sh -b <book_id> -t <output_title> -f <format> [-m <login_method>] [-c <cookie_file>]
```

**Options:**

- `-b <book_id>`: Book ID or URL (required for single book download)
- `-t <output_title>`: Output filename without extension (required for single book download)
- `-f <format>`: Format to download: `pdf`, `epub`, or `both` (required)
- `-m <login_method>`: Authentication method: `user` (default) or `sso`
- `-c <cookie_file>`: JSON file with cookies (required for SSO login)
- `-h`: Display help message

### Download multiple books

```bash
./oreilly-downloader.sh -l <batch_file> -f <format> [-m <login_method>] [-c <cookie_file>]
```

**Options:**

- `-l <batch_file>`: Path to file containing list of books to download
- Other options same as Basic Usage

#### Batch File Format

Create a text file with one book per line in the format:

```text
<book_id>,<output_title>
```

Example (`books.txt`):

```text
9780321635754,Art of Computer Programming
9781492092506,Data Pipelines Pocket Reference
# Lines starting with # are comments
9781492087144,Building ML Pipelines
```

## Examples

### Username/Password Login

```bash
# Download a book in PDF format
./oreilly-downloader.sh -b 9780321635754 -t "Art_of_Computer_Programming" -f pdf

# Download a book in both PDF and EPUB formats
./oreilly-downloader.sh -b 9780321635754 -t "Art_of_Computer_Programming" -f both
```

### SSO Login

```bash
# Download a book in PDF format with SSO
./oreilly-downloader.sh -b 9780321635754 -t "Art_of_Computer_Programming" -f pdf -m sso -c cookies.json

# Download multiple books with SSO
./oreilly-downloader.sh -l books.txt -f pdf -m sso -c cookies.json
```

## Finding Book IDs

1. Browse to the book on O'Reilly Learning Platform
2. The book ID is in the URL: `https://learning.oreilly.com/library/view/book-title/<BOOK_ID>/`
3. For example: `https://learning.oreilly.com/library/view/art-of-computer/9780321635754/` → Book ID is `9780321635754`

## Notes

- For PDF conversion, the script uses:
  - Local Calibre on macOS if available (`/Applications/calibre.app/Contents/MacOS/ebook-convert`)
  - Docker-based conversion using `rappdw/ebook-convert` as fallback (*untested*)
- Temporary files are stored in the `download/tmp` directory
- Final downloaded files are saved to:
  - PDFs: `download/pdf/`
  - EPUBs: `download/epub/`

## Acknowledgements

- [kirinnee/oreilly-downloader](https://github.com/kirinnee/oreilly-downloader) for the Docker image used for downloading
- [Calibre Project](https://calibre-ebook.com) for the ebook conversion tools
- [rappdw/ebook-convert](https://github.com/rappdw/ebook-convert) for the Docker image used for conversion
