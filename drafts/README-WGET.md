# WGET - HTTP File Downloader for Amstrad CPC

Interactive HTTP file downloader for the Amstrad CPC with Net4CPC (W5100S) hardware.

## Features

- **Interactive URL Input** - Type the URL directly when running
- **DNS Resolution** - Automatically resolves hostnames
- **HTTP/1.0 Protocol** - Simple, reliable downloads
- **Automatic Filename** - Extracts filename from URL and converts to AMSDOS format
- **Progress Display** - Shows download progress with dots
- **Error Handling** - Clear error messages for common problems

## Building

```bash
cd drafts
./build_wget.sh
```

This creates `bin/WGET.BIN` and uses the included `WGET.BAS` loader.

## Files to Copy to CPC Disk

1. **WGET.BAS** - BASIC loader (prompts for URL)
2. **bin/WGET.BIN** - Compiled program
3. **N4C.CFG** - Network configuration (see `../N4C.CFG.example`)

## Usage

On your CPC:

```
RUN"WGET
```

You'll be prompted:

```
WGET for Net4CPC
================

Enter URL: http://example.com/files/test.txt

Host: example.com
Path: /files/test.txt
Save as: TEST.TXT

Continue? (Y/N) y
```

The program will:
1. Initialize network from N4C.CFG
2. Resolve hostname via DNS
3. Connect to server on port 80
4. Send HTTP GET request
5. Download file and save to disk

## URL Format

Supported formats:
- `http://hostname/path/to/file.ext`
- `hostname/path/to/file.ext` (assumes http://)

**Note:** HTTPS is not supported (no SSL/TLS on CPC)

## Filename Conversion

The program automatically converts filenames to AMSDOS format (8.3):
- `test.txt` → `TEST.TXT`
- `longfilename.html` → `LONGFILE.HTM`
- `data.json` → `DATA.JSO`

If no filename is found in the URL, it defaults to `INDEX.HTM`.

## Examples

### Download a text file
```
Enter URL: http://textfiles.com/internet/FAQ.txt
```
Saves as: `FAQ.TXT`

### Download from a path
```
Enter URL: http://www.example.com/downloads/manual.pdf
```
Saves as: `MANUAL.PDF`

### Root page (no filename)
```
Enter URL: http://example.com/
```
Saves as: `INDEX.HTM`

## Network Configuration (N4C.CFG)

Create a file named `N4C.CFG` on the same disk:

```
IP=192.168.1.100
MASK=255.255.255.0
GW=192.168.1.1
DNS=8.8.8.8
```

Adjust these to match your network settings.

## Technical Details

### Memory Layout

WGET.BAS writes URL components to memory before calling the binary:

- `&3E00`: Hostname (null-terminated, max 128 bytes)
- `&3E80`: Path (null-terminated, max 128 bytes)
- `&3F00`: AMSDOS filename (11 bytes, space-padded)
- `&3F0B`: Filename length (1 byte)

The binary loads at `&4000` and reads from these locations.

### HTTP Protocol

Uses HTTP/1.0 which provides:
- Simple request/response
- Server closes connection when done (clean EOF)
- No chunked encoding complexity

### Libraries Used

- **w5100.s** - W5100S hardware driver
- **dns_simple.s** - DNS resolver
- **n4c-netinit-kv.s** - Network configuration reader

## Troubleshooting

**"ERROR: N4C.CFG not found"**
- Ensure N4C.CFG is on the same disk as the program

**"ERROR: DNS resolution failed"**
- Check DNS server setting in N4C.CFG
- Verify network cable is connected
- Test with IP address if DNS server is unreachable

**"ERROR: Connection refused or timeout"**
- Server may be down or unreachable
- Check firewall settings
- Verify hostname is correct

**"ERROR: Disk write failed (full?)"**
- Disk is full - use a disk with more space
- File may be too large for available space

## Limitations

- HTTP only (no HTTPS/SSL)
- Port 80 only (hardcoded)
- No authentication support
- No HTTP/1.1 features (chunked encoding, keep-alive)
- Maximum URL length ~255 characters
- Files must fit in available RAM and disk space

## Future Enhancements

Potential improvements:
- [ ] Custom port support
- [ ] Resume partial downloads
- [ ] Multiple file queue
- [ ] HTTP redirect following
- [ ] Basic authentication
- [ ] Better progress indicator (percentage, bytes)

## License

Open source - use freely in your Amstrad CPC projects.

Part of n4c-nettools library: https://github.com/salvogendut/n4c-nettools
